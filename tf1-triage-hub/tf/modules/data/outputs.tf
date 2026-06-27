output "dynamodb_table_name" {
  value = aws_dynamodb_table.incident_state.name
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.incident_state.arn
}

output "s3_audit_bucket_id" {
  value = aws_s3_bucket.audit.id
}

output "s3_audit_bucket_arn" {
  value = aws_s3_bucket.audit.arn
}
