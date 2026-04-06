import os
import json
import uuid
import threading
from datetime import datetime, timezone
from confluent_kafka import Producer, Consumer, KafkaError

from dynamodb import save_order, save_error_report

KAFKA_BROKERS = os.getenv("KAFKA_BROKERS", "localhost:9092")

# ── Producer ───────────────────────────────────────────────────────────────────
producer = Producer({
    "bootstrap.servers": KAFKA_BROKERS,
    "client.id":         "shipment-api-producer",
    "retries":           3,
    "retry.backoff.ms":  500,
})


def delivery_report(err, msg):
    if err:
        print(f"[Kafka] Delivery failed for topic {msg.topic()}: {err}")
    else:
        print(f"[Kafka] Delivered to {msg.topic()} "
              f"partition [{msg.partition()}] offset {msg.offset()}")


def publish_order_shipped(order: dict, carrier: str, tracking_number: str, shipped_at: str):
    """
    Publishes an orders.shipped event to Kafka.

    Consumed by:
      - Notification Service — sends tracking info to customer
        via email and SMS

    Event shape matches the Avro schema in config/kafka/schemas.json
    """
    event = {
        "eventId":        str(uuid.uuid4()),
        "orderNumber":    order.get("orderNumber"),
        "orderId":        order.get("orderId"),
        "customerName":   order.get("customerName"),
        "customerEmail":  order.get("customerEmail"),
        "customerPhone":  order.get("customerPhone"),
        "carrier":        carrier,
        "trackingNumber": tracking_number,
        "shippedAt":      shipped_at,
    }

    producer.produce(
        topic    = "orders.shipped",
        key      = order.get("orderNumber"),
        value    = json.dumps(event),
        callback = delivery_report,
    )
    producer.flush()
    return event


def publish_error_reported(report: dict):
    """
    Publishes an errors.reported event to Kafka on behalf
    of the shipment team when they report an issue.
    """
    event = {
        "eventId":     str(uuid.uuid4()),
        "reportId":    report["id"],
        "orderNumber": report.get("order_number"),
        "reportedBy":  "shipment",
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


# ── Consumer ───────────────────────────────────────────────────────────────────
# Runs in a background thread so it doesn't block the FastAPI server.
# Listens to two topics simultaneously:
#   - orders.created   — saves new orders to DynamoDB shipments table
#   - errors.reported  — saves error reports assigned to shipment team

def start_consumers():
    """
    Starts the Kafka consumer in a background thread.
    Called once when the FastAPI app starts up.
    """
    thread = threading.Thread(target=_consume_loop, daemon=True)
    thread.start()
    print("[Kafka] Shipment consumer started in background thread")


def _consume_loop():
    consumer = Consumer({
        "bootstrap.servers":  KAFKA_BROKERS,
        "group.id":           "shipment-api-consumer-group",
        "auto.offset.reset":  "earliest",
        # Commit offsets manually so we only mark a message as processed
        # after we've successfully saved it to DynamoDB
        "enable.auto.commit": False,
    })

    consumer.subscribe(["orders.created", "errors.reported"])
    print("[Kafka] Subscribed to: orders.created, errors.reported")

    try:
        while True:
            msg = consumer.poll(timeout=1.0)

            if msg is None:
                continue

            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    continue
                print(f"[Kafka] Consumer error: {msg.error()}")
                continue

            topic = msg.topic()
            try:
                event = json.loads(msg.value().decode("utf-8"))

                if topic == "orders.created":
                    _handle_order_created(event)

                elif topic == "errors.reported":
                    _handle_error_reported(event)

                # Manually commit offset after successful processing
                consumer.commit(msg)

            except Exception as e:
                print(f"[Kafka] Error processing message from {topic}: {e}")

    finally:
        consumer.close()


def _handle_order_created(event: dict):
    """
    Handles an orders.created event.
    Saves the order to the DynamoDB shipments table so it
    appears on the shipment team's dashboard.
    """
    order = {
        "orderId":       event.get("orderId"),
        "orderNumber":   event.get("orderNumber"),
        "customerName":  event.get("customerName"),
        "customerEmail": event.get("customerEmail"),
        "customerPhone": event.get("customerPhone"),
        "items":         json.dumps(event.get("items", [])),
        "paymentMethod": event.get("paymentMethod"),
        "status":        "pending",
        "createdAt":     event.get("createdAt"),
    }
    save_order(order)
    print(f"[Kafka] Order {order['orderNumber']} saved to shipments table")


def _handle_error_reported(event: dict):
    """
    Handles an errors.reported event.
    Only saves the report if shipment team is in the notifyTeams list.
    Surfaces the report on the shipment team's dashboard.
    """
    notify_teams = event.get("notifyTeams", [])
    if "shipment" not in notify_teams:
        return

    report = {
        "reportId":    event.get("reportId"),
        "orderNumber": event.get("orderNumber"),
        "reportedBy":  event.get("reportedBy"),
        "issueType":   event.get("issueType"),
        "description": event.get("description"),
        "status":      "open",
        "createdAt":   event.get("createdAt"),
    }
    save_error_report(report)
    print(f"[Kafka] Error report {report['reportId']} saved for shipment team")
