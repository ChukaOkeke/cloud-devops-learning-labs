# Configure the Terraform AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Providers for Master and PROD accounts
# Master account provider
provider "aws" {
  region = "us-east-1"
  profile = "iamadmin-general" # Specify the AWS CLI profile for the general account (optional)
  # Access keys can be set in the environment variables or through the AWS CLI configuration
}

# PROD account provider (Points to PROD)
provider "aws" {
  alias  = "prod_account"
  region = "us-east-1"
  profile = "iamadmin-prod" # Specify the AWS CLI profile for the PROD account (optional)
#   assume_role {
#     # This is the role you manually use or create to "get into" PROD
#     role_arn = "arn:aws:iam::PROD_ACCOUNT_ID:role/OrganizationAccountAccessRole"
#   }
}

# Create data source to get the current caller identity for the Master account (General)
data "aws_caller_identity" "current" {}

# Create an AWS Organization with ALL features enabled and allow access to IAM and CloudTrail services for the organization
resource "aws_organizations_organization" "org" {
  feature_set = "ALL"
  aws_service_access_principals = [
    "iam.amazonaws.com",
    "cloudtrail.amazonaws.com"
  ]
}

# Track the PROD account manually invited into the organization in the Terraform state (run terraform import aws_organizations_account.prod 697790871179 after manually inviting the account)
resource "aws_organizations_account" "prod" {
  name  = "Production"
  email = "liamrosie@hotmail.com"
}

# Create Role in PROD account to allow Master account to assume it and role-switch
resource "aws_iam_role" "cross_account_role" {
  provider = aws.prod_account  # Specify the provider for the PROD account
  name     = "OrganizationAccountAccessRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = "arn:aws:iam::045511192978:root" } # Replace with the actual AWS Account ID of the Master account
    }]
  })
}

# Attach the AdministratorAccess policy to the cross-account role in the PROD account
resource "aws_iam_role_policy_attachment" "admin_access" {
  provider = aws.prod_account  # Specify the provider for the PROD account
  role       = aws_iam_role.cross_account_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create a new Development member account within the Organization
resource "aws_organizations_account" "dev" {
  name      = "Development"
  email     = "chukybombo@yahoo.com"
  role_name = "OrganizationAccountAccessRole" # Created automatically by AWS
}

# Configure the S3 backend for remote state management
terraform {
  backend "s3" {
    bucket         = "my-cantrill-labs-terraform-state" # The unique bucket name
    key            = "foundation/terraform.tfstate" # The path within the bucket where the state file will be stored
    region         = "us-east-1"  # Variables can't be used, must be hardcoded
    dynamodb_table = "terraform-state-locking"
    encrypt        = true
    profile = "iamadmin-general" 
  }
}

# Display the account IDs of the Master, PROD, and DEV accounts as output variables for easy reference
# The Management Account ID (General)
output "management_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "The ID of the General/Management account"
}

# The Invited Account (Prod)
output "prod_account_id" {
  value = aws_organizations_account.prod.id
}

# The Created Account (Dev)
output "dev_account_id" {
  value = aws_organizations_account.dev.id
}