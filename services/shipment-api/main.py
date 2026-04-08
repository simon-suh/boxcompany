import os
import uuid
from datetime import datetime, timezone
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional

from dynamodb import get_all_orders, get_order, update_tracking
from kafka import publish_order_shipped, publish_error_reported, start_consumers

# ── App setup ─────────────────────────────────────────────────────────────────
app = FastAPI(
    title       = "BoxCo Shipment API",
    description = "Manages order fulfillment and tracking for the Shipment team.",
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

SCENARIO = int(os.getenv("SCENARIO", "1"))


# ── Start Kafka consumers on app startup ──────────────────────────────────────
@app.on_event("startup")
async def startup_event():
    """
    Starts the Kafka consumer background thread when FastAPI starts.
    This is what makes the shipment service reactive — it immediately
    begins listening for orders.created and errors.reported events
    without any manual intervention.
    """
    start_consumers()
    print(f"[Startup] Shipment API running — Scenario {SCENARIO}")


# ── Pydantic models ────────────────────────────────────────────────────────────
class TrackingRequest(BaseModel):
    carrier:         str
    tracking_number: str
    shipped_at:      Optional[str] = None


class ErrorReportRequest(BaseModel):
    order_number: Optional[str] = None
    issue_type:   str
    description:  str
    notify_teams: Optional[list[str]] = []


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok", "service": "shipment-api", "scenario": SCENARIO}


@app.get("/orders")
def get_orders():
    """
    Returns all orders from the DynamoDB shipments table.
    Used by the Shipment frontend dashboard to display
    incoming orders and their current status.

    Orders arrive here via the Kafka consumer — not via
    a direct call from the Sales API. This is the event-driven
    decoupling in action.
    """
    orders = get_all_orders()
    return {"orders": orders, "total": len(orders)}


@app.get("/orders/{order_id}")
def get_single_order(order_id: str):
    """
    Returns a single order by orderId.
    """
    order = get_order(order_id)
    if not order:
        raise HTTPException(
            status_code = 404,
            detail      = f"Order '{order_id}' not found."
        )
    return order


@app.post("/orders/{order_id}/track")
def upload_tracking(order_id: str, request: TrackingRequest):
    """
    Uploads tracking information for an order.

    Steps:
    1. Verify the order exists in DynamoDB
    2. Update the order with carrier, tracking number, and ship date
    3. Publish orders.shipped event to Kafka
       → Notification Service consumes this and sends
         tracking info to the customer via email and SMS

    This is the primary action the shipment team takes
    after physically shipping an order.
    """
    order = get_order(order_id)
    if not order:
        raise HTTPException(
            status_code = 404,
            detail      = f"Order '{order_id}' not found."
        )

    if order.get("status") == "shipped":
        raise HTTPException(
            status_code = 400,
            detail      = f"Order '{order_id}' has already been marked as shipped."
        )

    shipped_at = request.shipped_at or datetime.now(timezone.utc).isoformat()

    updated = update_tracking(
        order_id        = order_id,
        carrier         = request.carrier,
        tracking_number = request.tracking_number,
        shipped_at      = shipped_at,
    )

    if not updated:
        raise HTTPException(
            status_code = 500,
            detail      = "Failed to update tracking information."
        )

    # Publish orders.shipped to Kafka
    # Notification Service will consume this and alert the customer
    event = publish_order_shipped(
        order           = order,
        carrier         = request.carrier,
        tracking_number = request.tracking_number,
        shipped_at      = shipped_at,
    )

    return {
        "success":        True,
        "order_id":       order_id,
        "order_number":   order.get("orderNumber"),
        "carrier":        request.carrier,
        "tracking_number": request.tracking_number,
        "shipped_at":     shipped_at,
        "kafka_event":    event["eventId"],
        "message":        f"Tracking uploaded for {order.get('orderNumber')}. "
                          f"Customer notification sent via Kafka.",
    }


@app.post("/errors")
def report_error(request: ErrorReportRequest):
    """
    Accepts an error report from the Shipment team frontend.
    Publishes to errors.reported Kafka topic.

    This is how the shipment team notifies other teams of issues —
    for example reporting that medium boxes are out of stock
    and orders cannot be fulfilled.

    The event is consumed by:
      - Sales team API  (if 'sales' in notifyTeams)
      - Inventory team API (if 'inventory' in notifyTeams)
      - Dev team alerting (if 'dev' in notifyTeams)
    """
    report_id = str(uuid.uuid4())

    # If an order number is provided, update its status to 'issue'
    if request.order_number:
        from dynamodb import dynamodb
        try:
            orders_table = dynamodb.Table("shipments")
            # Find the order by orderNumber
            response = orders_table.scan(
                FilterExpression="orderNumber = :order_num",
                ExpressionAttributeValues={":order_num": request.order_number}
            )
            if response.get("Items"):
                order = response["Items"][0]
                # Update the order status to 'issue'
                orders_table.update_item(
                    Key={"orderId": order["orderId"]},
                    UpdateExpression="SET #status = :status",
                    ExpressionAttributeNames={"#status": "status"},
                    ExpressionAttributeValues={":status": "issue"}
                )
        except Exception as e:
            print(f"[Error] Could not update order status: {e}")

    event = publish_error_reported({
        "id":           report_id,
        "order_number": request.order_number,
        "issue_type":   request.issue_type,
        "description":  request.description,
        "notify_teams": request.notify_teams,
    })

    return {
        "success":     True,
        "report_id":   report_id,
        "message":     f"Error report submitted by shipment team. "
                       f"Kafka event published to errors.reported. "
                       f"Notifying: {', '.join(request.notify_teams or [])}",
    }


@app.get("/errors")
def get_error_reports():
    """
    Returns error reports assigned to the shipment team.
    These arrive via the Kafka consumer listening to errors.reported.
    Used by the Shipment frontend to display the issues panel.
    """
    from dynamodb import dynamodb
    try:
        errors_table = dynamodb.Table("shipment_errors")
        response     = errors_table.scan()
        items        = response.get("Items", [])
        return {
            "errors": sorted(items, key=lambda x: x.get("createdAt", ""), reverse=True),
            "total":  len(items),
        }
    except Exception as e:
        return {"errors": [], "total": 0, "note": str(e)}
