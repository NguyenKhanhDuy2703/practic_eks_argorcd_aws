output "vpc_id" {
  value = module.networking.vpc_id
}

output "eks_cluster_name" {
  value = module.compute.cluster_name
}

output "ingest_lambda_url" {
  value = module.lambda.ingest_lambda_url
}
