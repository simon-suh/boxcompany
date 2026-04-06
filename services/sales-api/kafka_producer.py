import os
import json
import uuid
from datetime import datetime, timezone
from confluent_kafka import Producer

# ── Kafka connection ───────────────────────────────────────────────────────────
KAFKA_BROKERS = os.getenv("KAFKA_BROKERS", "localhost:9092")

producer = Producer({
    "bootstrap.servers": KAFKA_BROKERS,
    "client.id":         "sales-api-producer",
    # Retry up to 3 times if a message fails to deliver
    "retries":           3,
    "retry.backoff.ms":  500,
})


def delivery_report(err, msg):
    """
    Callback fired after each message is delivered (or fails).
    Logs the result — in production this would feed into your
    observability stack (Grafana / OpenSearch).
    """
    if err:
        print(f"[Kafka] Delivery failed for topic {msg.topic()}: {err}")
    else:
        print(f"[Kafka] Delivered to {msg.topic()} "
              f"partition [{msg.partition()}] offset {msg.offset()}")


def publish_order_created(order: dict, customer: dict, items: list):
    """
    Publishes an orders.created event to Kafka.

    Consumed by:
      - Shipment API  — to display the order on the shipment dashboard
      - Notification Service — to send confirmation email/SMS to customer

    Event shape matches the Avro schema in config/kafka/schemas.json
    """
    event = {
        "eventId":       str(uuid.uuid4()),
        "orderNumber":   order["order_number"],
        "orderId":       order["id"],
        "customerName":  customer["name"],
        "customerEmail": customer.get("email"),
        "customerPhone": customer.get("phone"),
        "items": [
            {
                "productId":   item["product_id"],
                "productName": item["product_name"],
                "quantity":    item["quantity"],
            }
            for item in items
        ],
        "paymentMethod": order["payment_method"],
        "status":        "pending",
        "createdAt":     datetime.now(timezone.utc).isoformat(),
    }

    producer.produce(
        topic     = "orders.created",
        key       = order["order_number"],   # partition key — same order always goes to same partition
        value     = json.dumps(event),
        callback  = delivery_report,
    )
    producer.flush()
    return event


def publish_error_reported(report: dict):
    """
    Publishes an errors.reported event to Kafka.

    Consumed by:
      - The responsible team's API (based on notifyTeams field)
      - Dev team alerting pipeline

    Event shape matches the Avro schema in config/kafka/schemas.json
    """
    event = {
        "eventId":     str(uuid.uuid4()),
        "reportId":    report["id"],
        "orderNumber": report.get("order_number"),
        "reportedBy":  report["reported_by"],
        "issueType":   report["issue_type"],
        "description": report["description"],
        "notifyTeams": report.get("notify_teams", []),
        "createdAt":   datetime.now(timezone.utc).isoformat(),
    }

    producer.produce(
        topic    = "errors.reported",
        key      = report["id"],
        value    = json.dumps(event),
        callback = delivery_report,
    )
    producer.flush()
    return event
