output "ingest_lambda_name" {
  value = aws_lambda_function.ingest.function_name
}

output "ingest_lambda_url" {
  value = aws_lambda_function_url.ingest.function_url
}

output "integration_lambda_name" {
  value = aws_lambda_function.integration.function_name
}
