############################################
# App Security Group — instances behind ALB
# Purpose: inbound only from ALB; outbound to Internet for SSM/npm/yum
############################################
#tfsec:ignore:aws-ec2-no-public-egress-sgr
resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-app-sg"
  description = "Security group for application instances"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic to Internet (demo)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
  }
}
############################################
# ALB Security Group — public HTTP/HTTPS
# Purpose: ALB *must* be public, so ingress 0.0.0.0/0 is deliberate.
#tfsec: ignore public ingress warnings here (public web endpoint)
############################################
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  #tfsec:ignore:aws-ec2-no-public-ingress-sgr
  ingress {
    description = "Allow HTTP from anywhere"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  #tfsec:ignore:aws-ec2-no-public-ingress-sgr
  ingress {
    description = "Allow HTTPS from anywhere"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ALB egress restricted to VPC CIDR (targets inside VPC)
  egress {
    description = "Allow all outbound traffic within VPC CIDR"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = [var.vpc_cidr]
  }

  revoke_rules_on_delete = true

  tags = local.tags

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [description]
  }
}

############################################
# App SG Rule — allow ALB → app port
# Purpose: EC2 instances only accept traffic from ALB SG
############################################
resource "aws_security_group_rule" "app_http_from_alb" {
  type                     = "ingress"
  description              = "Allow app HTTP traffic from ALB security group"
  security_group_id        = aws_security_group.app_sg.id
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
}

############################################
# RDS Security Group — allow from app only
# Purpose: RDS is private, only app instances can access DB
############################################
resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.main.id

  # Restrict egress to VPC CIDR (remove 0.0.0.0/0)
  egress {
    description = "Allow all outbound traffic within VPC CIDR"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = local.tags
}

############################################
# RDS SG Rule — allow DB port from app SG
# Purpose: DB only accepts traffic from app instances
############################################
resource "aws_security_group_rule" "rds_from_app" {
  type                     = "ingress"
  description              = "Allow DB traffic from app security group"
  security_group_id        = aws_security_group.rds_sg.id
  from_port                = var.rds_engine == "postgres" ? 5432 : 3306
  to_port                  = var.rds_engine == "postgres" ? 5432 : 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app_sg.id
}

############################################
# DNS — apex A ALIAS → ALB (IPv4)
############################################
resource "aws_route53_record" "apex_a" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

############################################
# DNS — www CNAME → apex (optional)
############################################
resource "aws_route53_record" "www_cname" {
  count   = var.enable_www_alias ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = [var.domain_name]
}

############################################
# ALB Listener — HTTPS :443 → Target Group
############################################
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}
