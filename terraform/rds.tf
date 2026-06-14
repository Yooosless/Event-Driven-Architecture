resource "aws_security_group" "rds_sg" {
  name        = "afridi-shared-rds-sg"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [aws_security_group.allow_ssh.id] 
    }
    
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "afridi-rds-subnet-group"
  
  subnet_ids = data.aws_subnets.public.ids

  tags = {
    Name = "Shared RDS Subnet Group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier             = "afridi-shared-message-db"
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  db_name                = "messaging_db"
  username               = "postgres_user"
  password               = "SuperSecurePassword123"
  skip_final_snapshot    = true
  publicly_accessible    = true 
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
}

output "rds_endpoint" {
  value       = aws_db_instance.postgres.endpoint
  description = "The database network connection string"
}