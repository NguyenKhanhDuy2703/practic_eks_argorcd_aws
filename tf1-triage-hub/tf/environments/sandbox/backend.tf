terraform {
  backend "s3" {
    bucket         = "tf1-cdo05-tfstate-khanhduy2703"
    key            = "sandbox/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf1-cdo05-tflock-khanhduy2703"
    encrypt        = true
  }
}
