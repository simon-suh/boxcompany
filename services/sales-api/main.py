import os
import uuid
import random
import httpx
from datetime import datetime, timezone
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
from sqlalchemy.orm import Session

from database import get_db, Customer, Order, OrderItem, ErrorReport
from kafka_producer import publish_order_created, publish_error_reported

# ── App setup ─────────────────────────────────────────────────────────────────
app = FastAPI(
    title       = "BoxCo Sales API",
    description = "Handles order submission for the Sales team.",
    version     = "1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins  = ["*"],   # tighten this in production
    allow_methods  = ["*"],
    allow_headers  = ["*"],
)

# ── Scenario flag ──────────────────────────────────────────────────────────────
# Controls which version of the stock-check logic runs.
# Set via the SCENARIO environment variable in docker-compose.yml
# Scenario 1: stock check is broken for medium boxes (bug exists)
# Scenario 2: stock check works correctly for all products
# Scenario 3: XL boxes added, stock check works for all products
SCENARIO = int(os.getenv("SCENARIO", "1"))

INVENTORY_API_URL = os.getenv("INVENTORY_API_URL", "http://inventory-api:3003")


# ── Pydantic models (request/response shapes) ─────────────────────────────────
class OrderItemRequest(BaseModel):
    product_id:   str
    product_name: str
    quantity:     int


class OrderRequest(BaseModel):
    customer_name:  str
    customer_email: Optional[str] = None
    customer_phone: Optional[str] = None
    items:          list[OrderItemRequest]
    payment_method: str


class ErrorReportRequest(BaseModel):
    order_number: Optional[str] = None
    issue_type:   str
    description:  str
    notify_teams: Optional[list[str]] = []


# ── Helper: generate order number ─────────────────────────────────────────────
def generate_order_number() -> str:
    return f"ORD-{random.randint(10000, 99999)}"


# ── Helper: check stock via Inventory API ─────────────────────────────────────
async def check_stock(product_id: str, quantity_requested: int) -> dict:
    """
    Calls the Inventory API to get current stock for a product.
    Returns a dict with 'available' (int) and 'in_stock' (bool).

    ── SCENARIO 1 BUG ──────────────────────────────────────────
    Medium boxes bypass the stock check entirely — the function
    returns in_stock=True regardless of actual inventory.
    This simulates the bug that gets fixed in Scenario 2.

    ── SCENARIO 2 FIX ──────────────────────────────────────────
    All products including medium boxes go through the real
    stock check. Orders exceeding available stock are rejected.
    ────────────────────────────────────────────────────────────
    """
    # SCENARIO 1 BUG: medium boxes skip the stock check
    if SCENARIO == 1 and product_id == "medium-box":
        print(f"[Scenario 1] Skipping stock check for {product_id} — known bug")
        return {"available": 0, "in_stock": True}

    # All other products (and all products in Scenario 2+) check real inventory
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(
                f"{INVENTORY_API_URL}/inventory/{product_id}"
            )
            if response.status_code == 200:
                data      = response.json()
                available = data.get("stock", 0)
                return {
                    "available": available,
                    "in_stock":  available >= quantity_requested,
                }
            else:
                # If inventory API is unreachable, fail safe — reject the order
                print(f"[Warning] Inventory API returned {response.status_code} "
                      f"for {product_id}")
                return {"available": 0, "in_stock": False}
    except Exception as e:
        print(f"[Warning] Could not reach Inventory API: {e}")
        return {"available": 0, "in_stock": False}


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    """Health check — used by Docker and Kubernetes to verify the service is up."""
    return {"status": "ok", "service": "sales-api", "scenario": SCENARIO}


@app.get("/inventory")
async def get_inventory():
    """
    Returns current stock levels for all products by proxying
    the Inventory API. Used by the Sales frontend to show
    live stock counts next to each product on the order form.
    """
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(f"{INVENTORY_API_URL}/inventory")
            return response.json()
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Inventory API unavailable: {e}")


@app.post("/orders")
async def create_order(request: OrderRequest, db: Session = Depends(get_db)):
    """
    Accepts a new order from the Sales frontend.

    Steps:
    1. Validate that at least one item is included
    2. Check stock for each item via Inventory API
       (Scenario 1: medium boxes bypass this check — bug)
    3. Save customer and order to PostgreSQL
    4. Publish orders.created event to Kafka
    5. Return order confirmation
    """

    # ── Step 1: Basic validation ───────────────────────────────────────────────
    if not request.items:
        raise HTTPException(status_code=400, detail="Order must contain at least one item.")

    # ── Step 2: Stock check for each item ─────────────────────────────────────
    stock_errors = []
    for item in request.items:
        stock = await check_stock(item.product_id, item.quantity)
        if not stock["in_stock"]:
            stock_errors.append(
                f"{item.product_name}: requested {item.quantity}, "
                f"only {stock['available']} available."
            )

    if stock_errors:
        raise HTTPException(
            status_code = 400,
            detail      = {
                "message": "One or more items are out of stock or exceed available quantity.",
                "errors":  stock_errors,
            }
        )

    # ── Step 3: Save to PostgreSQL ────────────────────────────────────────────
    customer_id  = str(uuid.uuid4())
    order_id     = str(uuid.uuid4())
    order_number = generate_order_number()

    customer = Customer(
        id    = customer_id,
        name  = request.customer_name,
        email = request.customer_email,
        phone = request.customer_phone,
    )
    db.add(customer)

    order = Order(
        id             = order_id,
        order_number   = order_number,
        customer_id    = customer_id,
        payment_method = request.payment_method,
        status         = "pending",
    )
    db.add(order)

    order_items = []
    for item in request.items:
        order_item = OrderItem(
            id           = str(uuid.uuid4()),
            order_id     = order_id,
            product_id   = item.product_id,
            product_name = item.product_name,
            quantity     = item.quantity,
        )
        db.add(order_item)
        order_items.append({
            "product_id":   item.product_id,
            "product_name": item.product_name,
            "quantity":     item.quantity,
        })

    db.commit()

    # ── Step 4: Publish to Kafka ───────────────────────────────────────────────
    event = publish_order_created(
        order    = {"id": order_id, "order_number": order_number, "payment_method": request.payment_method},
        customer = {"name": request.customer_name, "email": request.customer_email, "phone": request.customer_phone},
        items    = order_items,
    )

    # ── Step 5: Return confirmation ────────────────────────────────────────────
    return {
        "success":      True,
        "order_number": order_number,
        "order_id":     order_id,
        "customer":     request.customer_name,
        "items":        order_items,
        "payment":      request.payment_method,
        "created_at":   datetime.now(timezone.utc).isoformat(),
        "kafka_event":  event["eventId"],
        "message":      f"Order {order_number} created successfully. "
                        f"Confirmation sent to customer.",
    }


@app.post("/errors")
async def report_error(request: ErrorReportRequest, db: Session = Depends(get_db)):
    """
    Accepts an error report from any team's frontend.
    Saves it to PostgreSQL and publishes to errors.reported Kafka topic.
    The responsible team's service consumes this event and surfaces
    it in their dashboard.
    """
    report_id = str(uuid.uuid4())

    report = ErrorReport(
        id           = report_id,
        order_number = request.order_number,
        reported_by  = "sales",
        issue_type   = request.issue_type,
        description  = request.description,
        notify_teams = request.notify_teams,
        status       = "open",
    )
    db.add(report)
    db.commit()

    event = publish_error_reported({
        "id":           report_id,
        "order_number": request.order_number,
        "reported_by":  "sales",
        "issue_type":   request.issue_type,
        "description":  request.description,
        "notify_teams": request.notify_teams,
    })

    return {
        "success":   True,
        "report_id": report_id,
        "message":   f"Error report submitted. Kafka event published to errors.reported. "
                     f"Notifying: {', '.join(request.notify_teams or [])}",
    }


@app.get("/orders")
def get_orders(db: Session = Depends(get_db)):
    """
    Returns all orders with their items and customer info.
    Used by the Sales frontend to display order history.
    """
    orders = db.query(Order).order_by(Order.created_at.desc()).all()
    result = []
    for order in orders:
        customer = db.query(Customer).filter(Customer.id == order.customer_id).first()
        items    = db.query(OrderItem).filter(OrderItem.order_id == order.id).all()
        result.append({
            "order_number":   order.order_number,
            "customer_name":  customer.name if customer else "Unknown",
            "customer_email": customer.email if customer else None,
            "customer_phone": customer.phone if customer else None,
            "items": [
                {
                    "product_id":   i.product_id,
                    "product_name": i.product_name,
                    "quantity":     i.quantity,
                }
                for i in items
            ],
            "payment_method": order.payment_method,
            "status":         order.status,
            "created_at":     order.created_at.isoformat() if order.created_at else None,
        })
    return result
