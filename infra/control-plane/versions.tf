############################################
# Versions & Providers
############################################
terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.5"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

############################################
# AWS provider — region & default tags
############################################
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = var.project_name
      Stack   = "control-plane"
      Managed = "terraform"
    }
  }
}
