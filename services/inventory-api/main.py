from prometheus_client import make_asgi_app
import os
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional

from dynamodb import get_all_products, get_product, update_stock, add_product
from kafka_producer import publish_inventory_updated
from kafka_consumer import start_consumer

# ── App setup ─────────────────────────────────────────────────────────────────
app = FastAPI(
    title       = "BoxCo Inventory API",
    description = "Manages stock levels for the Inventory team.",
    version     = "1.0.0",
)

app.mount("/static", StaticFiles(directory="static"), name="static")

@app.get("/")
def serve_frontend():
    return FileResponse("static/index.html")

app.add_middleware(
    CORSMiddleware,
    allow_origins = ["*"],
    allow_methods = ["*"],
    allow_headers = ["*"],
)

# ── Scenario flag ──────────────────────────────────────────────────────────────
# Scenario 1 + 2: small, medium, large boxes only
# Scenario 3:     XL boxes added
SCENARIO = int(os.getenv("SCENARIO", "1"))


# ── Start Kafka consumer on app startup ──────────────────────────────────────
@app.on_event("startup")
async def startup_event():
    """
    Starts the Kafka consumer background thread when FastAPI starts.
    The consumer listens for orders.created events and automatically
    decrements stock when orders are placed.
    """
    start_consumer()
    print(f"[Startup] Inventory API running — Scenario {SCENARIO}")


# ── Pydantic models ────────────────────────────────────────────────────────────
class StockUpdateRequest(BaseModel):
    new_stock: int
    reason:    Optional[str] = "adjustment"


class NewProductRequest(BaseModel):
    product_id:   str
    name:         str
    initial_stock: int


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    """Health check — used by Docker and Kubernetes."""
    return {"status": "ok", "service": "inventory-api", "scenario": SCENARIO}


@app.get("/inventory")
def get_inventory():
    """
    Returns all products and current stock levels.

    Called by:
      - Inventory frontend — to display the stock dashboard
      - Sales API — proxied to the Sales frontend to show
        live stock counts on the order form
    """
    products = get_all_products()
    # Filter out XL box for scenarios 1 and 2
    if SCENARIO < 3:
        products = [p for p in products if p.get("productId") != "xl-box"]
    return {
        "products": [
            {
                "productId": p.get("productId"),
                "name":      p.get("name"),
                "stock":     int(p.get("stock", 0)),
                "reserved":  int(p.get("reserved", 0)),
                "available": int(p.get("stock", 0)) - int(p.get("reserved", 0)),
            }
            for p in products
        ]
    }


@app.get("/inventory/{product_id}")
def get_single_product(product_id: str):
    """
    Returns stock info for a single product.

    Called by:
      - Sales API check_stock() function before accepting an order
        to verify quantity requested does not exceed available stock
    """
    product = get_product(product_id)
    if not product:
        raise HTTPException(
            status_code = 404,
            detail      = f"Product '{product_id}' not found in inventory."
        )
    stock    = int(product.get("stock", 0))
    reserved = int(product.get("reserved", 0))
    return {
        "productId": product.get("productId"),
        "name":      product.get("name"),
        "stock":     stock,
        "reserved":  reserved,
        "available": stock - reserved,
    }


@app.put("/inventory/{product_id}")
def update_product_stock(product_id: str, request: StockUpdateRequest):
    """
    Updates stock count for a product.

    Called by:
      - Inventory frontend "Update stock" button when the warehouse
        team receives a new shipment
      - Also used internally when an order reserves stock

    Publishes inventory.updated event to Kafka so the Sales API
    can update its cached stock levels.
    """
    product = get_product(product_id)
    if not product:
        raise HTTPException(
            status_code = 404,
            detail      = f"Product '{product_id}' not found."
        )

    if request.new_stock < 0:
        raise HTTPException(
            status_code = 400,
            detail      = "Stock cannot be negative."
        )

    previous_stock = int(product.get("stock", 0))
    updated        = update_stock(product_id, request.new_stock)

    if not updated:
        raise HTTPException(
            status_code = 500,
            detail      = "Failed to update stock."
        )

    # Publish inventory.updated event to Kafka
    event = publish_inventory_updated(
        product_id     = product_id,
        product_name   = product.get("name", product_id),
        previous_stock = previous_stock,
        new_stock      = request.new_stock,
        reason         = request.reason or "adjustment",
    )

    return {
        "success":        True,
        "product_id":     product_id,
        "previous_stock": previous_stock,
        "new_stock":      request.new_stock,
        "reason":         request.reason,
        "kafka_event":    event["eventId"],
        "message":        f"Stock updated for {product.get('name')}. "
                          f"Kafka event published to inventory.updated.",
    }


@app.post("/inventory")
def create_product(request: NewProductRequest):
    """
    Adds a new product to inventory.

    Used in Scenario 3 when XL boxes are introduced.
    Dev team calls this endpoint after deploying the new code
    to seed the new product into DynamoDB.

    Publishes inventory.updated with reason 'new-product'
    so the Sales API immediately knows the new product exists.
    """
    if SCENARIO < 3:
        raise HTTPException(
            status_code = 403,
            detail      = "Adding new products is only available in Scenario 3+."
        )

    try:
        product = add_product(
            product_id = request.product_id,
            name       = request.name,
            stock      = request.initial_stock,
        )
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))

    event = publish_inventory_updated(
        product_id     = request.product_id,
        product_name   = request.name,
        previous_stock = 0,
        new_stock      = request.initial_stock,
        reason         = "new-product",
    )

    return {
        "success":     True,
        "product":     product,
        "kafka_event": event["eventId"],
        "message":     f"New product '{request.name}' added with "
                       f"{request.initial_stock} units in stock.",
    }

# Prometheus metrics
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)
