############################################################
# Package and Upload Initial Application Artifact
# (comments are in English)
############################################################

# Create random suffix to ensure unique bucket name
resource "random_id" "rand" {
  byte_length = 3
}

# S3 bucket for application artifacts
resource "aws_s3_bucket" "assets" {
  bucket        = "${var.project_name}-assets-${random_id.rand.hex}"
  force_destroy = true # allow destroy even if bucket is not empty
  tags = {
    Project = var.project_name
  }
}

# Archive the local `app/` directory into a .zip file
data "archive_file" "app_zip" {
  type        = "zip"
  source_dir  = "${path.module}/app"             # local folder with app sources
  output_path = "${path.module}/app-initial.zip" # output .zip on disk
}

# Upload the initial application artifact to the S3 assets bucket
resource "aws_s3_object" "app_initial" {
  bucket = aws_s3_bucket.assets.id
  key    = "artifacts/app-initial.zip"                    # S3 key (path inside the bucket)
  source = data.archive_file.app_zip.output_path          # local .zip file to upload
  etag   = filemd5(data.archive_file.app_zip.output_path) # ensures update if contents change
}