############################################################
# Input Variables
############################################################

# Global project tag/name applied across resources (used for naming and tagging)
variable "project_name" {
  type        = string
  description = "Project tag/name applied across resources"
  default     = "multi-tier-demo"
}

# AWS region used by Terraform and AWS provider
variable "region" {
  type        = string
  description = "AWS region for the deployment"
  default     = "us-east-1"
}

# CIDR block for the main VPC (controls IP space for subnets)
variable "vpc_cidr" {
  type        = string
  description = "Primary VPC CIDR block"
  default     = "10.0.0.0/16"
}

# EC2 instance type for application nodes (affects cost and performance)
variable "instance_type" {
  type        = string
  description = "EC2 instance type for application nodes"
  default     = "t3.micro"
}

# Which database engine to use for RDS (supported: postgres or mysql)
variable "rds_engine" {
  type        = string
  description = "RDS engine: postgres or mysql"
  default     = "postgres"
}

# Master username for RDS (password is automatically managed by AWS RDS)
variable "rds_username" {
  type        = string
  description = "RDS master username (password is managed by AWS)"
  default     = "postgres"
}

# CIDR block allowed to access EC2 via SSH
# - Empty string disables SSH access entirely (more secure for production)
variable "admin_cidr" {
  type        = string
  description = "CIDR allowed to SSH into app instances; empty to disable SSH"
  default     = ""
}

# Base path in SSM Parameter Store for storing app-related configuration
# Example: "/multi-tier-demo/db/host"
variable "param_path" {
  type        = string
  description = "Base SSM Parameter Store path for non-secret app config (e.g., /multi-tier-demo)"
  default     = "/multi-tier-demo"
}

# Internal application port (container/instance level),
# behind ALB target group
variable "app_port" {
  type        = number
  description = "Application port behind the ALB target group"
  default     = 3000
}

# AWS region for all resources (duplicated for clarity, often matches `region`)
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

# Root namespace for SSM Parameter Store parameters
# Will be prepended as: /<namespace>/...
variable "namespace" {
  type        = string
  default     = "multi-tier-demo"
  description = "Root prefix in SSM Parameter Store, e.g. multi-tier-demo -> /multi-tier-demo/..."
}

# Control whether DB password should also be written into SSM Parameter Store
# (Recommended: false if using Secrets Manager; prevents duplicate secret management)
variable "ssm_write_db_password" {
  type        = bool
  default     = false
  description = "If true, write DB password to SSM as SecureString (not recommended when using Secrets Manager)."
}

# KMS key for encrypting SecureString values in SSM Parameter Store
# Only used when `ssm_write_db_password` is enabled
variable "ssm_kms_key_id" {
  type        = string
  default     = null
  description = "KMS key id/arn for SSM SecureString parameters (only used if ssm_write_db_password==true)."
}

# Key of the application artifact in S3 (passed from CI)
variable "app_artifact_key" {
  type        = string
  description = "S3 key for the application artifact (e.g., artifacts/app-20250911.zip)"
  default     = "artifacts/app-initial.zip"
}