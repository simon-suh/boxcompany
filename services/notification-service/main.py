import os
import json
import time
from confluent_kafka import Consumer, KafkaError

from notifications import (
    send_order_confirmation_email,
    send_order_confirmation_sms,
    send_shipment_notification_email,
    send_shipment_notification_sms,
)

# ── Config ─────────────────────────────────────────────────────────────────────
KAFKA_BROKERS     = os.getenv("KAFKA_BROKERS", "localhost:9092")
NOTIFICATION_MODE = os.getenv("NOTIFICATION_MODE", "log")


# ── Kafka consumer ─────────────────────────────────────────────────────────────
def create_consumer() -> Consumer:
    return Consumer({
        "bootstrap.servers":  KAFKA_BROKERS,
        "group.id":           "notification-service-consumer-group",
        "auto.offset.reset":  "earliest",
        # Manual commits — only mark a message as processed after
        # notification has been sent (or logged in dev mode)
        "enable.auto.commit": False,
    })


# ── Event handlers ─────────────────────────────────────────────────────────────

def handle_order_created(event: dict):
    """
    Handles an orders.created event.

    Sends:
    - Order confirmation email (if customer email provided)
    - Order confirmation SMS (if customer phone provided)

    If neither email nor phone is provided, logs a warning and skips.
    In NOTIFICATION_MODE=log, prints to console instead of sending.
    """
    order_number  = event.get("orderNumber", "UNKNOWN")
    customer_name = event.get("customerName", "Customer")
    customer_email= event.get("customerEmail")
    customer_phone= event.get("customerPhone")
    items         = event.get("items", [])

    print(f"[Notification] Processing order confirmation for {order_number}")

    if customer_email:
        send_order_confirmation_email(
            to_email      = customer_email,
            customer_name = customer_name,
            order_number  = order_number,
            items         = items,
        )
    else:
        print(f"[Notification] No email for {order_number} — skipping email")

    if customer_phone:
        send_order_confirmation_sms(
            to_phone      = customer_phone,
            customer_name = customer_name,
            order_number  = order_number,
        )
    else:
        print(f"[Notification] No phone for {order_number} — skipping SMS")


def handle_order_shipped(event: dict):
    """
    Handles an orders.shipped event.

    Sends:
    - Shipment notification email with tracking info (if email provided)
    - Shipment notification SMS with tracking info (if phone provided)

    In NOTIFICATION_MODE=log, prints to console instead of sending.
    """
    order_number    = event.get("orderNumber", "UNKNOWN")
    customer_name   = event.get("customerName", "Customer")
    customer_email  = event.get("customerEmail")
    customer_phone  = event.get("customerPhone")
    carrier         = event.get("carrier", "Unknown carrier")
    tracking_number = event.get("trackingNumber", "N/A")
    shipped_at      = event.get("shippedAt", "N/A")

    print(f"[Notification] Processing shipment notification for {order_number}")

    if customer_email:
        send_shipment_notification_email(
            to_email        = customer_email,
            customer_name   = customer_name,
            order_number    = order_number,
            carrier         = carrier,
            tracking_number = tracking_number,
            shipped_at      = shipped_at,
        )
    else:
        print(f"[Notification] No email for {order_number} — skipping email")

    if customer_phone:
        send_shipment_notification_sms(
            to_phone        = customer_phone,
            customer_name   = customer_name,
            order_number    = order_number,
            carrier         = carrier,
            tracking_number = tracking_number,
        )
    else:
        print(f"[Notification] No phone for {order_number} — skipping SMS")


# ── Main loop ──────────────────────────────────────────────────────────────────

def main():
    """
    Main entry point — runs the Kafka consumer loop indefinitely.

    Unlike the other three services which are FastAPI apps with background
    consumer threads, the Notification Service IS the consumer. There is
    no REST API — just this loop running until the container stops.

    Retries connection to Kafka on startup with a delay — Kafka may not
    be fully ready when this container starts even with depends_on health
    checks, so a small retry loop provides extra resilience.
    """
    print(f"[Startup] Notification Service starting")
    print(f"[Startup] Kafka brokers: {KAFKA_BROKERS}")
    print(f"[Startup] Notification mode: {NOTIFICATION_MODE}")

    # Retry connecting to Kafka up to 10 times on startup
    consumer     = None
    max_retries  = 10
    retry_delay  = 5

    for attempt in range(1, max_retries + 1):
        try:
            consumer = create_consumer()
            consumer.subscribe(["orders.created", "orders.shipped"])
            print(f"[Kafka] Connected — subscribed to: orders.created, orders.shipped")
            break
        except Exception as e:
            print(f"[Kafka] Connection attempt {attempt}/{max_retries} failed: {e}")
            if attempt < max_retries:
                print(f"[Kafka] Retrying in {retry_delay}s...")
                time.sleep(retry_delay)
            else:
                print(f"[Kafka] Could not connect after {max_retries} attempts. Exiting.")
                raise

    print("[Notification Service] Listening for events...")

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
                    handle_order_created(event)

                elif topic == "orders.shipped":
                    handle_order_shipped(event)

                # Commit offset only after notification was sent/logged
                consumer.commit(msg)

            except Exception as e:
                print(f"[Kafka] Error processing message from {topic}: {e}")

    except KeyboardInterrupt:
        print("[Notification Service] Shutting down...")
    finally:
        consumer.close()
        print("[Notification Service] Consumer closed.")


if __name__ == "__main__":
    main()
