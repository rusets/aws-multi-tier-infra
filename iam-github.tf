##############################
# GitHub OIDC + CI roles    #
# (comments are in English) #
##############################

# Which GitHub repo can assume these roles (format: owner/repo)
variable "github_repo" {
  description = "GitHub repository allowed to assume OIDC roles (format: owner/repo)"
  type        = string
  default     = "rusets/aws-multi-tier-infra"
}

# Read EXISTING GitHub OIDC provider (do not create a duplicate)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ---------- Role for Terraform (infra pipeline) ----------
data "aws_iam_policy_document" "tf_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"
      # IMPORTANT: use data.* (existing provider), not resource.*
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    # Audience must be sts.amazonaws.com for GitHub OIDC
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to this repository (any branch)
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

# Pragmatic baseline: PowerUserAccess
resource "aws_iam_role_policy_attachment" "tf_poweruser" {
  role       = aws_iam_role.github_tf.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# Extra IAM it often needs in restricted orgs (TagRole, ListInstanceProfiles, etc.)
# Enable by default; remove if your org policies already allow it.
resource "aws_iam_policy" "tf_iam_extras" {
  name        = "multi-tier-demo-tf-iam-extras"
  description = "Extra IAM permissions for Terraform when org/SCP is strict"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "IamReadWriteForRolesPolicies",
        Effect = "Allow",
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy",
          "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
          "iam:GetPolicyVersion", "iam:ListPolicyVersions",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:PassRole"
        ],
        Resource = "*"
      },
      {
        Sid       = "PassRoleToEC2Only",
        Effect    = "Allow",
        Action    = "iam:PassRole",
        Resource  = "arn:aws:iam::*:role/multi-tier-demo-*",
        Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
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
  assume_role_policy = data.aws_iam_policy_document.app_assume.json
  description        = "Role for App deploy via GitHub Actions OIDC"
}

# App role: S3 artifacts + SSM params under configured param_path
resource "aws_iam_role_policy" "github_app_artifacts_and_ssm" {
  name = "AppArtifactsAndSsmAccess"
  role = aws_iam_role.github_app.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # List that specific bucket
      {
        Effect   = "Allow",
        Action   = ["s3:ListBucket"],
        Resource = "${aws_s3_bucket.assets.arn}"
      },
      # Work with objects inside that bucket
      {
        Effect   = "Allow",
        Action   = ["s3:PutObject", "s3:PutObjectAcl", "s3:GetObject", "s3:DeleteObject"],
        Resource = "${aws_s3_bucket.assets.arn}/*"
      },
      # Read/write SSM params only under the chosen path
      {
        Effect   = "Allow",
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter"],
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter${var.param_path}/*"
      }
    ]
  })
}

# Allow CI to trigger Instance Refresh on our ASG
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
  name        = "multi-tier-demo-ec2-s3-read"
  description = "Allow EC2 instances to list and get objects from the S3 assets bucket"
  policy      = data.aws_iam_policy_document.ec2_s3_read.json
}

resource "aws_iam_role_policy_attachment" "attach_s3_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_s3_read.arn
}