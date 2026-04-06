import os
import json
import uuid
from datetime import datetime, timezone
from confluent_kafka import Producer

KAFKA_BROKERS = os.getenv("KAFKA_BROKERS", "localhost:9092")

producer = Producer({
    "bootstrap.servers": KAFKA_BROKERS,
    "client.id":         "inventory-api-producer",
    "retries":           3,
    "retry.backoff.ms":  500,
})


def delivery_report(err, msg):
    if err:
        print(f"[Kafka] Delivery failed for topic {msg.topic()}: {err}")
    else:
        print(f"[Kafka] Delivered to {msg.topic()} "
              f"partition [{msg.partition()}] offset {msg.offset()}")


def publish_inventory_updated(
    product_id:    str,
    product_name:  str,
    previous_stock: int,
    new_stock:     int,
    reason:        str,
):
    """
    Publishes an inventory.updated event to Kafka.

    Consumed by:
      - Sales API — updates its cached stock levels so the
        frontend shows accurate counts without a full page reload

    Event shape matches the Avro schema in config/kafka/schemas.json

    reason examples:
      - 'restock'         — inventory team received new stock
      - 'order-reserved'  — stock reserved after an order was placed
      - 'adjustment'      — manual correction by inventory team
      - 'new-product'     — a new product was added (Scenario 3)
    """
    event = {
        "eventId":       str(uuid.uuid4()),
        "productId":     product_id,
        "productName":   product_name,
        "previousStock": previous_stock,
        "newStock":      new_stock,
        "reason":        reason,
        "updatedAt":     datetime.now(timezone.utc).isoformat(),
    }

    producer.produce(
        topic    = "inventory.updated",
        key      = product_id,
        value    = json.dumps(event),
        callback = delivery_report,
    )
    producer.flush()
    return event
