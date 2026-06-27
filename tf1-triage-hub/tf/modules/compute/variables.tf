variable "project" {
  type        = string
  description = "Project prefix"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for EKS"
}

variable "eks_nodes_sg_id" {
  type        = string
  description = "Security group ID for EKS nodes"
}
