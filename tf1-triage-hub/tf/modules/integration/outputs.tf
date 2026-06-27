output "alert_queue_id" {
  value = aws_sqs_queue.alert_queue.id
}

output "alert_queue_arn" {
  value = aws_sqs_queue.alert_queue.arn
}

output "alert_queue_url" {
  value = aws_sqs_queue.alert_queue.url
}

output "alert_queue_name" {
  value = aws_sqs_queue.alert_queue.name
}

output "alert_dlq_id" {
  value = aws_sqs_queue.alert_dlq.id
}

output "alert_dlq_arn" {
  value = aws_sqs_queue.alert_dlq.arn
}

output "alert_dlq_url" {
  value = aws_sqs_queue.alert_dlq.url
}

output "alert_dlq_name" {
  value = aws_sqs_queue.alert_dlq.name
}
