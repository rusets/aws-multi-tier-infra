############################################
# Random suffix for unique S3 bucket names
############################################
resource "random_id" "rand" {
  byte_length = 3
}

############################################
# S3 Bucket — access logs for assets bucket
############################################
resource "aws_s3_bucket" "assets_logs" { #tfsec:ignore:aws-s3-enable-bucket-logging
  #checkov:skip=CKV_AWS_144: Cross-region replication not required for short-lived demo logs
  #checkov:skip=CKV_AWS_145: SSE-S3 (AES256) is sufficient; CMK not required for demo
  #checkov:skip=CKV2_AWS_62: Event notifications are not used in this demo
  bucket        = "${var.project_name}-assets-logs-${random_id.rand.hex}"
  force_destroy = true

  tags = {
    Project = var.project_name
    Purpose = "access-logs"
  }
}

############################################
# S3 Bucket Encryption — assets_logs
############################################
resource "aws_s3_bucket_server_side_encryption_configuration" "assets_logs_sse" { #tfsec:ignore:aws-s3-encryption-customer-key
  bucket = aws_s3_bucket.assets_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

############################################
# Versioning — assets_logs
############################################
resource "aws_s3_bucket_versioning" "assets_logs_versioning" {
  bucket = aws_s3_bucket.assets_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

############################################
# Public Access Block — assets_logs
############################################
resource "aws_s3_bucket_public_access_block" "assets_logs_block" {
  bucket = aws_s3_bucket.assets_logs.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

############################################
# Lifecycle — expire logs (30 days)
############################################
resource "aws_s3_bucket_lifecycle_configuration" "assets_logs_lifecycle" {
  bucket = aws_s3_bucket.assets_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

############################################
# S3 Bucket — application artifacts
############################################
resource "aws_s3_bucket" "assets" {
  #checkov:skip=CKV_AWS_144: Cross-region replication not required for demo artifacts
  #checkov:skip=CKV_AWS_145: SSE-S3 (AES256) is sufficient; CMK not required for demo
  #checkov:skip=CKV2_AWS_62: Event notifications are not used in this demo
  bucket        = "${var.project_name}-assets-${random_id.rand.hex}"
  force_destroy = true

  tags = {
    Project = var.project_name
  }
}

############################################
# S3 Bucket Encryption — assets
############################################
resource "aws_s3_bucket_server_side_encryption_configuration" "assets_sse" { #tfsec:ignore:aws-s3-encryption-customer-key
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

############################################
# Logging — assets -> assets_logs
############################################
resource "aws_s3_bucket_logging" "assets_logging" {
  bucket = aws_s3_bucket.assets.id

  target_bucket = aws_s3_bucket.assets_logs.id
  target_prefix = "assets/"
}

############################################
# Versioning — assets
############################################
resource "aws_s3_bucket_versioning" "assets_versioning" {
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

############################################
# Public Access Block — assets
############################################
resource "aws_s3_bucket_public_access_block" "assets_block" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

############################################
# Lifecycle — expire artifacts (90 days)
############################################
resource "aws_s3_bucket_lifecycle_configuration" "assets_lifecycle" {
  bucket = aws_s3_bucket.assets.id

  rule {
    id     = "expire-artifacts"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

############################################
# Archive application into ZIP
############################################
data "archive_file" "app_zip" {
  type        = "zip"
  source_dir  = local.app_dir
  output_path = local.app_zip_path
}

############################################
# Upload initial application artifact
############################################
resource "aws_s3_object" "app_initial" {
  bucket       = aws_s3_bucket.assets.id
  key          = "artifacts/app-initial.zip"
  source       = data.archive_file.app_zip.output_path
  etag         = data.archive_file.app_zip.output_md5
  content_type = "application/zip"

  tags = {
    Project = var.project_name
  }
}
