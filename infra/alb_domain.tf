############################################
# ALB Domain / Security Groups (Variant B)
# SG shells без inline-правил; правила — отдельные aws_security_group_rule
# IPv6 не используем (только IPv4)
############################################

############################################
# App Security Group — instances behind ALB
############################################
resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-app-sg"
  description = "Security group for application instances"
  vpc_id      = aws_vpc.main.id

  egress {
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
# ALB Security Group — empty shell (rules = separate resources)
############################################
############################################
# ALB Security Group — inline rules (80/443 + egress all)
############################################
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  # :80 HTTP from anywhere
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  # :443 HTTPS from anywhere
  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress allow all (IPv4)
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
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
############################################
resource "aws_security_group_rule" "app_http_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.app_sg.id
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
}

############################################
# RDS Security Group — shell + rule from app SG
############################################
resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_security_group_rule" "rds_from_app" {
  type                     = "ingress"
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
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}
