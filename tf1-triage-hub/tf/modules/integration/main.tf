locals {
  name_prefix = "${var.project}-${var.environment}"
}

# Dead Letter Queue
resource "aws_sqs_queue" "alert_dlq" {
  name                        = "${local.name_prefix}-alert-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600 # 14 days
  sqs_managed_sse_enabled     = true

  tags = {
    Name = "${local.name_prefix}-alert-dlq.fifo"
  }
}

# Main Queue
resource "aws_sqs_queue" "alert_queue" {
  name                        = "${local.name_prefix}-alert-queue.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 300
  message_retention_seconds   = 345600 # 4 days
  sqs_managed_sse_enabled     = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.alert_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${local.name_prefix}-alert-queue.fifo"
  }
}
