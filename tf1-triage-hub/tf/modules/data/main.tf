locals {
  name_prefix = "${var.project}-${var.environment}"
}

data "aws_caller_identity" "current" {}

# 1. DynamoDB Table for incident_state
resource "aws_dynamodb_table" "incident_state" {
  name         = "${local.name_prefix}-incident-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "incident_id"

  attribute {
    name = "incident_id"
    type = "S"
  }

  attribute {
    name = "correlation_key"
    type = "S"
  }

  attribute {
    name = "alert_fingerprint"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  global_secondary_index {
    name            = "CorrelationKeyIndex"
    hash_key        = "correlation_key"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "AlertFingerprintIndex"
    hash_key        = "alert_fingerprint"
    projection_type = "ALL"
  }

  tags = {
    Name = "${local.name_prefix}-incident-state"
  }
}

# 2. S3 Audit Bucket
resource "aws_s3_bucket" "audit" {
  bucket = "tf1-audit-${data.aws_caller_identity.current.account_id}-${var.environment}"

  tags = {
    Name = "tf1-audit-${var.environment}"
  }
}

resource "aws_s3_bucket_versioning" "audit_versioning" {
  bucket = aws_s3_bucket.audit.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "audit_access" {
  bucket                  = aws_s3_bucket.audit.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "audit_lifecycle" {
  bucket = aws_s3_bucket.audit.id

  rule {
    id     = "archive_to_glacier"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# Require TLS (HTTPS)
resource "aws_s3_bucket_policy" "require_tls" {
  bucket = aws_s3_bucket.audit.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSSLRequestsOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.audit.arn,
          "${aws_s3_bucket.audit.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
