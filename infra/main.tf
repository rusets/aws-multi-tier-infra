############################################
# Project: AWS Multi-Tier Demo (VPC, ALB, EC2/ASG, RDS, S3)
############################################

############################################
# Data Sources — region/account/AZs/partition
############################################
data "aws_availability_zones" "azs" { state = "available" }
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

############################################
# Locals — tags and compact 2-AZ footprint
############################################
locals {
  azs  = slice(data.aws_availability_zones.azs.names, 0, 2)
  tags = { Project = var.project_name }
}

############################################
# Networking — VPC + IGW
############################################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.tags, { Name = "${var.project_name}-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${var.project_name}-igw" })
}

############################################
# Subnets — public (ALB/EC2) and private (RDS)
############################################
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  map_public_ip_on_launch = true
  tags                    = merge(local.tags, { Name = "${var.project_name}-public-${count.index}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${var.project_name}-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  tags              = merge(local.tags, { Name = "${var.project_name}-private-${count.index}" })
}

############################################
# Load Balancer — ALB (references SG from alb_domain.tf)
############################################
resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
  tags               = local.tags
}

############################################
# Target Group — HTTP on app port (health checks from vars)
############################################
resource "aws_lb_target_group" "app_tg" {
  name        = "${var.project_name}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Project = var.project_name }
}

############################################
# Listener — HTTP :80 → 301 → HTTPS :443
############################################
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


############################################
# RDS — subnet group + instance (AWS-managed master secret)
############################################
resource "aws_db_subnet_group" "db" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = aws_subnet.private[*].id
  tags       = local.tags
}

resource "aws_db_instance" "db" {
  identifier        = "${var.project_name}-db"
  engine            = var.rds_engine
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  username          = var.rds_username

  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.db.name
  vpc_security_group_ids      = [aws_security_group.rds_sg.id]
  multi_az                    = false
  publicly_accessible         = false
  skip_final_snapshot         = true
  deletion_protection         = false
  tags                        = local.tags
}

############################################
# IAM — EC2 role + instance profile
############################################
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = local.tags
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

############################################
# IAM — EC2 S3 read (assets bucket)
############################################
data "aws_iam_policy_document" "ec2_s3_read" {
  statement {
    sid       = "ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.assets.arn]
  }

  statement {
    sid       = "GetObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.assets.arn}/*"]
  }
}

resource "aws_iam_policy" "ec2_s3_read" {
  name        = "${var.project_name}-ec2-s3-read"
  description = "Allow EC2 to list bucket and get objects from assets bucket"
  policy      = data.aws_iam_policy_document.ec2_s3_read.json
}

resource "aws_iam_role_policy_attachment" "ec2_attach_s3_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_s3_read.arn
}

############################################
# IAM — EC2 app config + RDS secret access
############################################
data "aws_iam_policy_document" "ec2_access" {
  statement {
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:GetParameterHistory"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter/${trim(var.param_path, "/")}/*",
      "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter/app/*"
    ]
  }

  statement {
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:ResourceAliases"
      values   = ["alias/aws/ssm"]
    }
  }

  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_db_instance.db.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_policy" "ec2_access" {
  name   = "${var.project_name}-ec2-access"
  policy = data.aws_iam_policy_document.ec2_access.json
}

resource "aws_iam_role_policy_attachment" "attach_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_access.arn
}

resource "aws_iam_role_policy_attachment" "attach_ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

############################################
# Compute — user_data via templatefile()
############################################
locals {
  rendered_user_data = templatefile(local.user_data, {
    REGION         = var.region
    APP_PORT       = var.app_port
    PARAM_PATH     = var.param_path
    RDS_SECRET_ARN = try(aws_db_instance.db.master_user_secret[0].secret_arn, "")
  })
}

#############################################
# Compute — Launch Template + ASG
############################################
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  user_data = base64encode(local.rendered_user_data)

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  network_interfaces {
    security_groups = [aws_security_group.app_sg.id]
  }

  update_default_version = true

  tag_specifications {
    resource_type = "instance"
    tags          = local.tags
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.project_name}-asg"
  max_size                  = 1
  min_size                  = 1
  desired_capacity          = 1
  health_check_type         = "ELB"
  health_check_grace_period = 300
  vpc_zone_identifier       = aws_subnet.public[*].id
  target_group_arns         = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}
