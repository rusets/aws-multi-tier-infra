############################################
# SSM Parameters — canonical config paths
# Principle: single namespace, no trailing slash
############################################
locals {
  ssm_root = var.param_path != "" ? var.param_path : "/${var.namespace}"
}

############################################
# App — S3 bucket name for artifacts
# Principle: read by EC2/user-data at runtime
############################################
resource "aws_ssm_parameter" "assets_bucket" {
  name        = "${local.ssm_root}/assets_bucket"
  type        = "String"
  value       = aws_s3_bucket.assets.bucket
  description = "S3 bucket that stores application artifacts"
  overwrite   = true
}

############################################
# App — S3 object key of current artifact
# Principle: decouple infra from CI versioning
############################################}
resource "aws_ssm_parameter" "app_artifact_key" {
  name        = "${local.ssm_root}/app/artifact_key"
  type        = "String"
  value       = var.app_artifact_key
  description = "S3 key for the application artifact"
  overwrite   = true
}

############################################
# App — internal HTTP port (string for bash)
# Principle: convenience in shell templates
############################################
resource "aws_ssm_parameter" "app_port" {
  name        = "${local.ssm_root}/app/app_port"
  type        = "String"
  value       = tostring(var.app_port)
  description = "Application port (string for convenience in bash)"
  overwrite   = true
}

############################################
# DB — hostname endpoint (non-secret)
# Principle: discoverable by app on boot
############################################
resource "aws_ssm_parameter" "db_host" {
  name        = "${local.ssm_root}/db/host"
  type        = "String"
  value       = aws_db_instance.db.address
  description = "RDS hostname"
  overwrite   = true
}

############################################
# DB — master username (non-secret)
# Principle: password stays in Secrets Manager
############################################
resource "aws_ssm_parameter" "db_username" {
  name        = "${local.ssm_root}/db/username"
  type        = "String"
  value       = aws_db_instance.db.username
  description = "RDS master username"
  overwrite   = true
}

############################################
# DB — logical database name (app scope)
# Principle: avoids hard-coding in user-data
############################################
resource "aws_ssm_parameter" "db_name" {
  name        = "${local.ssm_root}/db/name"
  type        = "String"
  value       = "notes"
  description = "Application database name"
  overwrite   = true
}

############################################
# DB — optional password in SSM (SecureString)
# Principle: prefer AWS-managed secret in SM
############################################
resource "aws_ssm_parameter" "db_password" {
  count       = var.ssm_write_db_password ? 1 : 0
  name        = "${local.ssm_root}/db/password"
  type        = "SecureString"
  key_id      = var.ssm_kms_key_id
  value       = "" # keep empty unless you truly self-manage the password
  description = "RDS master password (SecureString). Prefer Secrets Manager; keep disabled by default."
  overwrite   = true
}
