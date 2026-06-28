locals {
  repositories = [
    "ingest-lambda",
    "correlator-worker",
    "ai-engine",
    "integration-lambda"
  ]
}

resource "aws_ecr_repository" "repos" {
  for_each             = toset(local.repositories)
  name                 = "${var.project}/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project}/${each.key}"
  }
}

resource "aws_ecr_lifecycle_policy" "repos_policy" {
  for_each   = toset(local.repositories)
  repository = aws_ecr_repository.repos[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 2,
        description  = "Keep last 10 images",
        selection = {
          tagStatus   = "any",
          countType   = "imageCountMoreThan",
          countNumber = 10
        },
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 1,
        description  = "Expire untagged images older than 7 days",
        selection = {
          tagStatus   = "untagged",
          countType   = "sinceImagePushed",
          countUnit   = "days",
          countNumber = 7
        },
        action = {
          type = "expire"
        }
      }
    ]
  })
}
