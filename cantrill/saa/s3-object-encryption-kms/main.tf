# Create the S3 Bucket
resource "aws_s3_bucket" "food_pics" {
  bucket        = "foodpics99999"
  force_destroy = true
}

# Get the current Account ID and the iamadmin user details
data "aws_caller_identity" "current" {}

data "aws_iam_user" "admin_user" {
  user_name = "iamadmin" 
}

# Create the KMS Key
resource "aws_kms_key" "food_pics_key" {
  description             = "Symmetric KMS key for food pics object encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true # Best practice for security compliance
  multi_region            = false # Ensures it is a single-region key

  # Define the Key Policy
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "food-pics-kms-policy"
    Statement = [
      {
        # REQUIRED: Allows the Account Root to manage the key. 
        # This prevents accidental "lockout" if the iamadmin user is deleted.
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
      # {
      #   # Grants your specific user administrative rights
      #   Sid    = "Allow Admin for iamadmin"
      #   Effect = "Allow"
      #   Principal = {
      #     AWS = data.aws_iam_user.admin_user.arn
      #   }
      #   Action = [
      #     # Administrative Actions
      #     "kms:Create*",
      #     "kms:Describe*",
      #     "kms:Enable*",
      #     "kms:List*",
      #     "kms:Put*",
      #     "kms:Update*",
      #     "kms:Revoke*",
      #     "kms:Disable*",
      #     "kms:Get*",
      #     "kms:Delete*",
      #     "kms:TagResource",
      #     "kms:UntagResource",
      #     "kms:ScheduleKeyDeletion",
      #     "kms:CancelKeyDeletion"
      #   ]
      #   Resource = "*"
      # },
      # {
      #   # Grants your specific user usage rights
      #   Sid    = "Allow Use for iamadmin"
      #   Effect = "Allow"
      #   Principal = {
      #     AWS = data.aws_iam_user.admin_user.arn
      #   }
      #   Action = [
      #     # Usage Actions
      #     "kms:Encrypt",
      #     "kms:Decrypt",
      #     "kms:ReEncrypt*",
      #     "kms:GenerateDataKey*",
      #     "kms:DescribeKey"
      #   ]
      #   Resource = "*"
      # }
    ]
  })
}

# Create the Alias
resource "aws_kms_alias" "food_pics_alias" {
  name          = "alias/foodpics"
  target_key_id = aws_kms_key.food_pics_key.key_id
}

# SSE-S3 Encryption (Managed by S3)
resource "aws_s3_object" "object_sse_s3" {
  bucket = aws_s3_bucket.food_pics.id
  key    = "sse-s3-dweez.jpg"
  source = "./assets/sse-s3-dweez.jpg" # Ensure this file exists locally
  
  server_side_encryption = "AES256"
}

# SSE-KMS with AWS Managed Key (alias/aws/s3)
resource "aws_s3_object" "object_aws_kms" {
  bucket = aws_s3_bucket.food_pics.id
  key    = "sse-kms-ginny.jpg"
  source = "./assets/sse-kms-ginny.jpg"
  
  server_side_encryption = "aws:kms"
  # Omission of kms_key_id defaults to the AWS-managed S3 key
  # kms_key_id             = "alias/aws/s3" 
}

# SSE-KMS with Customer Managed Key (alias/foodpics)
# Note: Changing this in an existing resource triggers a re-upload/update
resource "aws_s3_object" "object_cmk_kms" {
  bucket = aws_s3_bucket.food_pics.id
  key    = "sse-kms-ginny.jpg"
  source = "./assets/sse-kms-ginny.jpg"
  
  server_side_encryption = "aws:kms"
  # References the CMK created in the previous step
  kms_key_id             = aws_kms_alias.food_pics_alias.target_key_arn
}

# Inline Identity Policy to Deny KMS Access
resource "aws_iam_user_policy" "deny_kms_iamadmin" {
  name = "DenyKMSAccess"
  user = "iamadmin"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ExplicitDenyKMS"
        Effect   = "Deny"
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}
