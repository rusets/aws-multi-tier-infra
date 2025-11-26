############################################
# Variables — core infrastructure configuration
############################################

############################################
# Global Project Name
############################################
variable "project_name" {
  type        = string
  description = "Project tag/name applied across resources"
  default     = "multi-tier-demo"

  validation {
    condition     = length(trimspace(var.project_name)) > 0
    error_message = "project_name must not be empty."
  }
}

############################################
# AWS Region
############################################
variable "region" {
  type        = string
  description = "AWS region for the deployment (single source of truth)"
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d$", var.region))
    error_message = "region must match pattern like us-east-1."
  }
}

############################################
# VPC CIDR Block
############################################
variable "vpc_cidr" {
  type        = string
  description = "Primary VPC CIDR block"
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR (e.g., 10.0.0.0/16)."
  }
}

############################################
# EC2 Instance Type
############################################
variable "instance_type" {
  type        = string
  description = "EC2 instance type for application nodes"
  default     = "t3.micro"

  validation {
    condition     = length(trimspace(var.instance_type)) > 0
    error_message = "instance_type must not be empty."
  }
}

############################################
# RDS Engine Type
############################################
variable "rds_engine" {
  type        = string
  description = "RDS engine type (postgres or mysql)"
  default     = "postgres"

  validation {
    condition     = contains(["postgres", "mysql"], lower(trimspace(var.rds_engine)))
    error_message = "rds_engine must be either 'postgres' or 'mysql'."
  }
}

############################################
# RDS Master Username
############################################
variable "rds_username" {
  type        = string
  description = "RDS master username (password managed by AWS)"
  default     = "postgres"

  validation {
    condition     = length(trimspace(var.rds_username)) > 0
    error_message = "rds_username must not be empty."
  }
}

############################################
# SSM Base Path
############################################
variable "param_path" {
  type        = string
  description = "Base SSM Parameter Store path for non-secret app config. If empty, falls back to \"/<namespace>\"."
  default     = ""

  validation {
    condition     = var.param_path == "" || can(regex("^/.+[^/]$", var.param_path))
    error_message = "param_path must be empty OR start with '/' and NOT end with '/'. Example: /multi-tier-demo"
  }
}

############################################
# Application Port
############################################
variable "app_port" {
  type        = number
  description = "Application port behind the ALB target group"
  default     = 3000

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535
    error_message = "app_port must be within 1..65535."
  }
}

############################################
# Health Check Settings
############################################
variable "health_check_path" {
  type        = string
  description = "Health check HTTP path used by the ALB Target Group"
  default     = "/health"

  validation {
    condition     = can(regex("^/.*$", var.health_check_path))
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_matcher" {
  type        = string
  description = "HTTP code matcher for ALB health checks (e.g., 200 or 200-399)"
  default     = "200-399"

  validation {
    condition     = can(regex("^[0-9]{3}(-[0-9]{3})?$", var.health_check_matcher))
    error_message = "health_check_matcher must be 'XYZ' or 'XYZ-ABC' (HTTP codes)."
  }
}

############################################
# Namespace
############################################
variable "namespace" {
  type        = string
  description = "Root prefix in SSM Parameter Store (e.g., multi-tier-demo -> /multi-tier-demo)"
  default     = "multi-tier-demo"

  validation {
    condition     = length(trimspace(var.namespace)) > 0
    error_message = "namespace must not be empty."
  }
}

############################################
# SSM Configuration
############################################
variable "ssm_write_db_password" {
  type    = bool
  default = false
}

variable "ssm_kms_key_id" {
  type        = string
  default     = null
  description = "KMS KeyId/ARN for encrypting SSM SecureString when writing DB password."

  validation {
    condition = var.ssm_write_db_password ? (
      var.ssm_kms_key_id != null && length(trimspace(var.ssm_kms_key_id)) > 0
    ) : true
    error_message = "When ssm_write_db_password=true, set non-empty ssm_kms_key_id (KeyId or full ARN)."
  }
}

############################################
# Application Artifact Key
############################################
variable "app_artifact_key" {
  type        = string
  description = "S3 key for the application artifact (e.g., artifacts/app-20250911.zip)"
  default     = "artifacts/app-initial.zip"

  validation {
    condition     = length(trimspace(var.app_artifact_key)) > 0
    error_message = "app_artifact_key must not be empty."
  }
}

############################################
# Domain and Certificate Inputs
############################################
variable "domain_name" {
  description = "Primary domain (e.g., multi-tier.space)"
  type        = string
  default     = "multi-tier.space"
}

variable "hosted_zone_id" {
  description = "Existing Route 53 Hosted Zone ID"
  type        = string
}

variable "acm_certificate_arn" {
  description = "Pre-issued ACM certificate ARN in us-east-1"
  type        = string
}

variable "enable_www_alias" {
  description = "Also map www.<domain> to apex"
  type        = bool
  default     = true
}

############################################
# Launch Template AMI
############################################
variable "ami_id" {
  description = "Pinned AMI ID for the Launch Template (ami-*)"
  type        = string
}
