############################################################
# Useful Outputs
# These values are shown after `terraform apply`
# and can also be consumed by other modules or pipelines.
############################################################

# Public DNS name of the Application Load Balancer (ALB).
# Use this to access your application in a browser.
output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.app.dns_name
}

# Hostname endpoint of the RDS instance (without port).
# This is the value used by applications to connect to the DB.
output "rds_endpoint" {
  description = "RDS instance endpoint hostname"
  value       = aws_db_instance.db.address
}

# Name of the S3 bucket that stores static assets / application artifacts.
# Helpful for deploying front-end files or uploading application packages.
output "s3_assets_bucket" {
  description = "S3 bucket name for static assets (placeholder)"
  value       = aws_s3_bucket.assets.bucket
}

# ARN (Amazon Resource Name) of the AWS-managed RDS master password secret.
# ⚠️ This does NOT expose the actual password, only the ARN.
# The EC2 instance role has permission to read this secret at runtime.
output "rds_master_secret_arn" {
  description = "ARN of the AWS-managed RDS master password secret (readable by EC2 role)"
  value       = aws_db_instance.db.master_user_secret[0].secret_arn
}