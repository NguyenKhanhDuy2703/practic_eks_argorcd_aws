output "repository_urls" {
  value = {
    for repo in local.repositories : repo => aws_ecr_repository.repos[repo].repository_url
  }
}
