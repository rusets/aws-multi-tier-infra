############################################
# Outputs — Lambda names
############################################
output "wake_lambda_name" {
  description = "Wake lambda name"
  value       = aws_lambda_function.wake.function_name
}

output "status_lambda_name" {
  description = "Status lambda name"
  value       = aws_lambda_function.status.function_name
}

output "heartbeat_lambda_name" {
  description = "Heartbeat lambda name"
  value       = aws_lambda_function.heartbeat.function_name
}

output "idle_reaper_lambda_name" {
  description = "Idle reaper lambda name"
  value       = aws_lambda_function.idle_reaper.function_name
}

output "wake_endpoint" {
  description = "HTTP API URL to trigger apply"
  value       = "${data.aws_apigatewayv2_api.wait_api.api_endpoint}/${var.api_stage_name}/wake"
}

output "status_endpoint" {
  description = "HTTP API URL to poll readiness"
  value       = "${data.aws_apigatewayv2_api.wait_api.api_endpoint}/${var.api_stage_name}/status"
}
