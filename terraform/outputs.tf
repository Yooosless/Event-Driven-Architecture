output "ec2_public_ip" {
  description = "The public IPv4 address assigned to your compute instance"
  value       = aws_instance.afridi_basic.public_ip
}

output "ecr_repo_url" {
  description = "The full registry URL of your private ECR repository"
  value       = aws_ecr_repository.rust_app.repository_url
}

output "api_gateway_url" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}


output "s3_bucket_name" {
  value = aws_s3_bucket.telemetry_bucket.id
}