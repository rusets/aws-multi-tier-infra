############################################
# Lambda trust policy (assume role)
############################################
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com",
      ]
    }
  }
}

############################################
# Ensure ./dist for ZIP artifacts
############################################
resource "null_resource" "ensure_dist" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/dist"
  }
}

############################################
# Build step — wake Lambda deps (npm ci → install fallback)
# Goal: always package node_modules into wake.zip
############################################
resource "null_resource" "wake_npm_ci" {
  triggers = {
    package_json_hash = filesha1("${path.module}/../../lambda/wake/package.json")
    lockfile_hash     = try(filesha1("${path.module}/../../lambda/wake/package-lock.json"), "no-lock")
  }

  provisioner "local-exec" {
    interpreter = [
      "/usr/bin/env",
      "bash",
      "-lc",
    ]
    command = <<-EOC
      set -euo pipefail
      cd "${path.module}/../../lambda/wake"
      npm ci --omit=dev || npm install --omit=dev
    EOC
  }
}

############################################
# Artifacts — wake.zip (Node), status.zip (Python)
############################################
data "archive_file" "wake_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/wake"
  output_path = "${path.module}/dist/wake.zip"

  depends_on = [
    null_resource.ensure_dist,
    null_resource.wake_npm_ci,
  ]
}

data "archive_file" "status_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/status"
  output_path = "${path.module}/dist/status.zip"

  depends_on = [
    null_resource.ensure_dist,
  ]
}

############################################
# IAM — roles for wake & status
############################################
resource "aws_iam_role" "wake_role" {
  name               = "${var.project_name}-wake-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "status_role" {
  name               = "${var.project_name}-status-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

############################################
# CloudWatch Logs basic policy attachments
############################################
resource "aws_iam_role_policy_attachment" "wake_logs" {
  role       = aws_iam_role.wake_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "status_logs" {
  role       = aws_iam_role.status_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

############################################
# Secrets — GitHub PAT read for wake
############################################
data "aws_secretsmanager_secret" "gh_pat" {
  name = var.gh_secret_name
}

data "aws_iam_policy_document" "wake_secret_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      data.aws_secretsmanager_secret.gh_pat.arn,
    ]
  }
}

resource "aws_iam_policy" "wake_secret_read" {
  name   = "${var.project_name}-wake-secret-read"
  policy = data.aws_iam_policy_document.wake_secret_read.json
}

resource "aws_iam_role_policy_attachment" "wake_secret_attach" {
  role       = aws_iam_role.wake_role.name
  policy_arn = aws_iam_policy.wake_secret_read.arn
}

############################################
# Lambda — wake (Node.js 20 / arm64)
############################################
resource "aws_lambda_function" "wake" {
  function_name    = "${var.project_name}-wake"
  role             = aws_iam_role.wake_role.arn
  filename         = data.archive_file.wake_zip.output_path
  source_code_hash = data.archive_file.wake_zip.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  architectures = [
    "arm64",
  ]
  timeout                        = 30
  memory_size                    = 256
  reserved_concurrent_executions = 5
  publish                        = true

  environment {
    variables = {
      GH_OWNER           = "rusets"
      GH_REPO            = "aws-multi-tier-infra"
      GITHUB_WORKFLOW_ID = "204971868"
      GH_REF             = "main"

      SSM_TOKEN_PARAM = "/gh/actions/token"
      TOKEN_SOURCE    = "ssm"

      S3_BUCKET = var.wait_site_bucket_name
      S3_PREFIX = var.wait_site_prefix
      REGION    = var.region
    }
  }

  lifecycle {
    ignore_changes = [environment]
  }
}
resource "aws_cloudwatch_log_group" "wake" {
  name              = "/aws/lambda/${aws_lambda_function.wake.function_name}"
  retention_in_days = var.lambda_log_retention_days
}

############################################
# Lambda — status (Python 3.12 / arm64)
############################################
resource "aws_lambda_function" "status" {
  function_name    = "${var.project_name}-status"
  role             = aws_iam_role.status_role.arn
  filename         = data.archive_file.status_zip.output_path
  source_code_hash = data.archive_file.status_zip.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"
  architectures = [
    "arm64",
  ]
  timeout                        = 10
  memory_size                    = 128
  reserved_concurrent_executions = 5
  publish                        = true

  environment {
    variables = {
      TARGET_URL      = "https://${var.domain_name}/"
      REQUEST_TIMEOUT = tostring(var.status_request_timeout)
      # CORS origin is enforced inside handler (set to app.multi-tier.space)
    }
  }

  depends_on = [
    data.archive_file.status_zip,
  ]
}

resource "aws_cloudwatch_log_group" "status" {
  name              = "/aws/lambda/${aws_lambda_function.status.function_name}"
  retention_in_days = var.lambda_log_retention_days
}
