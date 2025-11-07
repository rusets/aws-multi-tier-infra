############################################
# Output — ALB DNS (public, non-sensitive)
# Purpose: quick browser access to the app
############################################
output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.app.dns_name
}

############################################
# Output — RDS Endpoint (host, non-sensitive)
# Purpose: app/clients connect to the DB host
############################################
output "rds_endpoint" {
  description = "RDS instance endpoint hostname"
  value       = aws_db_instance.db.address
}

############################################
# Output — S3 Assets Bucket (non-sensitive)
# Purpose: where artifacts/static assets live
############################################
output "s3_assets_bucket" {
  description = "S3 bucket name for static assets (placeholder)"
  value       = aws_s3_bucket.assets.bucket
}

############################################
# Output — RDS Master Secret ARN (SENSITIVE)
# Purpose: reference to AWS-managed DB password
# Note: this hides in CLI/UI, but still exists in state
############################################
output "rds_master_secret_arn" {
  description = "ARN of the AWS-managed RDS master password secret (readable by EC2 role)"
  value       = aws_db_instance.db.master_user_secret[0].secret_arn
  sensitive   = true
}

############################################
# Output — Public HTTPS Domain (Route53/ACM)
# Purpose: main entrypoint for end users
############################################
output "domain_https_url" {
  description = "Public HTTPS URL"
  value       = "https://${var.domain_name}"
}
