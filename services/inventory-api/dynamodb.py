import os
import boto3
from botocore.exceptions import ClientError

# ── DynamoDB connection ────────────────────────────────────────────────────────
# In local development this points to DynamoDB Local running in Docker.
# In production this points to real AWS DynamoDB — remove endpoint_url
# and ensure the ECS/K8s pod has an IAM role with DynamoDB permissions.

DYNAMODB_ENDPOINT = os.getenv("DYNAMODB_ENDPOINT", "http://localhost:8000")
DYNAMODB_REGION   = os.getenv("DYNAMODB_REGION", "us-east-1")
AWS_ACCESS_KEY_ID     = os.getenv("AWS_ACCESS_KEY_ID", "local")
AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY", "local")

TABLE_NAME = "inventory"

dynamodb = boto3.resource(
    "dynamodb",
    endpoint_url          = DYNAMODB_ENDPOINT,
    region_name           = DYNAMODB_REGION,
    aws_access_key_id     = AWS_ACCESS_KEY_ID,
    aws_secret_access_key = AWS_SECRET_ACCESS_KEY,
)

table = dynamodb.Table(TABLE_NAME)


# ── DynamoDB helpers ───────────────────────────────────────────────────────────

def get_all_products() -> list:
    """
    Returns all products and their current stock levels.
    Called by the Inventory frontend to display the stock dashboard
    and by the Sales API /inventory proxy endpoint.
    """
    try:
        response = table.scan()
        items = response.get("Items", [])
        # Sort consistently by productId for predictable display order
        return sorted(items, key=lambda x: x.get("productId", ""))
    except ClientError as e:
        print(f"[DynamoDB] Error scanning inventory table: {e}")
        return []


def get_product(product_id: str) -> dict | None:
    """
    Returns a single product by productId.
    Called by the Sales API to check stock before accepting an order.
    Returns None if the product doesn't exist.
    """
    try:
        response = table.get_item(Key={"productId": product_id})
        return response.get("Item")
    except ClientError as e:
        print(f"[DynamoDB] Error getting product {product_id}: {e}")
        return None


def update_stock(product_id: str, new_stock: int) -> dict | None:
    """
    Updates the stock count for a product.
    Returns the updated item or None if the product doesn't exist.

    Uses a conditional update to ensure the product exists before
    updating — prevents accidentally creating phantom products.
    """
    try:
        response = table.update_item(
            Key                        = {"productId": product_id},
            UpdateExpression           = "SET stock = :new_stock",
            ConditionExpression        = "attribute_exists(productId)",
            ExpressionAttributeValues  = {":new_stock": new_stock},
            ReturnValues               = "ALL_NEW",
        )
        return response.get("Attributes")
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return None
        print(f"[DynamoDB] Error updating stock for {product_id}: {e}")
        raise


def add_product(product_id: str, name: str, stock: int) -> dict:
    """
    Adds a new product to the inventory table.
    Used in Scenario 3 when XL boxes are introduced.
    Uses put_item with a condition to prevent overwriting existing products.
    """
    item = {
        "productId": product_id,
        "name":      name,
        "stock":     stock,
        "reserved":  0,
    }
    try:
        table.put_item(
            Item                 = item,
            ConditionExpression  = "attribute_not_exists(productId)",
        )
        return item
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            raise ValueError(f"Product {product_id} already exists.")
        raise
