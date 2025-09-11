##############################
# GitHub OIDC + roles for CI #
##############################

# Which GitHub repo is allowed to assume these roles (format: owner/repo)
variable "github_repo" {
  description = "GitHub repository allowed to assume OIDC roles (format: owner/repo)"
  type        = string
  default     = "rusets/aws-multi-tier-infra"
}

# ---------- OIDC provider for GitHub Actions ----------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's well-known thumbprint; update if GitHub publishes changes
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# ---------- Role for Terraform (infra pipeline) ----------
data "aws_iam_policy_document" "tf_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Limit to this repository (any branch)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/*"]
    }
  }
}

resource "aws_iam_role" "github_tf" {
  name               = "multi-tier-demo-github-tf"
  assume_role_policy = data.aws_iam_policy_document.tf_assume.json
  description        = "Role for Terraform via GitHub Actions OIDC"
}

# Simple and pragmatic: PowerUserAccess + allow creation of service-linked roles
resource "aws_iam_role_policy_attachment" "tf_poweruser" {
  role       = aws_iam_role.github_tf.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "tf_slr" {
  name = "AllowServiceLinkedRoles"
  role = aws_iam_role.github_tf.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["iam:CreateServiceLinkedRole"],
      Resource = "*"
    }]
  })
}

# ---------- Role for App deploy (CI uploads to S3, updates SSM, can trigger ASG refresh) ----------
data "aws_iam_policy_document" "app_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Limit to this repository (any branch)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/*"]
    }
  }
}

resource "aws_iam_role" "github_app" {
  name               = "multi-tier-demo-github-app"
  assume_role_policy = data.aws_iam_policy_document.app_assume.json
  description        = "Role for App deploy via GitHub Actions OIDC"
}

# Inline policy for the App deploy role:
# - S3: upload/read artifacts only in our assets bucket
# - SSM: read/write parameters only under our configured path
resource "aws_iam_role_policy" "github_app_artifacts_and_ssm" {
  name = "AppArtifactsAndSsmAccess"
  role = aws_iam_role.github_app.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # S3 list the specific bucket
      {
        Effect   = "Allow",
        Action   = ["s3:ListBucket"],
        Resource = "${aws_s3_bucket.assets.arn}"
      },
      # S3 upload/read objects within that bucket (artifacts/* etc.)
      {
        Effect   = "Allow",
        Action   = ["s3:PutObject", "s3:PutObjectAcl", "s3:GetObject", "s3:DeleteObject"],
        Resource = "${aws_s3_bucket.assets.arn}/*"
      },
      # SSM: read/write parameters only under our namespace
      {
        Effect   = "Allow",
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter"],
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter${var.param_path}/*"
      }
    ]
  })
}

# Allow CI to trigger a rolling Instance Refresh on the target AutoScalingGroup
# (so new artifact is picked by fresh instances right away)
resource "aws_iam_role_policy" "github_app_asg_refresh" {
  name = "AppAsgInstanceRefresh"
  role = aws_iam_role.github_app.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "autoscaling:StartInstanceRefresh",
          "autoscaling:DescribeInstanceRefreshes",
          "autoscaling:DescribeAutoScalingGroups"
        ],
        Resource = "${aws_autoscaling_group.app.arn}"
      }
    ]
  })
}

# ---------- Managed policy for EC2 role to read artifacts from S3 (attach to app instances) ----------
data "aws_iam_policy_document" "ec2_s3_read" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.assets.arn]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.assets.arn}/*"]
  }
}

resource "aws_iam_policy" "ec2_s3_read" {
  name        = "multi-tier-demo-ec2-s3-read"
  description = "Allow EC2 instances to list and get objects from the S3 assets bucket"
  policy      = data.aws_iam_policy_document.ec2_s3_read.json
}

# Attach EC2 S3 read policy to the instance role used by your ASG
resource "aws_iam_role_policy_attachment" "attach_s3_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_s3_read.arn
}