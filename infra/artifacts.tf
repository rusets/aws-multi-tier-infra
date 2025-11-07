############################################
# Random suffix for unique S3 bucket name
############################################
resource "random_id" "rand" {
  byte_length = 3
}

############################################
# S3 bucket for application artifacts
############################################
resource "aws_s3_bucket" "assets" {
  bucket        = "${var.project_name}-assets-${random_id.rand.hex}"
  force_destroy = true

  tags = {
    Project = var.project_name
  }
}

############################################
# Package local app/ into a ZIP (repo root)
############################################
data "archive_file" "app_zip" {
  type        = "zip"
  source_dir  = local.app_dir
  output_path = local.app_zip_path
}

############################################
# Upload the initial application artifact
# Use data.archive_file outputs to enforce ordering
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
