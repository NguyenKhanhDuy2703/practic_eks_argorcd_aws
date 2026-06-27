locals {
  name_prefix = "${var.project}-${var.environment}"
}

# 1. Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-sg-alb"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress rules are handled by aws_security_group_rule below to avoid cycle

  tags = {
    Name = "${local.name_prefix}-sg-alb"
  }
}

# 2. Security Group for EKS Nodes
resource "aws_security_group" "eks_nodes" {
  name        = "${local.name_prefix}-sg-eks-nodes"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  # Inbound rules are handled by aws_security_group_rule below

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-eks-nodes"
  }
}

# Rule: ALB out to EKS Nodes
resource "aws_security_group_rule" "alb_to_eks" {
  type                     = "egress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.alb.id
}

# Rule: EKS Nodes in from ALB
resource "aws_security_group_rule" "eks_from_alb" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.eks_nodes.id
}

# 3. Security Group for Lambda Functions
resource "aws_security_group" "lambda" {
  name        = "${local.name_prefix}-sg-lambda"
  description = "Security group for Lambda functions"
  vpc_id      = var.vpc_id

  egress {
    description     = "Allow outbound to VPC Endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.vpc_endpoints_sg_id]
  }

  tags = {
    Name = "${local.name_prefix}-sg-lambda"
  }
}

# Add rules for VPC Endpoints SG to accept traffic from EKS Nodes and Lambda
resource "aws_security_group_rule" "vpce_from_eks" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = var.vpc_endpoints_sg_id
}

resource "aws_security_group_rule" "vpce_from_lambda" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lambda.id
  security_group_id        = var.vpc_endpoints_sg_id
}
