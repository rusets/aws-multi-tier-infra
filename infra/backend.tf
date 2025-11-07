############################################
# Terraform Backend — S3 state + DynamoDB lock
# Principle: remote, encrypted, team-safe state
############################################
terraform {
  backend "s3" {
    bucket         = "multi-tier-demo-tfstate-097635932419-e7f2c4"
    key            = "aws-multi-tier-infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "multi-tier-demo-tf-locks"
    encrypt        = true
  }
}
