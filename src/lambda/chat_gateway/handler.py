"""chat_gateway (Access AI models): fronts the web application, forwarding
each customer request to the Bedrock agent and returning its final answer.
"""
import json
import os
import uuid

import boto3

REGION = os.environ.get("REGION", "us-east-1")
AGENT_ID = os.environ["AGENT_ID"]
AGENT_ALIAS_ID = os.environ["AGENT_ALIAS_ID"]

bedrock_agent_runtime = boto3.client(
    "bedrock-agent-runtime",
    region_name=REGION,
    endpoint_url="http://localhost:4566",
    aws_access_key_id="test",
    aws_secret_access_key="test",
)


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Request body must be valid JSON."})

    prompt = body.get("prompt")
    if not prompt:
        return _response(400, {"error": "'prompt' is required."})

    session_id = body.get("sessionId") or uuid.uuid4().hex

    response = bedrock_agent_runtime.invoke_agent(
        agentId=AGENT_ID,
        agentAliasId=AGENT_ALIAS_ID,
        sessionId=session_id,
        inputText=prompt,
    )

    answer = "".join(
        chunk["chunk"]["bytes"].decode("utf-8")
        for chunk in response.get("completion", [])
        if "chunk" in chunk
    )

    return _response(200, {"answer": answer, "sessionId": session_id})


def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(payload),
    }
