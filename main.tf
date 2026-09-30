# ─── Customer database (DynamoDB) + the password used to authenticate to it ─

resource "aws_dynamodb_table" "customer_database" {
  name         = "${local.name_prefix}-${var.customer_database_table_name}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "customerId"

  attribute {
    name = "customerId"
    type = "S"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.customer_database_table_name}"
  })
}

resource "aws_dynamodb_table_item" "sample_customers" {
  for_each = {
    "cust-001" = { name = "Ada Lovelace", tier = "GOLD", email = "ada@example.com" }
    "cust-002" = { name = "Grace Hopper", tier = "SILVER", email = "grace@example.com" }
  }

  table_name = aws_dynamodb_table.customer_database.name
  hash_key   = aws_dynamodb_table.customer_database.hash_key

  item = jsonencode({
    customerId = { S = each.key }
    name       = { S = each.value.name }
    tier       = { S = each.value.tier }
    email      = { S = each.value.email }
  })
}

resource "aws_secretsmanager_secret" "database_password" {
  name = "${local.name_prefix}-database-password"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "database_password" {
  secret_id     = aws_secretsmanager_secret.database_password.id
  secret_string = var.database_password
}

# ─── Data storage: OpenAPI schema describing the action group's operations ──

resource "aws_s3_bucket" "action_schema" {
  bucket = "${local.name_prefix}-${var.action_schema_bucket_name}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.action_schema_bucket_name}"
  })
}

resource "aws_s3_bucket_public_access_block" "action_schema" {
  bucket = aws_s3_bucket.action_schema.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "action_schema" {
  bucket       = aws_s3_bucket.action_schema.id
  key          = "action-group-schema.json"
  source       = "${path.module}/src/schema/action-group-schema.json"
  etag         = filemd5("${path.module}/src/schema/action-group-schema.json")
  content_type = "application/json"
}

# ─── Lambda: performs actions (place order, check inventory, check customer)

resource "aws_iam_role" "action_handler_exec" {
  name = "${local.name_prefix}-action-handler-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "action_handler_basic" {
  role       = aws_iam_role.action_handler_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "action_handler_dynamodb" {
  name = "${local.name_prefix}-action-handler-dynamodb"
  role = aws_iam_role.action_handler_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
      Resource = aws_dynamodb_table.customer_database.arn
    }]
  })
}

resource "aws_iam_role_policy" "action_handler_secrets" {
  name = "${local.name_prefix}-action-handler-secrets"
  role = aws_iam_role.action_handler_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.database_password.arn
    }]
  })
}

resource "null_resource" "action_handler_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/action_handler/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} action_handler"
  }
}

data "archive_file" "action_handler_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/action_handler/handler.py"
  output_path = "${path.module}/.build/action_handler.zip"

  depends_on = [null_resource.action_handler_package]
}

resource "aws_lambda_function" "action_handler" {
  function_name = "${local.name_prefix}-action-handler"
  role          = aws_iam_role.action_handler_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 15
  memory_size   = 256

  filename         = data.archive_file.action_handler_zip.output_path
  source_code_hash = data.archive_file.action_handler_zip.output_base64sha256

  environment {
    variables = {
      REGION                 = var.aws_region
      CUSTOMER_TABLE_NAME    = aws_dynamodb_table.customer_database.name
      DB_PASSWORD_SECRET_ARN = aws_secretsmanager_secret.database_password.arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-action-handler"
  })

  depends_on = [
    aws_iam_role_policy_attachment.action_handler_basic,
    aws_iam_role_policy.action_handler_dynamodb,
    aws_iam_role_policy.action_handler_secrets,
  ]
}

# ─── Bedrock agent: access AI models, perform actions via the action group ──

resource "aws_iam_role" "bedrock_agent" {
  name = "${local.name_prefix}-bedrock-agent"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "bedrock.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "bedrock_agent_model" {
  name = "${local.name_prefix}-bedrock-agent-model"
  role = aws_iam_role.bedrock_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.foundation_model_id}"
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_agent_schema" {
  name = "${local.name_prefix}-bedrock-agent-schema"
  role = aws_iam_role.bedrock_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.action_schema.arn}/*"
    }]
  })
}

resource "aws_bedrockagent_agent" "customer_service" {
  agent_name                  = "${local.name_prefix}-agent"
  agent_resource_role_arn     = aws_iam_role.bedrock_agent.arn
  foundation_model            = var.foundation_model_id
  instruction                 = "You are a customer service bot for an online store. Use the available actions to place orders, check inventory, and look up customer details and traits so you can deliver up-to-date, personalized answers."
  idle_session_ttl_in_seconds = 600
  prepare_agent               = true

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.bedrock_agent_model,
    aws_iam_role_policy.bedrock_agent_schema,
  ]
}

resource "aws_lambda_permission" "bedrock_invoke_action_handler" {
  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.action_handler.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.customer_service.agent_arn
}

resource "aws_bedrockagent_agent_action_group" "actions" {
  agent_id                   = aws_bedrockagent_agent.customer_service.agent_id
  agent_version              = "DRAFT"
  action_group_name          = "${local.name_prefix}-actions"
  action_group_state         = "ENABLED"
  skip_resource_in_use_check = true

  action_group_executor {
    lambda = aws_lambda_function.action_handler.arn
  }

  api_schema {
    s3 {
      s3_bucket_name = aws_s3_bucket.action_schema.id
      s3_object_key  = aws_s3_object.action_schema.key
    }
  }

  depends_on = [aws_lambda_permission.bedrock_invoke_action_handler]
}

resource "aws_bedrockagent_agent_alias" "prod" {
  agent_id         = aws_bedrockagent_agent.customer_service.agent_id
  agent_alias_name = "prod"

  depends_on = [aws_bedrockagent_agent_action_group.actions]
}

# ─── Lambda: chat gateway (Access AI models) — fronts the web application ──

resource "aws_iam_role" "chat_gateway_exec" {
  name = "${local.name_prefix}-chat-gateway-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "chat_gateway_basic" {
  role       = aws_iam_role.chat_gateway_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "chat_gateway_agent" {
  name = "${local.name_prefix}-chat-gateway-agent"
  role = aws_iam_role.chat_gateway_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeAgent"]
      Resource = aws_bedrockagent_agent_alias.prod.agent_alias_arn
    }]
  })
}

resource "null_resource" "chat_gateway_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/chat_gateway/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} chat_gateway"
  }
}

data "archive_file" "chat_gateway_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/chat_gateway/handler.py"
  output_path = "${path.module}/.build/chat_gateway.zip"

  depends_on = [null_resource.chat_gateway_package]
}

resource "aws_lambda_function" "chat_gateway" {
  function_name = "${local.name_prefix}-chat-gateway"
  role          = aws_iam_role.chat_gateway_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.chat_gateway_zip.output_path
  source_code_hash = data.archive_file.chat_gateway_zip.output_base64sha256

  environment {
    variables = {
      REGION         = var.aws_region
      AGENT_ID       = aws_bedrockagent_agent.customer_service.agent_id
      AGENT_ALIAS_ID = aws_bedrockagent_agent_alias.prod.agent_alias_id
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-chat-gateway"
  })

  depends_on = [
    aws_iam_role_policy_attachment.chat_gateway_basic,
    aws_iam_role_policy.chat_gateway_agent,
  ]
}

resource "aws_lambda_function_url" "chat_gateway" {
  function_name      = aws_lambda_function.chat_gateway.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["POST"]
    allow_headers = ["content-type"]
  }
}
