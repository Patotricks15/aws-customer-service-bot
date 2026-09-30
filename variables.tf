variable "project_name" {
  description = "Project name used as prefix for all resources."
  type        = string
  default     = "floci-customer-service-bot"
}

variable "aws_region" {
  description = "AWS region (simulated by floci)."
  type        = string
  default     = "us-east-1"
}

variable "foundation_model_id" {
  description = "Bedrock foundation model id used by the customer service agent."
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "customer_database_table_name" {
  description = "Name of the DynamoDB table holding customer records (the 'customer database')."
  type        = string
  default     = "customer-database"
}

variable "action_schema_bucket_name" {
  description = "Name of the S3 bucket storing the action group's OpenAPI schema (data storage)."
  type        = string
  default     = "action-group-schema"
}

variable "database_password" {
  description = "Password used by the action handler Lambda to authenticate against the customer database, stored in Secrets Manager."
  type        = string
  default     = "S3cure-Demo-Password!"
  sensitive   = true
}
