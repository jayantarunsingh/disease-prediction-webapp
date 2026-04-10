// This file defines the variables we use in main.tf

variable "aws_region" {
  description = "The AWS region to create resources in."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "The EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "The name of your *existing* key pair in the AWS Console."
  type        = string
  default     = "your-key" // CHANGE THIS if your key in AWS has a different name
}

variable "key_path" {
  description = "The *local* file path to your .pem key."
  type        = string
  default     = "./your-key.pem" // This should match your .pem file
}
