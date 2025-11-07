############################################
# Terraform Core — version & providers
# Principle: stable, reproducible builds
############################################
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.12.0, < 7.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

############################################
# AWS Provider — single source of region
# Principle: no inline comments; tags unified
############################################
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = var.project_name
      Managed = "terraform"
    }
  }
}
