"""action_handler (Perform actions): implements the customer service bot's
action group — place orders, check inventory, and look up customer details
and traits — backed by the customer database (DynamoDB) and a database
password stored in Secrets Manager.
"""
import json
import os
import uuid

import boto3

REGION = os.environ.get("REGION", "us-east-1")
CUSTOMER_TABLE_NAME = os.environ["CUSTOMER_TABLE_NAME"]
DB_PASSWORD_SECRET_ARN = os.environ["DB_PASSWORD_SECRET_ARN"]

_boto_kwargs = {
    "region_name": REGION,
    "endpoint_url": "http://localhost:4566",
    "aws_access_key_id": "test",
    "aws_secret_access_key": "test",
}

dynamodb = boto3.resource("dynamodb", **_boto_kwargs)
secrets_manager = boto3.client("secretsmanager", **_boto_kwargs)
customer_table = dynamodb.Table(CUSTOMER_TABLE_NAME)

# Static in-memory catalog used to simulate inventory levels for the demo.
_INVENTORY = {
    "prod-100": 42,
    "prod-200": 7,
    "prod-300": 0,
}


def lambda_handler(event, context):
    api_path = event.get("apiPath", "")
    http_method = event.get("httpMethod", "GET")
    parameters = {p["name"]: p["value"] for p in event.get("parameters", [])}
    request_body = _extract_request_body(event)

    # Authenticate to the customer database with the stored password before serving data.
    _authenticate_to_database()

    if api_path == "/place-order" and http_method == "POST":
        payload = _place_order(request_body)
    elif api_path == "/check-inventory" and http_method == "GET":
        payload = _check_inventory(parameters.get("productId", ""))
    elif api_path == "/check-customer-details" and http_method == "GET":
        payload = _check_customer_details(parameters.get("customerId", ""))
    else:
        payload = {"error": f"Unsupported action: {http_method} {api_path}"}

    return _agent_response(event, payload)


def _authenticate_to_database():
    # In a real integration this password would open a connection to a
    # traditional database; here it just proves the secret is reachable.
    secrets_manager.get_secret_value(SecretId=DB_PASSWORD_SECRET_ARN)


def _place_order(request_body):
    customer_id = request_body.get("customerId", "")
    product_id = request_body.get("productId", "")
    quantity = int(request_body.get("quantity", 0))

    available = _INVENTORY.get(product_id, 0)
    if quantity > available:
        return {"orderId": None, "status": f"REJECTED: only {available} units of {product_id} available"}

    _INVENTORY[product_id] = available - quantity
    order_id = f"order-{uuid.uuid4().hex[:8]}"
    return {"orderId": order_id, "status": "CONFIRMED", "customerId": customer_id}


def _check_inventory(product_id):
    return {"productId": product_id, "quantityAvailable": _INVENTORY.get(product_id, 0)}


def _check_customer_details(customer_id):
    item = customer_table.get_item(Key={"customerId": customer_id}).get("Item")
    if not item:
        return {"error": f"Customer {customer_id} not found."}
    return item


def _extract_request_body(event):
    content = event.get("requestBody", {}).get("content", {})
    json_body = content.get("application/json", {})
    properties = json_body.get("properties", [])
    if isinstance(properties, list):
        return {prop["name"]: prop["value"] for prop in properties}
    return properties or {}


def _agent_response(event, payload):
    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": event.get("actionGroup", ""),
            "apiPath": event.get("apiPath", ""),
            "httpMethod": event.get("httpMethod", ""),
            "httpStatusCode": 200,
            "responseBody": {
                "application/json": {"body": json.dumps(payload)}
            },
        },
    }
