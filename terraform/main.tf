terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"

}

# Provision an EC2 instance
resource "aws_instance" "my-first-ec2" {
  ami           = "ami-0b6c6ebed2801a5cb"
  instance_type = "t3.micro"

}

# # General syntax for provisioning a resource
# resource "provider_resource" "name" {
#   # Resource configuration goes here
#   key = "value"
#   key2 = "value2"
# }