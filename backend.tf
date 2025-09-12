# Terraform remote state: S3 backend with DynamoDB locking
terraform {
  backend "s3" {
    bucket         = "multi-tier-demo-tfstate-097635932419-e7f2c4" # S3 bucket for state
    key            = "aws-multi-tier-infra/terraform.tfstate"      # state object key
    region         = "us-east-1"                                   # backend region
    dynamodb_table = "multi-tier-demo-tf-locks"                    # state lock table (DynamoDB)
    encrypt        = true                                          # SSE for state object
  }
}
