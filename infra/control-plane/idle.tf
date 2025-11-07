############################################
# Artifacts — heartbeat.zip, idle_reaper.zip
############################################
data "archive_file" "heartbeat_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/heartbeat"
  output_path = "${path.module}/dist/heartbeat.zip"

  depends_on = [null_resource.ensure_dist]
}

data "archive_file" "idle_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/idle_reaper"
  output_path = "${path.module}/dist/idle_reaper.zip"

  depends_on = [null_resource.ensure_dist]
}

############################################
# IAM — roles for heartbeat & idle-reaper
############################################
resource "aws_iam_role" "heartbeat_role" {
  name               = "${var.project_name}-heartbeat-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "idle_role" {
  name               = "${var.project_name}-idle-reaper-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "heartbeat_logs" {
  role       = aws_iam_role.heartbeat_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "idle_logs" {
  role       = aws_iam_role.idle_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

############################################
# Policies — heartbeat S3 Put + SSM PutParameter
############################################
data "aws_iam_policy_document" "heartbeat_s3_ssm" {
  statement {
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "arn:aws:s3:::${var.wait_site_bucket_name}/${var.wait_site_prefix}*",
      "arn:aws:s3:::${var.wait_site_bucket_name}/status.json"
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["ssm:PutParameter"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "heartbeat_s3_ssm" {
  name   = "${var.project_name}-heartbeat-s3-ssm"
  policy = data.aws_iam_policy_document.heartbeat_s3_ssm.json
}

resource "aws_iam_role_policy_attachment" "heartbeat_s3_ssm_attach" {
  role       = aws_iam_role.heartbeat_role.name
  policy_arn = aws_iam_policy.heartbeat_s3_ssm.arn
}

############################################
# Policies — idle-reaper SSM Get + Secret (GitHub PAT)
############################################
data "aws_secretsmanager_secret" "gh_pat_for_idle" {
  name = var.gh_secret_name
}

data "aws_iam_policy_document" "idle_ssm_secret" {
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [data.aws_secretsmanager_secret.gh_pat_for_idle.arn]
  }
}

resource "aws_iam_policy" "idle_ssm_secret" {
  name   = "${var.project_name}-idle-ssm-gh"
  policy = data.aws_iam_policy_document.idle_ssm_secret.json
}

resource "aws_iam_role_policy_attachment" "idle_ssm_secret_attach" {
  role       = aws_iam_role.idle_role.name
  policy_arn = aws_iam_policy.idle_ssm_secret.arn
}

############################################
# Lambda — heartbeat (writes status.json + updates SSM when ready)
############################################
resource "aws_lambda_function" "heartbeat" {
  function_name                  = "${var.project_name}-heartbeat"
  role                           = aws_iam_role.heartbeat_role.arn
  filename                       = data.archive_file.heartbeat_zip.output_path
  source_code_hash               = data.archive_file.heartbeat_zip.output_base64sha256
  handler                        = "handler.handler"
  runtime                        = "python3.12"
  architectures                  = ["arm64"]
  timeout                        = 10
  memory_size                    = 128
  reserved_concurrent_executions = 5
  publish                        = true

  environment {
    variables = {
      S3_BUCKET       = var.wait_site_bucket_name
      S3_PREFIX       = var.wait_site_prefix
      TARGET_URL      = "https://${var.domain_name}/"
      REQUEST_TIMEOUT = tostring(var.status_request_timeout)
      HEARTBEAT_PARAM = var.heartbeat_param
    }
  }

  depends_on = [data.archive_file.heartbeat_zip]
}

resource "aws_cloudwatch_log_group" "heartbeat" {
  name              = "/aws/lambda/${aws_lambda_function.heartbeat.function_name}"
  retention_in_days = var.lambda_log_retention_days
}

############################################
# Lambda — idle-reaper (triggers destroy after idle_minutes)
############################################
resource "aws_lambda_function" "idle_reaper" {
  function_name                  = "${var.project_name}-idle-reaper"
  role                           = aws_iam_role.idle_role.arn
  filename                       = data.archive_file.idle_zip.output_path
  source_code_hash               = data.archive_file.idle_zip.output_base64sha256
  handler                        = "handler.handler"
  runtime                        = "python3.12"
  architectures                  = ["arm64"]
  timeout                        = 15
  memory_size                    = 128
  reserved_concurrent_executions = 5
  publish                        = true

  environment {
    variables = {
      REGION          = var.region
      HEARTBEAT_PARAM = var.heartbeat_param
      IDLE_MINUTES    = tostring(var.idle_minutes)
      GH_OWNER        = var.gh_owner
      GH_REPO         = var.gh_repo
      GH_WORKFLOW     = var.gh_workflow
      GH_REF          = var.gh_ref
      GH_SECRET_NAME  = var.gh_secret_name
    }
  }

  depends_on = [data.archive_file.idle_zip]
}

resource "aws_cloudwatch_log_group" "idle_reaper" {
  name              = "/aws/lambda/${aws_lambda_function.idle_reaper.function_name}"
  retention_in_days = var.lambda_log_retention_days
}

############################################
# EventBridge — schedules (every minute)
############################################
resource "aws_cloudwatch_event_rule" "heartbeat_schedule" {
  name                = "${var.project_name}-heartbeat-every-1m"
  description         = "Run heartbeat every minute"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "heartbeat_target" {
  rule      = aws_cloudwatch_event_rule.heartbeat_schedule.name
  target_id = "${var.project_name}-hb-target"
  arn       = aws_lambda_function.heartbeat.arn
}

resource "aws_lambda_permission" "allow_events_heartbeat" {
  statement_id  = "AllowEventsInvokeHB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.heartbeat.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.heartbeat_schedule.arn
}

resource "aws_cloudwatch_event_rule" "idle_reaper_schedule" {
  name                = "${var.project_name}-idle-reaper-every-1m"
  description         = "Run idle reaper every minute"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "idle_reaper_target" {
  rule      = aws_cloudwatch_event_rule.idle_reaper_schedule.name
  target_id = "${var.project_name}-idle-target"
  arn       = aws_lambda_function.idle_reaper.arn
}

resource "aws_lambda_permission" "allow_events_idle" {
  statement_id  = "AllowEventsInvokeIdle"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.idle_reaper.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.idle_reaper_schedule.arn
}
