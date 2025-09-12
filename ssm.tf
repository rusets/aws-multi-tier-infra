########################################
# SSM Parameters (comments in English) #
########################################

locals {
  # Canonical SSM root path (no trailing slash). Example: "/multi-tier-demo"
  ssm_root = "/${var.namespace}"
}

# ---- App parameters ----
resource "aws_ssm_parameter" "assets_bucket" {
  name        = "${local.ssm_root}/assets_bucket"
  type        = "String"
  value       = aws_s3_bucket.assets.bucket
  description = "S3 bucket that stores application artifacts"
  tags        = { project = var.project_name }
  overwrite   = true
}

resource "aws_ssm_parameter" "app_artifact_key" {
  name        = "${local.ssm_root}/app/artifact_key"
  type        = "String"
  value       = var.app_artifact_key
  description = "S3 key for the application artifact"
  tags        = { project = var.project_name }
  overwrite   = true
}

resource "aws_ssm_parameter" "app_port" {
  name        = "${local.ssm_root}/app/app_port"
  type        = "String"
  value       = tostring(var.app_port)
  description = "Application port (string for convenience in bash)"
  tags        = { project = var.project_name }
  overwrite   = true
}

# ---- DB parameters (non-secret) ----
resource "aws_ssm_parameter" "db_host" {
  name        = "${local.ssm_root}/db/host"
  type        = "String"
  value       = aws_db_instance.db.address
  description = "RDS hostname"
  tags        = { project = var.project_name }
  overwrite   = true
}

resource "aws_ssm_parameter" "db_username" {
  name        = "${local.ssm_root}/db/username"
  type        = "String"
  value       = aws_db_instance.db.username
  description = "RDS master username"
  tags        = { project = var.project_name }
  overwrite   = true
}

resource "aws_ssm_parameter" "db_name" {
  name        = "${local.ssm_root}/db/name"
  type        = "String"
  value       = "notes"
  description = "Application database name"
  tags        = { project = var.project_name }
  overwrite   = true
}

# ---- Optional: write DB password to SSM (prefer Secrets Manager instead) ----
resource "aws_ssm_parameter" "db_password" {
  count       = var.ssm_write_db_password ? 1 : 0
  name        = "${local.ssm_root}/db/password"
  type        = "SecureString"
  key_id      = var.ssm_kms_key_id
  value       = "" # supply only if you truly manage the password yourself
  description = "RDS master password (SecureString). Prefer Secrets Manager; keep disabled by default."
  tags        = { project = var.project_name }
  overwrite   = true
}