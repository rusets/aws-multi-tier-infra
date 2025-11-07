############################################
# Existing HTTP API — by exact ID
############################################
data "aws_apigatewayv2_api" "wait_api" {
  api_id = var.existing_http_api_id
}

############################################
# Integration — wake (POST /wake)
############################################
resource "aws_apigatewayv2_integration" "wake_integration" {
  api_id                 = data.aws_apigatewayv2_api.wait_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.wake.arn
  payload_format_version = "2.0"
}

############################################
# Route — POST /wake
############################################
resource "aws_apigatewayv2_route" "wake_route" {
  api_id    = data.aws_apigatewayv2_api.wait_api.id
  route_key = "POST /wake"
  target    = "integrations/${aws_apigatewayv2_integration.wake_integration.id}"
}

############################################
# Permission — allow API to invoke wake
############################################
resource "aws_lambda_permission" "wake_allow_api" {
  statement_id  = "AllowInvokeByHttpApiWake"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wake.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${data.aws_apigatewayv2_api.wait_api.execution_arn}/*/*/wake"
}

############################################
# Integration — status (GET /status)
############################################
resource "aws_apigatewayv2_integration" "status_integration" {
  api_id                 = data.aws_apigatewayv2_api.wait_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.status.arn
  payload_format_version = "2.0"
}

############################################
# Route — GET /status
############################################
resource "aws_apigatewayv2_route" "status_route" {
  api_id    = data.aws_apigatewayv2_api.wait_api.id
  route_key = "GET /status"
  target    = "integrations/${aws_apigatewayv2_integration.status_integration.id}"
}

############################################
# Permission — allow API to invoke status
############################################
resource "aws_lambda_permission" "status_allow_api" {
  statement_id  = "AllowInvokeByHttpApiStatus"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.status.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${data.aws_apigatewayv2_api.wait_api.execution_arn}/*/*/status"
}

