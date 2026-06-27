variable "project" {
  type        = string
  description = "Project prefix"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "sqs_queue_url" {
  type        = string
  description = "URL of the SQS queue"
}

variable "sqs_queue_arn" {
  type        = string
  description = "ARN of the SQS queue"
}

variable "dynamodb_table_arn" {
  type        = string
  description = "ARN of the DynamoDB table"
}

variable "s3_audit_bucket_arn" {
  type        = string
  description = "ARN of the S3 audit bucket"
}

variable "lambda_sg_id" {
  type        = string
  description = "Security group ID for Lambda"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs"
}
