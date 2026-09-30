output "agent_id" {
  description = "ID of the Bedrock agent (Access AI models)."
  value       = aws_bedrockagent_agent.customer_service.agent_id
}

output "agent_alias_id" {
  description = "ID of the 'prod' alias created for the Bedrock agent."
  value       = aws_bedrockagent_agent_alias.prod.agent_alias_id
}

output "chat_gateway_function_url" {
  description = "Public URL of the chat gateway Lambda used by the web application."
  value       = aws_lambda_function_url.chat_gateway.function_url
}

output "customer_database_table" {
  description = "Name of the DynamoDB table holding customer records."
  value       = aws_dynamodb_table.customer_database.name
}

output "action_schema_bucket" {
  description = "Name of the S3 bucket holding the action group's OpenAPI schema."
  value       = aws_s3_bucket.action_schema.bucket
}
