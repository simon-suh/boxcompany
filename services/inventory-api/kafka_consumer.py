import os
import json
import threading
from confluent_kafka import Consumer, KafkaError

from dynamodb import get_product, update_stock

KAFKA_BROKERS = os.getenv("KAFKA_BROKERS", "localhost:9092")


def start_consumer():
    """
    Starts the Kafka consumer in a background thread.
    Called once when the FastAPI app starts up.
    """
    thread = threading.Thread(target=_consume_loop, daemon=True)
    thread.start()
    print("[Kafka] Inventory consumer started in background thread")


def _consume_loop():
    consumer = Consumer({
        "bootstrap.servers":  KAFKA_BROKERS,
        "group.id":           "inventory-api-consumer-group",
        "auto.offset.reset":  "earliest",
        "enable.auto.commit": False,
    })

    consumer.subscribe(["orders.created"])
    print("[Kafka] Subscribed to: orders.created")

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

            try:
                event = json.loads(msg.value().decode("utf-8"))
                _handle_order_created(event)
                consumer.commit(msg)

            except Exception as e:
                print(f"[Kafka] Error processing orders.created event: {e}")

    finally:
        consumer.close()


def _handle_order_created(event: dict):
    """
    Handles an orders.created event.
    Decrements stock for each item in the order.
    """
    items = event.get("items", [])
    order_number = event.get("orderNumber", "unknown")

    for item in items:
        product_id = item.get("productId")
        quantity = item.get("quantity", 0)

        if not product_id or quantity <= 0:
            continue

        try:
            product = get_product(product_id)
            if not product:
                print(f"[Kafka] Product {product_id} not found for order {order_number}")
                continue

            current_stock = int(product.get("stock", 0))
            new_stock = max(0, current_stock - quantity)  # Don't go below 0

            update_stock(product_id, new_stock)
            print(f"[Kafka] Decremented {product_id}: {current_stock} → {new_stock} "
                  f"(order {order_number}, qty {quantity})")

        except Exception as e:
            print(f"[Kafka] Failed to decrement stock for {product_id}: {e}")
