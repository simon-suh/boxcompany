import os
import boto3
from botocore.exceptions import ClientError

# ── DynamoDB connection ────────────────────────────────────────────────────────
DYNAMODB_ENDPOINT     = os.getenv("DYNAMODB_ENDPOINT", "http://localhost:8000")
DYNAMODB_REGION       = os.getenv("DYNAMODB_REGION", "us-east-1")
AWS_ACCESS_KEY_ID     = os.getenv("AWS_ACCESS_KEY_ID", "local")
AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY", "local")

SHIPMENTS_TABLE = "shipments"
ERRORS_TABLE    = "shipment_errors"

dynamodb = boto3.resource(
    "dynamodb",
    endpoint_url          = DYNAMODB_ENDPOINT,
    region_name           = DYNAMODB_REGION,
    aws_access_key_id     = AWS_ACCESS_KEY_ID,
    aws_secret_access_key = AWS_SECRET_ACCESS_KEY,
)

shipments_table = dynamodb.Table(SHIPMENTS_TABLE)


# ── DynamoDB helpers ───────────────────────────────────────────────────────────

def save_order(order: dict) -> dict:
    """
    Saves an incoming order to the shipments table.
    Called by the Kafka consumer when an orders.created
    event is consumed — this is how the shipment team
    sees new orders on their dashboard.
    """
    try:
        shipments_table.put_item(
            Item                = order,
            ConditionExpression = "attribute_not_exists(orderId)",
        )
        return order
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            print(f"[DynamoDB] Order {order.get('orderId')} already exists — skipping")
            return order
        raise


def get_all_orders() -> list:
    """
    Returns all orders sorted by createdAt descending.
    Used by the Shipment frontend dashboard to display
    incoming orders.
    """
    try:
        response = shipments_table.scan()
        items    = response.get("Items", [])
        return sorted(items, key=lambda x: x.get("createdAt", ""), reverse=True)
    except ClientError as e:
        print(f"[DynamoDB] Error scanning shipments table: {e}")
        return []


def get_order(order_id: str) -> dict | None:
    """
    Returns a single order by orderId.
    """
    try:
        response = shipments_table.get_item(Key={"orderId": order_id})
        return response.get("Item")
    except ClientError as e:
        print(f"[DynamoDB] Error getting order {order_id}: {e}")
        return None


def update_tracking(order_id: str, carrier: str, tracking_number: str, shipped_at: str) -> dict | None:
    """
    Adds tracking info to an existing order and marks it as shipped.
    Called when the shipment team uploads tracking info via the frontend.
    """
    try:
        response = shipments_table.update_item(
            Key                       = {"orderId": order_id},
            UpdateExpression          = "SET #s = :status, carrier = :carrier, "
                                        "trackingNumber = :tracking, shippedAt = :shipped",
            ConditionExpression       = "attribute_exists(orderId)",
            ExpressionAttributeNames  = {"#s": "status"},
            ExpressionAttributeValues = {
                ":status":   "shipped",
                ":carrier":  carrier,
                ":tracking": tracking_number,
                ":shipped":  shipped_at,
            },
            ReturnValues              = "ALL_NEW",
        )
        return response.get("Attributes")
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return None
        raise


def save_error_report(report: dict) -> dict:
    """
    Saves an incoming error report to DynamoDB.
    Called by the Kafka consumer when an errors.reported
    event is consumed and the shipment team is in notifyTeams.
    """
    try:
        errors_table = dynamodb.Table("shipment_errors")
        errors_table.put_item(Item=report)
        return report
    except ClientError as e:
        print(f"[DynamoDB] Error saving error report: {e}")
        raise
