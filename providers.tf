############################################################
# Terraform Core + Providers
############################################################

terraform {
  # Require Terraform version 1.6.0 or higher (but not too old)
  required_version = ">= 1.6.0"

  required_providers {
    # AWS provider for all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.12.0, < 7.0" # keep pinned below major v7 for stability
    }

    # Random provider (used for suffixes, secrets, etc.)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Archive provider (used to zip app/ into artifact)
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure AWS provider region (comes from variables.tf)
provider "aws" {
  region = var.aws_region # default: us-east-1
}