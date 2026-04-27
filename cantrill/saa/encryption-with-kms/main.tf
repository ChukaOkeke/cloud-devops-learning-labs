# Get the current Account ID and the iamadmin user details
data "aws_caller_identity" "current" {}

data "aws_iam_user" "admin_user" {
  user_name = "iamadmin" 
}

# Create the KMS Key
resource "aws_kms_key" "asgard_key" {
  description             = "Symmetric KMS key for Asgard project encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true # Best practice for security compliance
  multi_region            = false # Ensures it is a single-region key

  # Define the Key Policy
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "asgard-kms-policy"
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
      },
      {
        # Grants your specific user administrative rights
        Sid    = "Allow Admin for iamadmin"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_iam_user.admin_user.arn
        }
        Action = [
          # Administrative Actions
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ]
        Resource = "*"
      },
      {
        # Grants your specific user usage rights
        Sid    = "Allow Use for iamadmin"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_iam_user.admin_user.arn
        }
        Action = [
          # Usage Actions
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# Create the Alias
resource "aws_kms_alias" "asgard_alias" {
  name          = "alias/asgardsunic"
  target_key_id = aws_kms_key.asgard_key.key_id
}