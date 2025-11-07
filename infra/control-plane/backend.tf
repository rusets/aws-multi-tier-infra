############################################
# Backend — separate state for control-plane
############################################
terraform {
  backend "s3" {
    bucket         = "multi-tier-demo-tfstate-097635932419-e7f2c4"
    key            = "aws-multi-tier-control/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "multi-tier-demo-tf-locks"
  }
}
