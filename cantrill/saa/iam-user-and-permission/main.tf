# Configure the Terraform AWS provider
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
  profile = "iamadmin" # Specify the AWS CLI profile to use for credentials (optional)
  # Access keys can be set in the environment variables or through the AWS CLI configuration
}

# Create 2 S3 Buckets
resource "aws_s3_bucket" "s3_bucket_1" {
  bucket = "chukas-unique-bucket-1" # Must be globally unique

  tags = {
    Name        = "My first bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket" "s3_bucket_2" {
  bucket = "chukas-unique-bucket-2" # Must be globally unique

  tags = {
    Name        = "My second bucket"
    Environment = "Dev"
  }
}

#Create an IAM User with permissions to change their own password
# 1. Create the IAM User
resource "aws_iam_user" "rosie" {
  name = "Rosie"
  path = "/system/"

  tags = {
    JobTitle = "Engineer"
  }
}

# 2. Create the Login Profile (For Console Access)
resource "aws_iam_user_login_profile" "rosie_login" {
  user                    = aws_iam_user.rosie.name # Reference the IAM User name from the created IAM User
  password_reset_required = true # Triggers change password prompt on first login on the console
}

# Display the auto-generated user password
output "initial_password" {
  value = aws_iam_user_login_profile.rosie_login.password
  sensitive = true
}

# 3. Attach the AWS Managed Policy for password changes
# This allows Rosie to actually perform the password change action
resource "aws_iam_user_policy_attachment" "password_change_attach" {
  user       = aws_iam_user.rosie.name
  policy_arn = "arn:aws:iam::aws:policy/IAMUserChangePassword" # AWS Managed Policy ARN for allowing users to change their own password
}

# # Create Inline Policy for the IAM User to have full access to S3
# resource "aws_iam_user_policy" "rosie_s3_full_access" {
#   name = "RosieS3FullAccess"
#   user = aws_iam_user.rosie.name

#   # Terraform's "jsonencode" function converts a Terraform expression result to valid JSON syntax
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect   = "Allow"
#         Action   = "s3:*"
#         Resource = "*"
#       },
#     ]
#   })
# }

# Create Managed Policy to deny and allow access to S3 
resource "aws_iam_policy" "rosie_s3_restricted" {
  name        = "RosieS3RestrictedPolicy"
  description = "Allows S3 access everywhere except two specific buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Statement 1: Allow all S3 actions globally
      {
        Sid      = "AllowAllS3"
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = "*"
      },
      # Statement 2: Explicitly Deny access to specific buckets
      {
        Sid      = "DenySpecificBuckets"
        Effect   = "Deny"
        Action   = "s3:*"
        Resource = [
          "arn:aws:s3:::chukas-unique-bucket-1",  # Deny access to the bucket itself
          "arn:aws:s3:::chukas-unique-bucket-1/*",  # Deny access to all objects within the bucket
          "arn:aws:s3:::chukas-unique-bucket-2",
          "arn:aws:s3:::chukas-unique-bucket-2/*"
        ]
      }
    ]
  })
}

# Attach the Managed Policy to User Rosie
resource "aws_iam_user_policy_attachment" "rosie_attach" {
  user       = aws_iam_user.rosie.name
  policy_arn = aws_iam_policy.rosie_s3_restricted.arn
}



#Verify and display AWS profiles and credentials
data "aws_caller_identity" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}