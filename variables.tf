############################################################
# Input Variables (comments are in English, as requested)334433
############################################################

# Global project tag/name applied across resources (used for naming and tagging)
variable "project_name" {
  type        = string
  description = "Project tag/name applied across resources"
  default     = "multi-tier-demo"

  validation {
    condition     = length(trim(var.project_name, " ")) > 0
    error_message = "project_name must not be empty."
  }
}

# AWS region used by Terraform and AWS provider
variable "region" {
  type        = string
  description = "AWS region for the deployment"
  default     = "us-east-1"

  validation {
    # basic region format like us-east-1, eu-west-3, etc.
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d$", var.region))
    error_message = "region must match pattern like us-east-1."
  }
}

# CIDR block for the main VPC (controls IP space for subnets)
variable "vpc_cidr" {
  type        = string
  description = "Primary VPC CIDR block"
  default     = "10.0.0.0/16"

  validation {
    # cidrnetmask() throws on invalid CIDR; can() converts it to boolean
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR (e.g., 10.0.0.0/16)."
  }
}

# EC2 instance type for application nodes (affects cost and performance)
variable "instance_type" {
  type        = string
  description = "EC2 instance type for application nodes"
  default     = "t3.micro"

  validation {
    condition     = length(trim(var.instance_type, " ")) > 0
    error_message = "instance_type must not be empty."
  }
}

# Which database engine to use for RDS (supported: postgres or mysql)
variable "rds_engine" {
  type        = string
  description = "RDS engine: postgres or mysql"
  default     = "postgres"

  validation {
    condition     = contains(["postgres", "mysql"], lower(trim(var.rds_engine, " ")))
    error_message = "rds_engine must be either 'postgres' or 'mysql'."
  }
}

# Master username for RDS (password is automatically managed by AWS RDS)
variable "rds_username" {
  type        = string
  description = "RDS master username (password is managed by AWS)"
  default     = "postgres"

  validation {
    condition     = length(trim(var.rds_username, " ")) > 0
    error_message = "rds_username must not be empty."
  }
}

# CIDR block allowed to access EC2 via SSH
# - Empty string disables SSH access entirely (more secure for production)
variable "admin_cidr" {
  type        = string
  description = "CIDR allowed to SSH into app instances; empty to disable SSH"
  default     = ""

  validation {
    condition     = var.admin_cidr == "" || can(cidrnetmask(var.admin_cidr))
    error_message = "admin_cidr must be empty or a valid CIDR (e.g., 1.2.3.4/32)."
  }
}

# Base path in SSM Parameter Store for storing app-related configuration
# Example effective keys: /multi-tier-demo/db/host, etc.
variable "param_path" {
  type        = string
  description = "Base SSM Parameter Store path for non-secret app config (e.g., /multi-tier-demo)"
  default     = "/multi-tier-demo"

  validation {
    # Must start with "/" and must NOT end with "/"
    condition     = can(regex("^/.+[^/]$", var.param_path))
    error_message = "param_path must start with '/' and must not end with '/'. Example: /multi-tier-demo"
  }
}

# Internal application port (container/instance level), behind ALB target group
variable "app_port" {
  type        = number
  description = "Application port behind the ALB target group"
  default     = 3000

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535
    error_message = "app_port must be within 1..65535."
  }
}

# AWS region duplicative variable for clarity (often same as `region`)
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d$", var.aws_region))
    error_message = "aws_region must match pattern like us-east-1."
  }
}

# Root namespace for SSM Parameter Store parameters
# Used to build canonical SSM paths, e.g. /<namespace>/db/host
variable "namespace" {
  type        = string
  description = "Root prefix in SSM Parameter Store, e.g. multi-tier-demo -> /multi-tier-demo/..."
  default     = "multi-tier-demo"

  validation {
    condition     = length(trim(var.namespace, " ")) > 0
    error_message = "namespace must not be empty."
  }
}

# Control whether DB password should also be written into SSM Parameter Store
# (Recommended: false if using Secrets Manager; prevents duplicate secret management)
variable "ssm_write_db_password" {
  type        = bool
  description = "If true, write DB password to SSM as SecureString (not recommended when using Secrets Manager)."
  default     = false
}

# KMS key for encrypting SecureString values in SSM Parameter Store
# Only used when `ssm_write_db_password` is enabled
variable "ssm_kms_key_id" {
  type        = string
  description = "KMS key id/arn for SSM SecureString parameters (only used if ssm_write_db_password==true)."
  default     = null
}

# Key of the application artifact in S3 (passed from CI or a default)
variable "app_artifact_key" {
  type        = string
  description = "S3 key for the application artifact (e.g., artifacts/app-20250911.zip)"
  default     = "artifacts/app-initial.zip"

  validation {
    condition     = length(trim(var.app_artifact_key, " ")) > 0
    error_message = "app_artifact_key must not be empty."
  }
}

# Which GitHub repo can assume OIDC roles (format: owner/repo)
variable "github_repo" {
  type        = string
  description = "GitHub repository allowed to assume OIDC roles (format: owner/repo)"
  default     = "rusets/aws-multi-tier-infra"

  validation {
    # simple owner/repo check
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must be in the form owner/repo (e.g., rusets/aws-multi-tier-infra)."
  }
}
