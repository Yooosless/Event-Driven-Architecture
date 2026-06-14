

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

resource "aws_security_group" "allow_ssh" {
  name        = var.security_group_name
  description = "Allow inbound SSH and application tier web traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow inbound SSH administration"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow unrestricted outbound execution communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow public HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow public HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_iam_role" "ec2_telemetry_role" {
  name = "afridi-ec2-telemetry-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

resource "aws_instance" "afridi_basic" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ec2_key.key_name
  vpc_security_group_ids      = [aws_security_group.allow_ssh.id]
  associate_public_ip_address = true
  subnet_id                   = data.aws_subnets.public.ids[0]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  user_data = <<EOF
#!/bin/bash -xe
exec > /var/log/user-data.log 2>&1

# Update OS resources and register the containerization toolchain
yum update -y
amazon-linux-extras install docker -y
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# --- AUTOMATED AWS CLI V2 INSTALLATION ---
echo "Installing AWS CLI Version 2..."
cd /tmp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Clean up installation files
rm -rf awscliv2.zip aws/
EOF

  tags = {
    Name = "afridi-basic-ec2"
  }
}

resource "aws_eip" "worker_static_ip" {
  domain = "vpc"
  
  tags = {
    Name = "afridi-ec2-static-ip"
  }
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.afridi_basic.id
  allocation_id = aws_eip.worker_static_ip.id
}

resource "aws_ec2_instance_state" "afridi_basic_state" {
  instance_id = aws_instance.afridi_basic.id
  state       = var.sleep_mode ? "stopped" : "running"
}

