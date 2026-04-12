import os
import json
import threading
from confluent_kafka import Consumer, KafkaError
from sqlalchemy.orm import Session

from database import get_db, Order

KAFKA_BROKERS = os.getenv("KAFKA_BROKERS", "localhost:9092")


def start_consumer():
    """
    Starts the Kafka consumer in a background thread.
    Called once when the FastAPI app starts up.
    """
    thread = threading.Thread(target=_consume_loop, daemon=True)
    thread.start()
    print("[Kafka] Sales consumer started in background thread")


def _consume_loop():
    consumer = Consumer({
        "bootstrap.servers":  KAFKA_BROKERS,
        "group.id":           "sales-api-consumer-group",
        "auto.offset.reset":  "earliest",
        "enable.auto.commit": False,
    })

    consumer.subscribe(["orders.shipped"])
    print("[Kafka] Subscribed to: orders.shipped")

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
                _handle_order_shipped(event)
                consumer.commit(msg)

            except Exception as e:
                print(f"[Kafka] Error processing orders.shipped event: {e}")

    finally:
        consumer.close()


def _handle_order_shipped(event: dict):
    """
    Handles an orders.shipped event.
    Updates the order status in PostgreSQL from 'pending' to 'shipped'.
    """
    order_number = event.get("orderNumber")
    
    if not order_number:
        print(f"[Kafka] Skipping event with missing orderNumber")
        return

    # Get a database session
    db_gen = get_db()
    db = next(db_gen)
    
    try:
        # Find the order by order_number
        order = db.query(Order).filter(Order.order_number == order_number).first()
        
        if not order:
            print(f"[Kafka] Order {order_number} not found in PostgreSQL")
            return
        
        # Update status
        order.status = "shipped"
        db.commit()
        
        print(f"[Kafka] Updated order {order_number} status to 'shipped'")
        
    except Exception as e:
        db.rollback()
        print(f"[Kafka] Failed to update order {order_number}: {e}")
    finally:
        db.close()
