resource "aws_s3_bucket" "telemetry_bucket" {
  bucket        = "afridi-poc-bucket" 
  force_destroy = true 

  tags = {
    Environment = "Dev-POC"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "block_public" {
  bucket = aws_s3_bucket.telemetry_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}



resource "aws_iam_role_policy" "ec2_s3_policy" {
  name = "EC2InstanceS3TelemetryAccess"
  role = aws_iam_role.ec2_telemetry_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        # Points to the bucket created by your other Terraform file
        Resource = "${aws_s3_bucket.telemetry_bucket.arn}/*"
      }
    ]
  })
}

#  Create the Instance Profile Wrapper that EC2 requires
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "afridi-ec2-telemetry-profile"
  role = aws_iam_role.ec2_telemetry_role.name
}