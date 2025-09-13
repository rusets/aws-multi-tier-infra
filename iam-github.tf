##############################
# GitHub OIDC + CI roles    #
# (uses only variables.tf)   #
##############################

# We do NOT read the OIDC provider via data source to avoid IAM read perms.
# Instead we pass its ARN via variable github_oidc_provider_arn.
locals {
  github_oidc_provider_arn = var.github_oidc_provider_arn
}

# ---------- Role for Terraform (infra pipeline) ----------
data "aws_iam_policy_document" "tf_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    # Required audience for GitHub OIDC
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Limit to this repository (all branches)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/*"]
    }
  }
}

resource "aws_iam_role" "github_tf" {
  name               = "multi-tier-demo-github-tf"
  description        = "Role for Terraform via GitHub Actions OIDC"
  assume_role_policy = data.aws_iam_policy_document.tf_assume.json

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      tags,
      assume_role_policy
    ]
  }
}

# Baseline permissions for Terraform in CI (broad AWS access EXCEPT IAM)
resource "aws_iam_role_policy_attachment" "tf_poweruser" {
  role       = aws_iam_role.github_tf.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# Extra IAM permissions Terraform needs because PowerUserAccess excludes IAM.
# Keep pragmatic and scoped to role/policy management + PassRole to EC2.
resource "aws_iam_policy" "tf_iam_extras" {
  name        = "${var.project_name}-tf-iam-extras"
  description = "Extra IAM permissions needed by Terraform when managing IAM resources"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "IamCrudForRolesPolicies",
        Effect = "Allow",
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:UpdateAssumeRolePolicy",
          "iam:TagRole", "iam:UntagRole",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy",
          "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
          "iam:GetPolicyVersion", "iam:ListPolicyVersions",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:GetRole", "iam:ListRoles",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:PassRole"
        ],
        Resource = "*"
      },
      {
        Sid       = "PassRoleToEC2Only",
        Effect    = "Allow",
        Action    = "iam:PassRole",
        Resource  = "arn:aws:iam::*:role/${var.project_name}-*",
        Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
      },
      {
        Sid      = "CreateServiceLinkedRoles",
        Effect   = "Allow",
        Action   = ["iam:CreateServiceLinkedRole"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "tf_iam_extras_attach" {
  role       = aws_iam_role.github_tf.name
  policy_arn = aws_iam_policy.tf_iam_extras.arn
}

# ---------- Role for App deploy (artifacts to S3, SSM params, ASG refresh) ----------
data "aws_iam_policy_document" "app_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/*"]
    }
  }
}

resource "aws_iam_role" "github_app" {
  name               = "multi-tier-demo-github-app"
  description        = "Role for App deploy via GitHub Actions OIDC"
  assume_role_policy = data.aws_iam_policy_document.app_assume.json

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      tags,
      assume_role_policy
    ]
  }
}

# App role: S3 artifacts + SSM params (under param_path) + ASG Instance Refresh
resource "aws_iam_role_policy" "github_app_artifacts_and_ssm" {
  name = "AppArtifactsAndSsmAccess"
  role = aws_iam_role.github_app.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # S3 list this bucket
      {
        Effect   = "Allow",
        Action   = ["s3:ListBucket"],
        Resource = "${aws_s3_bucket.assets.arn}"
      },
      # S3 read/write objects in this bucket (artifacts)
      {
        Effect   = "Allow",
        Action   = ["s3:PutObject", "s3:PutObjectAcl", "s3:GetObject", "s3:DeleteObject"],
        Resource = "${aws_s3_bucket.assets.arn}/*"
      },
      # SSM read/write limited to your base param path
      {
        Effect   = "Allow",
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter"],
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter${var.param_path}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_app_asg_refresh" {
  name = "AppAsgInstanceRefresh"
  role = aws_iam_role.github_app.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["autoscaling:StartInstanceRefresh", "autoscaling:DescribeInstanceRefreshes", "autoscaling:DescribeAutoScalingGroups"],
        Resource = "${aws_autoscaling_group.app.arn}"
      }
    ]
  })
}

# ---------- EC2 policy to read artifacts from S3 (attach to EC2 role used by ASG) ----------
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
  name        = "${var.project_name}-ec2-s3-read"
  description = "Allow EC2 instances to list and get objects from the S3 assets bucket"
  policy      = data.aws_iam_policy_document.ec2_s3_read.json
}

resource "aws_iam_role_policy_attachment" "attach_s3_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_s3_read.arn
}

# Minimal permissions for Terraform backend (S3 state + DynamoDB lock)
locals {
  tf_state_bucket = "multi-tier-demo-tfstate-097635932419-e7f2c4"
  tf_lock_table   = "multi-tier-demo-tf-locks"
  region          = "us-east-1"
  account_id      = "097635932419"
}

resource "aws_iam_policy" "tf_backend" {
  name        = "${var.project_name}-tf-backend"
  description = "Allow CI role to read/write Terraform state in S3 and use DynamoDB locking"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "ListStateBucket",
        Effect   = "Allow",
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"],
        Resource = "arn:aws:s3:::${local.tf_state_bucket}"
      },
      {
        Sid    = "RWStateObjects",
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject",
        "s3:GetObjectVersion", "s3:AbortMultipartUpload", "s3:ListBucketMultipartUploads"],
        Resource = "arn:aws:s3:::${local.tf_state_bucket}/*"
      },
      {
        Sid      = "DynamoDBLocking",
        Effect   = "Allow",
        Action   = ["dynamodb:DescribeTable", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:UpdateItem"],
        Resource = "arn:aws:dynamodb:${local.region}:${local.account_id}:table/${local.tf_lock_table}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "tf_backend_attach" {
  role       = aws_iam_role.github_tf.name
  policy_arn = aws_iam_policy.tf_backend.arn
}