// This file defines all the AWS resources Terraform will create.

// 1. Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

// 2. Find the latest Ubuntu 22.04 (Jammy) AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] // Canonical's AWS owner ID
}

// 3. Define the Security Group (Firewall)
resource "aws_security_group" "app_sg" {
  name        = "app-sg-terraform"
  description = "Allow SSH and App access"

  // Allow SSH (Port 22) from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Allow our Flask App (Port 5000) from anywhere
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Allow all outbound traffic (for apt update, pip install)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "App-SG (Terraform)"
  }
}

// 4. Define the EC2 Instance
resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name // The key you imported to AWS
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  // Wait for the instance to be ready before proceeding
  provisioner "remote-exec" {
    inline = ["echo 'Instance is ready for Ansible'"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.key_path)
      host        = self.public_ip
    }
  }

  tags = {
    Name = "Disease-Prediction-Server (Terraform)"
  }
}

// 5. (THE MAGIC) Automatically generate an Ansible inventory file
resource "local_file" "ansible_inventory" {
  filename = "terraform_inventory.ini" // This is the new inventory file
  content = templatefile("inventory.tftpl", {
    host_ip  = aws_instance.app_server.public_ip,
    key_path = var.key_path
  })
}
