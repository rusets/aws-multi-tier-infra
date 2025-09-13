##############################
# GitHub OIDC + CI roles    #
# (comments are in English) #
##############################

# Use existing GitHub OIDC provider (do NOT create a duplicate)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ---------- Role for Terraform (infra pipeline) ----------
# Trust policy limited to your repo (any branch)
data "aws_iam_policy_document" "tf_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    # GitHub OIDC audience must be sts.amazonaws.com
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
}

# Baseline permissions for Terraform in CI
resource "aws_iam_role_policy_attachment" "tf_poweruser" {
  role       = aws_iam_role.github_tf.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# Extra IAM permissions that PowerUserAccess does not include (IAM is excluded)
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
          "iam:PassRole",
          "iam:GetRole",
          "iam:ListRoles",
          "iam:ListOpenIDConnectProviders",
          "iam:GetOpenIDConnectProvider"

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
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
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