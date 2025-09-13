############################################################
# Package and Upload Initial Application Artifact
############################################################

# Archive the local `app/` directory into a .zip file.
# This is the application code that will be deployed to EC2.
data "archive_file" "app_zip" {
  type        = "zip"
  source_dir  = "${path.module}/app"             # local folder with app sources
  output_path = "${path.module}/app-initial.zip" # output .zip on disk
}

# Upload the initial application artifact to the S3 assets bucket.
# EC2 instances will later download this zip from S3 during bootstrap.
resource "aws_s3_object" "app_initial" {
  bucket = aws_s3_bucket.assets.id
  key    = "artifacts/app-initial.zip"                    # S3 key (path inside the bucket)
  source = data.archive_file.app_zip.output_path          # local .zip file to upload
  etag   = filemd5(data.archive_file.app_zip.output_path) # ensures update if contents change
}

resource "aws_s3_bucket" "assets" {
  bucket = "${var.project_name}-assets-${random_id.suffix.hex}"

  # This automatically removes all objects when bucket is destroyed
  force_destroy = true

  tags = {
    project = var.project_name
  }
}