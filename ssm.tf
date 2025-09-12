locals {
  # Canonical SSM root path (no trailing slash)
  ssm_root = "/${var.namespace}"
}

# ---- App parameters ----
resource "aws_ssm_parameter" "assets_bucket" {
  name        = "${local.ssm_root}/assets_bucket"
  type        = "String"
  value       = aws_s3_bucket.assets.bucket
  description = "S3 bucket that stores application artifacts"
  tags        = { project = var.namespace }
}

resource "aws_ssm_parameter" "app_artifact_key" {
  name        = "${local.ssm_root}/app/artifact_key"
  type        = "String"
  value       = "artifacts/app-initial.zip" # or your CI pipeline value
  description = "S3 key for the application artifact"
  tags        = { project = var.namespace }
  overwrite = true  # Always overwrite existing parameter value
}


resource "aws_ssm_parameter" "app_port" {
  name        = "${local.ssm_root}/app/app_port"
  type        = "String"
  value       = tostring(var.app_port)
  description = "Application port (string for convenience in bash)"
  tags        = { project = var.namespace }
  overwrite = true  # Always overwrite existing parameter value
}

# ---- DB parameters (non-secret) ----
resource "aws_ssm_parameter" "db_host" {
  name        = "${local.ssm_root}/db/host"
  type        = "String"
  value       = aws_db_instance.db.address
  description = "RDS hostname"
  tags        = { project = var.namespace }
  overwrite = true  # Always overwrite existing parameter value
}

resource "aws_ssm_parameter" "db_username" {
  name        = "${local.ssm_root}/db/username"
  type        = "String"
  value       = aws_db_instance.db.username
  description = "RDS master username"
  tags        = { project = var.namespace }
  overwrite = true  # Always overwrite existing parameter value
}

resource "aws_ssm_parameter" "db_name" {
  name        = "${local.ssm_root}/db/name"
  type        = "String"
  value       = "notes"
  description = "Application database name"
  tags        = { project = var.namespace }
  overwrite = true  # Always overwrite existing parameter value
}

# ---- DB password in SSM is OPTIONAL (use Secrets Manager instead if possible) ----
# If you insist on writing it, enable var.ssm_write_db_password and provide var.ssm_kms_key_id.
resource "aws_ssm_parameter" "db_password" {
  count       = var.ssm_write_db_password ? 1 : 0
  name        = "${local.ssm_root}/db/password"
  type        = "SecureString"
  key_id      = var.ssm_kms_key_id
  value       = aws_db_instance.db.password # If you set manage_master_user_password=true you won't have this. Prefer Secrets Manager.
  description = "RDS master password (SecureString). Prefer Secrets Manager; keep this disabled by default."
  tags        = { project = var.namespace }
  overwrite = true  # Always overwrite existing parameter value
}