############################################################
# Project: AWS Multi-Tier Demo (VPC, ALB, EC2/ASG, RDS, S3)
# Goal: Production-style layout with least-privilege access
# Notes:
#  - RDS master password is generated/managed by AWS
#    (manage_master_user_password = true). Terraform never sees it.
#  - EC2 instances read non-secret config from SSM Parameter Store
#    and the DB password from Secrets Manager at runtime via IAM role.
#  - user_data is rendered via templatefile(); only 4 safe placeholders
#    are used to avoid Terraform interpolation issues.
############################################################

############################################################
# Providers & Versions
############################################################



############################################################
# Data Sources
############################################################
data "aws_availability_zones" "azs" { state = "available" }
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

############################################################
# Locals
############################################################
locals {
  # Use first two AZs for a small HA footprint
  azs = slice(data.aws_availability_zones.azs.names, 0, 2)

  # Common project tag applied across resources
  tags = { Project = var.project_name }
}

############################################################
# Networking: VPC, Subnets, Routing
############################################################
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

# Public subnets (for ALB & NAT-less demo instances)
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

# Default route to the internet via IGW
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associate both public subnets with the public route table
resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private subnets (for RDS)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  tags              = merge(local.tags, { Name = "${var.project_name}-private-${count.index}" })
}

############################################################
# Security Groups
############################################################

# ALB SG: expose HTTP/80 to the world, egress open
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol         = "tcp"
    from_port        = 80
    to_port          = 80
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = local.tags
}

# App SG: ALB -> app port; optional SSH from admin CIDR
resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-app-sg"
  description = "Security group for application instances"
  vpc_id      = aws_vpc.main.id

  # Egress open (instances fetch dependencies, talk to RDS, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# Ingress rule: allow HTTP traffic from ALB to the app port
resource "aws_security_group_rule" "app_http_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.app_sg.id
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
}

# Optional SSH access for administration (disabled if admin_cidr is empty)
resource "aws_security_group_rule" "app_ssh" {
  count             = var.admin_cidr == "" ? 0 : 1
  type              = "ingress"
  security_group_id = aws_security_group.app_sg.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.admin_cidr]
}

# RDS SG: allow DB connections only from app SG
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

############################################################
# Application Load Balancer (HTTP)
############################################################
resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
  tags               = local.tags
}

resource "aws_lb_target_group" "app_tg" {
  name     = "${var.project_name}-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # Simple HTTP health check against the Node app
  health_check {
    path                = "/health"
    interval            = 15
    unhealthy_threshold = 3
    healthy_threshold   = 2
    matcher             = "200-399"
  }

  tags = local.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

############################################################
# AMI: Amazon Linux 2023 (latest x86_64 HVM EBS)
############################################################
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["137112412989"] # Amazon

  filter {
    name   = "name"
    values = ["al2023-ami-20*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

############################################################
# RDS: managed password (Terraform never sees the secret)
############################################################
resource "aws_db_subnet_group" "db" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = aws_subnet.private[*].id
  tags       = local.tags
}

resource "aws_db_instance" "db" {
  identifier        = "${var.project_name}-db"
  engine            = var.rds_engine
  instance_class    = "db.t3.micro"
  allocated_storage = 20 # RDS minimum
  username          = var.rds_username

  manage_master_user_password = true # AWS generates & stores in Secrets Manager

  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  multi_az               = false
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false
  tags                   = local.tags
}

############################################################
# IAM for EC2:
#  - Instance role can read:
#     * non-secret config from SSM Parameter Store
#     * the specific RDS-generated secret in Secrets Manager
#  - Includes SSM Managed Instance Core for Session Manager, etc.
############################################################
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

data "aws_iam_policy_document" "ec2_access" {
  # SSM Parameter Store (non-secret parameters only)
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

  # KMS permissions to decrypt SSM SecureString if ever used later (safe default)
  statement {
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:ResourceAliases"
      values   = ["alias/aws/ssm"]
    }
  }

  # Secrets Manager access: ONLY the specific secret created by this RDS
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

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

############################################################
# User Data: rendered via templatefile() with four safe vars
############################################################
locals {
  rendered_user_data = templatefile("${path.module}/user_data.sh", {
    REGION         = var.region
    APP_PORT       = var.app_port
    PARAM_PATH     = var.param_path
    RDS_SECRET_ARN = try(aws_db_instance.db.master_user_secret[0].secret_arn, "")
  })
}
############################################################
# Launch Template & Auto Scaling Group
############################################################
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  user_data = base64encode(local.rendered_user_data)

  iam_instance_profile { name = aws_iam_instance_profile.ec2_profile.name }
  network_interfaces { security_groups = [aws_security_group.app_sg.id] }

  update_default_version = true

  tag_specifications {
    resource_type = "instance"
    tags          = local.tags
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.project_name}-asg"
  max_size                  = 2
  min_size                  = 1
  desired_capacity          = 1
  health_check_type         = "ELB"
  health_check_grace_period = 240
  vpc_zone_identifier       = aws_subnet.public[*].id
  target_group_arns         = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Propagate the project tag to EC2 for CI/CD targeting
  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}

############################################################
# S3 (optional assets / placeholder)
############################################################
resource "random_id" "rand" { byte_length = 3 }

resource "aws_s3_bucket" "assets" {
  bucket = "${var.project_name}-assets-${random_id.rand.hex}"
  tags   = local.tags
}