# 1. Package the Node.js folder into a ZIP archive cleanly
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-helper" # Tells Terraform to read your lambda/ folder
  output_path = "${path.module}/lambda_function.zip"
}

# --- Everything else below this line in lambda.tf stays exactly the same ---
resource "aws_lambda_function" "router" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "message-middleware-router"
  role             = "arn:aws:iam::589118303122:role/kpi-interns-dev-sso-inboundRole"  
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  reserved_concurrent_executions = var.sleep_mode ? 0 : -1

  environment {
    variables = {
      EC2_PUBLIC_IP    = aws_instance.afridi_basic.public_ip
      ECS_CLUSTER_NAME = aws_ecs_cluster.app_cluster.name
      ECS_SERVICE_NAME = aws_ecs_service.rust_ecs_service.name
    }
  }
}

# 3. Create a modern, high-performance HTTP API Gateway
resource "aws_apigatewayv2_api" "http_api" {
  name          = "message-router-gateway"
  protocol_type = "HTTP"
}

# 4. Connect the API Gateway directly to your Lambda Function
resource "aws_apigatewayv2_integration" "lambda_int" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.router.arn
}

# 5. Create a default stage ($default) so you don't need prefixes in the URL
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
  
  default_route_settings {
    throttling_burst_limit = var.sleep_mode ? 0 : 100
    throttling_rate_limit  = var.sleep_mode ? 0 : 50
  }
}

# Create a catch-all route that forwards EVERYTHING to your Lambda function
resource "aws_apigatewayv2_route" "catch_all" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /{proxy+}" # This catches any method (POST/GET) and any path
  target    = "integrations/${aws_apigatewayv2_integration.lambda_int.id}"
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.router.function_name
  principal     = "apigateway.amazonaws.com"
  
  # Changed trailing format to allow route proxying execution
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}