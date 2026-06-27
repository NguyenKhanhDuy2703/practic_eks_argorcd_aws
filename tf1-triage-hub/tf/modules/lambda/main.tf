locals {
  name_prefix = "${var.project}-${var.environment}"
}

# 1. IAM Role for Ingest Lambda
resource "aws_iam_role" "ingest" {
  name = "${local.name_prefix}-ingest-lambda-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ingest_vpc_access" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.ingest.name
}

resource "aws_iam_role_policy" "ingest_sqs" {
  name = "sqs-access"
  role = aws_iam_role.ingest.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sqs:SendMessage", Effect = "Allow", Resource = var.sqs_queue_arn }]
  })
}

# 2. Ingest Lambda Function
data "archive_file" "dummy_ingest" {
  type        = "zip"
  output_path = "${path.module}/dummy_ingest.zip"
  source {
    content  = "def handler(event, context):\n  return {'statusCode': 200, 'body': 'ok'}"
    filename = "main.py"
  }
}

resource "aws_lambda_function" "ingest" {
  function_name    = "${local.name_prefix}-ingest-lambda"
  role             = aws_iam_role.ingest.arn
  handler          = "main.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.dummy_ingest.output_path
  source_code_hash = data.archive_file.dummy_ingest.output_base64sha256
  timeout          = 30
  memory_size      = 256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_sg_id]
  }

  environment {
    variables = {
      SQS_QUEUE_URL = var.sqs_queue_url
      ENVIRONMENT   = var.environment
    }
  }
}

# Function URL for Ingest Lambda
resource "aws_lambda_function_url" "ingest" {
  function_name      = aws_lambda_function.ingest.function_name
  authorization_type = "NONE" # Configurable, usually NONE for webhook receiving and handled inside code
}

# 3. IAM Role for Integration Lambda
resource "aws_iam_role" "integration" {
  name = "${local.name_prefix}-integration-lambda-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "integration_vpc_access" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.integration.name
}

resource "aws_iam_role_policy" "integration_access" {
  name = "integration-access"
  role = aws_iam_role.integration.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem"], Effect = "Allow", Resource = var.dynamodb_table_arn },
      { Action = ["s3:PutObject", "s3:GetObject"], Effect = "Allow", Resource = "${var.s3_audit_bucket_arn}/*" },
      { Action = "secretsmanager:GetSecretValue", Effect = "Allow", Resource = "*" } # Should be restricted in prod
    ]
  })
}

# 4. Integration Lambda Function
data "archive_file" "dummy_integration" {
  type        = "zip"
  output_path = "${path.module}/dummy_integration.zip"
  source {
    content  = "def handler(event, context):\n  return {'statusCode': 200, 'body': 'ok'}"
    filename = "main.py"
  }
}

resource "aws_lambda_function" "integration" {
  function_name    = "${local.name_prefix}-integration-lambda"
  role             = aws_iam_role.integration.arn
  handler          = "main.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.dummy_integration.output_path
  source_code_hash = data.archive_file.dummy_integration.output_base64sha256
  timeout          = 30
  memory_size      = 256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_sg_id]
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }
}
