variable "aws_region" {
  type        = string
  description = "The target AWS Region for all resources"
  default     = "us-east-1"
}

variable "instance_type" {
  type        = string
  description = "The EC2 instance size compute capacity"
  default     = "t2.micro"
}

variable "ami_id" {
  type        = string
  description = "Amazon Linux 2 AMI ID matching the selected region"
  default     = "ami-0c02fb55956c7d316"
}

variable "key_name" {
  type        = string
  description = "Name tag for the generated AWS key pair identity"
  default     = "afridi-basic-key"
}

variable "security_group_name" {
  type        = string
  description = "Name tag for the infrastructure access control firewall"
  default     = "afridi-allow-ssh"
}

variable "ecr_repository_name" {
  type        = string
  description = "The name of your private Elastic Container Registry"
  default     = "rust-hello-world"
}

variable "sleep_mode" {
  type        = bool
  default     = false
  description = "Set to true to gracefully pause running worker compute frames and drop costs"
}