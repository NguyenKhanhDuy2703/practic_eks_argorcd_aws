locals {
  name_prefix = "${var.project}-${var.environment}"
}

# 1. SNS Topic
resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

# 2. CloudWatch Log Groups for Lambda (Retention 14 days)
resource "aws_cloudwatch_log_group" "ingest_lambda" {
  name              = "/aws/lambda/${var.ingest_lambda_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "integration_lambda" {
  name              = "/aws/lambda/${var.integration_lambda_name}"
  retention_in_days = 14
}

# 3. Alarms for Lambda
# Ingest Errors
resource "aws_cloudwatch_metric_alarm" "ingest_errors" {
  alarm_name          = "${local.name_prefix}-ingest-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300" # 5 mins
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Ingest Lambda errors > 5 in 5 mins"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    FunctionName = var.ingest_lambda_name
  }
}

# Integration Duration p99 > 10s
resource "aws_cloudwatch_metric_alarm" "integration_duration" {
  alarm_name          = "${local.name_prefix}-integration-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "60"
  extended_statistic  = "p99"
  threshold           = "10000" # 10 seconds in ms
  alarm_description   = "Integration Lambda p99 duration > 10s"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    FunctionName = var.integration_lambda_name
  }
}

# 4. Alarms for SQS
resource "aws_cloudwatch_metric_alarm" "sqs_depth" {
  alarm_name          = "${local.name_prefix}-sqs-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "100"
  alarm_description   = "SQS Queue depth > 100"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    QueueName = var.alert_queue_name
  }
}

resource "aws_cloudwatch_metric_alarm" "dlq_count" {
  alarm_name          = "${local.name_prefix}-dlq-count"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "DLQ has messages (CRITICAL)"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    QueueName = var.alert_dlq_name
  }
}

# 5. Alarm for DynamoDB Throttles
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "${local.name_prefix}-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "DynamoDB throttled requests > 0"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    TableName = var.dynamodb_table_name
  }
}
