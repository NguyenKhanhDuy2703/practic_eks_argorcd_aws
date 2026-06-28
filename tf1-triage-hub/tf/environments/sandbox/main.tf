terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}


provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = module.compute.cluster_endpoint
  cluster_ca_certificate = base64decode(module.compute.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.compute.cluster_name]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.compute.cluster_endpoint
    cluster_ca_certificate = base64decode(module.compute.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.compute.cluster_name]
    }
  }
}

module "networking" {
  source      = "../../modules/networking"
  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  azs         = var.azs
}

module "security" {
  source              = "../../modules/security"
  project             = var.project
  environment         = var.environment
  vpc_id              = module.networking.vpc_id
  vpc_endpoints_sg_id = module.networking.vpc_endpoints_sg_id
}

module "data" {
  source      = "../../modules/data"
  project     = var.project
  environment = var.environment
}

module "integration" {
  source      = "../../modules/integration"
  project     = var.project
  environment = var.environment
}

module "ecr" {
  source  = "../../modules/ecr"
  project = var.project
}

module "compute" {
  source             = "../../modules/compute"
  project            = var.project
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  eks_nodes_sg_id    = module.security.eks_nodes_sg_id
}

module "lambda" {
  source              = "../../modules/lambda"
  project             = var.project
  environment         = var.environment
  sqs_queue_url       = module.integration.alert_queue_url
  sqs_queue_arn       = module.integration.alert_queue_arn
  dynamodb_table_arn  = module.data.dynamodb_table_arn
  s3_audit_bucket_arn = module.data.s3_audit_bucket_arn
  lambda_sg_id        = module.security.lambda_sg_id
  private_subnet_ids  = module.networking.private_subnet_ids
}

module "observability" {
  source                  = "../../modules/observability"
  project                 = var.project
  environment             = var.environment
  ingest_lambda_name      = module.lambda.ingest_lambda_name
  integration_lambda_name = module.lambda.integration_lambda_name
  alert_queue_name        = module.integration.alert_queue_name
  alert_dlq_name          = module.integration.alert_dlq_name
  dynamodb_table_name     = module.data.dynamodb_table_name
}

module "argocd" {
  source      = "../../modules/argocd"
  cluster_id  = module.compute.cluster_id
  environment = var.environment
}
