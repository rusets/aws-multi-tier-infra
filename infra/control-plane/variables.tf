############################################
# Variables — control-plane settings
############################################

############################################
# General project metadata
############################################
variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "multi-tier-demo"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

############################################
# Existing API Gateway configuration
############################################
variable "existing_http_api_name" {
  description = "Existing HTTP API name"
  type        = string
  default     = "multi-tier-wait-api"
}

variable "api_stage_name" {
  description = "HTTP API stage"
  type        = string
  default     = "prod"
}

############################################
# Public domain & static bucket
############################################
variable "domain_name" {
  description = "Primary HTTPS domain"
  type        = string
  default     = "multi-tier.space"
}

variable "wait_site_bucket_name" {
  description = "S3 bucket with waiting UI"
  type        = string
  default     = "multi-tier-demo-wait-site"
}

variable "wait_site_prefix" {
  description = "Optional prefix for status.json"
  type        = string
  default     = ""
}

############################################
# Operational parameters
############################################
variable "lambda_log_retention_days" {
  description = "CloudWatch retention days"
  type        = number
  default     = 14
}

variable "heartbeat_param" {
  description = "SSM param for last heartbeat"
  type        = string
  default     = "/multi-tier/last_heartbeat"
}

variable "idle_minutes" {
  description = "Idle minutes for auto-destroy"
  type        = number
  default     = 20
}

variable "status_request_timeout" {
  description = "HTTP status probe timeout"
  type        = number
  default     = 2.5
}

############################################
# GitHub Actions integration
############################################
variable "gh_owner" {
  description = "GitHub owner"
  type        = string
  default     = "rusets"
}

variable "gh_repo" {
  description = "GitHub repository"
  type        = string
  default     = "aws-multi-tier-infra"
}

variable "gh_workflow" {
  description = "Workflow file name"
  type        = string
  default     = "infra.yml"
}

############################################
# GitHub dispatch settings
############################################
variable "gh_ref" {
  description = "Git ref for workflow_dispatch (branch name only, e.g., main)"
  type        = string
  default     = "main"
}

variable "gh_secret_name" {
  description = "Secrets Manager name of PAT"
  type        = string
  default     = "gh/actions/token"
}

############################################
# Existing HTTP API identification
############################################
variable "existing_http_api_id" {
  description = "Existing HTTP API ID (e.g., e40una40of). Preferred over name."
  type        = string
  default     = "e40una40of"
}
