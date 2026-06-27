output "alb_sg_id" {
  value       = aws_security_group.alb.id
  description = "The ID of the ALB Security Group"
}

output "eks_nodes_sg_id" {
  value       = aws_security_group.eks_nodes.id
  description = "The ID of the EKS Nodes Security Group"
}

output "lambda_sg_id" {
  value       = aws_security_group.lambda.id
  description = "The ID of the Lambda Security Group"
}
