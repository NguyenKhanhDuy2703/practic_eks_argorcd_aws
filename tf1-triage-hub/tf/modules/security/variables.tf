variable "project" {
  type        = string
  description = "Project name prefix"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC"
}

variable "vpc_endpoints_sg_id" {
  type        = string
  description = "ID of the VPC Endpoints Security Group"
}
