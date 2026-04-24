# Create S3 bucket in Prod
resource "aws_s3_bucket" "s3_bucket_1" {
  provider = aws.prod  
  bucket = "chukas-unique-bucket-7" # Must be globally unique

  tags = {
    Name        = "My bucket"
    Environment = "Prod"
  }
}

# Create a Service Control Policy (SCP) that denies all S3 actions in the PROD account
resource "aws_organizations_policy" "deny_s3_prod" {
  name        = "DenyS3Access"
  description = "Allows everything EXCEPT S3 bucket and object actions"
  type        = "SERVICE_CONTROL_POLICY"

  # The JSON policy content
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Deny"
        Action   = "s3:*"
        Resource = "*"
      }
    ]
  })
}

# Attach the SCP to the PROD OU to enforce it on all accounts within that OU
resource "aws_organizations_policy_attachment" "prod_attach" {
  policy_id = aws_organizations_policy.deny_s3_prod.id
  target_id = data.terraform_remote_state.foundation.outputs.prod_ou_id
}