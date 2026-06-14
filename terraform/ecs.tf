data "aws_iam_role" "ecs_execution_role" {
  name = "ecsTaskExecutionRole"
}

# ==============================================================================
# --- AWS ECS (ELASTIC CONTAINER SERVICE) INFRASTRUCTURE ---
# ==============================================================================

resource "aws_ecs_cluster" "app_cluster" {
  name = "afridi-hybrid-cluster"
}

resource "aws_ecs_task_definition" "rust_ecs_task" {
  family                   = "rust-app-task"
  network_mode             = "awsvpc"     
  requires_compatibilities = ["FARGATE"] 
  cpu                      = "256"        # 0.25 vCPU
  memory                   = "512"        # 512MB RAM

  # 💡 References the data lookup dynamically
  execution_role_arn       = data.aws_iam_role.ecs_execution_role.arn
  task_role_arn            = data.aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "rust-app-ecs-container"
      image     = "${aws_ecr_repository.message_generator.repository_url}:latest"
      essential = true
      
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080 
        }
      ]      

      environment = [
        { 
          name  = "INFRA_SOURCE"
          value = "ECS" 
        },
        { 
          name  = "API_GATEWAY_URL"
          value = "${aws_apigatewayv2_api.http_api.api_endpoint}/send" 
        },
        {
          name  = "DATABASE_URL"
          value = "postgres://postgres_user:SuperSecurePassword123@${aws_db_instance.postgres.address}/messaging_db"
        },
        {
          name  = "AWS_REGION"
          value = "us-east-1"
        },
        {
          name  = "AWS_S3_BUCKET_NAME"
          value = "afridi-poc-bucket"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/rust-app-task"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/rust-app-task"
  retention_in_days = 7 
}

resource "aws_ecs_service" "rust_ecs_service" {
  name            = "afridi-rust-service"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.rust_ecs_task.arn
  desired_count   = var.sleep_mode ? 0 : 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.public.ids
    security_groups  = [aws_security_group.allow_ssh.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_ecr_repository.message_generator,
    aws_cloudwatch_log_group.ecs_log_group
  ] 
}

# ==============================================================================
# --- AWS IAM SECURITY POLICIES ---
# ==============================================================================

# 💡 This grants your ECS container task explicit permission to read/write to your S3 bucket
resource "aws_iam_role_policy" "ecs_s3_policy" {
  name = "afridi-ecs-s3-access-policy"
  role = data.aws_iam_role.ecs_execution_role.id # 💡 Fixed link to map to your data object ID

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::afridi-poc-bucket",
          "arn:aws:s3:::afridi-poc-bucket/*"
        ]
      }
    ]
  })
}