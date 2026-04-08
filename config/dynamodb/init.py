import socket
import boto3
import time
from botocore.config import Config

# Force IPv4 — DynamoDB Local listens on IPv6 by default in Docker
# which causes boto3 to hang on connection
original_getaddrinfo = socket.getaddrinfo
def getaddrinfo_ipv4(*args, **kwargs):
    responses = original_getaddrinfo(*args, **kwargs)
    return [r for r in responses if r[0] == socket.AF_INET]
socket.getaddrinfo = getaddrinfo_ipv4

print('Connecting to DynamoDB...')

config = Config(
    connect_timeout=5,
    read_timeout=5,
    retries={'max_attempts': 1}
)

dynamodb = boto3.resource(
    'dynamodb',
    endpoint_url='http://dynamodb-local:8000',
    region_name='us-east-1',
    aws_access_key_id='local',
    aws_secret_access_key='local',
    config=config
)

for attempt in range(20):
    try:
        list(dynamodb.tables.all())
        print('DynamoDB is ready.')
        break
    except Exception as e:
        print(f'Attempt {attempt+1}/20: {e}')
        time.sleep(3)

try:
    dynamodb.create_table(
        TableName='shipments',
        KeySchema=[{'AttributeName': 'orderId', 'KeyType': 'HASH'}],
        AttributeDefinitions=[{'AttributeName': 'orderId', 'AttributeType': 'S'}],
        BillingMode='PAY_PER_REQUEST'
    )
    print('Shipments table created.')
except Exception as e:
    print(f'Shipments: {e}')

try:
    dynamodb.create_table(
        TableName='inventory',
        KeySchema=[{'AttributeName': 'productId', 'KeyType': 'HASH'}],
        AttributeDefinitions=[{'AttributeName': 'productId', 'AttributeType': 'S'}],
        BillingMode='PAY_PER_REQUEST'
    )
    print('Inventory table created.')
except Exception as e:
    print(f'Inventory: {e}')

time.sleep(5)

table = dynamodb.Table('inventory')
items = [
    {'productId': 'small-box',  'name': 'Small box',  'stock': 500, 'reserved': 0},
    {'productId': 'medium-box', 'name': 'Medium box', 'stock': 0,   'reserved': 0},
    {'productId': 'large-box',  'name': 'Large box',  'stock': 300, 'reserved': 0},
    {'productId': 'xl-box',     'name': 'XL box',     'stock': 150, 'reserved': 0},
]
for item in items:
    table.put_item(Item=item)
    print(f'Seeded: {item["name"]} — {item["stock"]} units')

print('DynamoDB init complete.')