# S3 bucket and Policy
# Create an S3 bucket for CloudTrail logs (not real-time)
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "cloudtrail-asgard-5555"
  force_destroy = true
}

# Create a bucket policy to allow CloudTrail to write logs to the S3 bucket
resource "aws_s3_bucket_policy" "cloudtrail_policy" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

# CloudWatch Integration
# Create CloudWatch Log Group for real-time logging
resource "aws_cloudwatch_log_group" "asgard_trail_logs" {
  name = "/aws/cloudtrail/AsgardOrg"
  retention_in_days = 1 # Only keep 1 day of logs for labs
}

# The IAM Role for CloudTrail to assume - Trust Policy
resource "aws_iam_role" "cloudtrail_cloudwatch_role" {
  name = "AsgardCloudTrailToCloudWatchRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = { Service = "cloudtrail.amazonaws.com" }
    }]
  })
}

# The Policy allowing the role to write logs - Permissions Policy
resource "aws_iam_role_policy" "cloudtrail_cloudwatch_policy" {
  name = "AsgardCloudTrailCloudWatchPolicy"
  role = aws_iam_role.cloudtrail_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.asgard_trail_logs.arn}:*"
    }]
  })
}

# The Organizational Trail
resource "aws_cloudtrail" "asgard_org_trail" {
  depends_on = [aws_s3_bucket_policy.cloudtrail_policy]

  name                          = "AsgardOrg"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  enable_logging = false # Stop logging to save costs during the demo, but you can enable it to see real-time logs in CloudWatch
  include_global_service_events = true  # Include global events like IAM, STS, CloudTrail itself, etc.
  is_multi_region_trail         = true  # Create the trail in all regions to ensure comprehensive coverage across the organization
  is_organization_trail         = true # Automatically deploy this trail to every member account (Dev and Prod)
  
  # CloudWatch Logs configuration
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.asgard_trail_logs.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cloudwatch_role.arn

  # Management Events (Read/Write) are enabled by default, 
  # but we can explicitly define them:
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }
}