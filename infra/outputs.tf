############################################
# Outputs — public and sensitive values
############################################

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.app.dns_name
}

output "rds_endpoint" {
  description = "RDS instance endpoint hostname"
  value       = aws_db_instance.db.address
}

output "s3_assets_bucket" {
  description = "S3 bucket name for static assets (placeholder)"
  value       = aws_s3_bucket.assets.bucket
}

output "rds_master_secret_arn" {
  description = "ARN of the AWS-managed RDS master password secret (readable by EC2 role)"
  value       = aws_db_instance.db.master_user_secret[0].secret_arn
  sensitive   = true
}

output "domain_https_url" {
  description = "Public HTTPS URL"
  value       = "https://${var.domain_name}"
}
