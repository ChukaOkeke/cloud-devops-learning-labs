# Destination bucket for replication (created in us-west-1)
# Create an S3 bucket for hosting the static website
resource "aws_s3_bucket" "destination_bucket" {
  provider = aws.destination
  bucket = "destinationbucket555567"
  force_destroy = true # Automatically delete all objects (including versions) when destroying the bucket
}

# Enable Object versioning for better data protection (optional but recommended)
resource "aws_s3_bucket_versioning" "destination_versioning" {
  provider = aws.destination
  bucket = aws_s3_bucket.destination_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Automatically delete old versions of the object after 30 days (optional lifecycle rule)
resource "aws_s3_bucket_lifecycle_configuration" "destination_lifecycle" {
  provider = aws.destination
  bucket = aws_s3_bucket.destination_bucket.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Disable "Block All Public Access"
resource "aws_s3_bucket_public_access_block" "destination_access" {
  provider = aws.destination
  bucket = aws_s3_bucket.destination_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Enable Static Website Hosting
resource "aws_s3_bucket_website_configuration" "destination_website_config" {
  provider = aws.destination
  bucket = aws_s3_bucket.destination_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# Create a bucket policy to allow public read access to the website content on destination bucket
resource "aws_s3_bucket_policy" "allow_destination_public_access" {
  provider = aws.destination
  # IMPORTANT: This depends on the public access block being disabled first
  depends_on = [aws_s3_bucket_public_access_block.destination_access]
  bucket     = aws_s3_bucket.destination_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.destination_bucket.arn}/*"
      },
    ]
  })
}

# Display the website endpoint as an output
output "destination_website_endpoint" {
  value = aws_s3_bucket_website_configuration.destination_website_config.website_endpoint
}


# Source bucket for replication (created in us-east-1)
# Create an S3 bucket for hosting the static website
resource "aws_s3_bucket" "source_bucket" {
  provider = aws.source
  bucket = "sourcebucket555567"
  force_destroy = true # Automatically delete all objects (including versions) when destroying the bucket
}

# Enable Object versioning for better data protection (optional but recommended)
resource "aws_s3_bucket_versioning" "source_versioning" {
  provider = aws.source
  bucket = aws_s3_bucket.source_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Automatically delete old versions of the object after 30 days (optional lifecycle rule)
resource "aws_s3_bucket_lifecycle_configuration" "source_lifecycle" {
  provider = aws.source
  bucket = aws_s3_bucket.source_bucket.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Disable "Block All Public Access"
resource "aws_s3_bucket_public_access_block" "source_access" {
  provider = aws.source
  bucket = aws_s3_bucket.source_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Enable Static Website Hosting
resource "aws_s3_bucket_website_configuration" "source_website_config" {
  provider = aws.source
  bucket = aws_s3_bucket.source_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# Create a bucket policy to allow public read access to the website content on source bucket
resource "aws_s3_bucket_policy" "allow_source_public_access" {
  provider = aws.source
  # IMPORTANT: This depends on the public access block being disabled first
  depends_on = [aws_s3_bucket_public_access_block.source_access]
  bucket     = aws_s3_bucket.source_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.source_bucket.arn}/*"
      },
    ]
  })
}

# Display the website endpoint as an output
output "source_website_endpoint" {
  value = aws_s3_bucket_website_configuration.source_website_config.website_endpoint
}


# IAM Role for Replication
resource "aws_iam_role" "replication_role" {
  provider = aws.source
  name = "AsgardS3ReplicationRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
    }]
  })
}

# IAM Policy for Replication to read objects from the source bucket and write to destination bucket
resource "aws_iam_role_policy" "replication_policy" {
  provider = aws.source
  name = "AsgardS3ReplicationPolicy"
  role = aws_iam_role.replication_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [aws_s3_bucket.source_bucket.arn]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.source_bucket.arn}/*"]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.destination_bucket.arn}/*"]
      }
    ]
  })
}

# Replication Configuration
resource "aws_s3_bucket_replication_configuration" "replication" {
  provider = aws.source
  # Must have versioning enabled first
  depends_on = [aws_s3_bucket_versioning.source_versioning]

  role   = aws_iam_role.replication_role.arn
  bucket = aws_s3_bucket.source_bucket.id

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.destination_bucket.arn
      storage_class = "STANDARD"
    }
  }
}


# # Upload index.html to the source bucket
# resource "aws_s3_object" "index" {
#   provider = aws.source
#   depends_on = [aws_s3_bucket_versioning.source_versioning, aws_s3_bucket_replication_configuration.replication] # Ensure versioning and replication are enabled on source bucket before uploading
#   bucket       = aws_s3_bucket.source_bucket.id
#   key          = "index.html"
#   source       = "./website/index.html" # Path to your local file
#   content_type = "text/html"
# }

# # Upload image to the source bucket 
# resource "aws_s3_object" "image" {
#   provider = aws.source
#   depends_on = [aws_s3_bucket_versioning.source_versioning, aws_s3_bucket_replication_configuration.replication] # Ensure versioning and replication are enabled on source bucket before uploading
#   bucket       = aws_s3_bucket.source_bucket.id
#   key          = "aotm.jpg"
#   source       = "./website/aotm.jpg" # Path to your local file
#   content_type = "image/jpeg"
# }

# Upload another index.html to the source bucket
resource "aws_s3_object" "index" {
  provider = aws.source
  depends_on = [aws_s3_bucket_versioning.source_versioning, aws_s3_bucket_replication_configuration.replication] # Ensure versioning and replication are enabled on source bucket before uploading
  bucket       = aws_s3_bucket.source_bucket.id
  key          = "index.html"
  source       = "./website2/index.html" # Path to your local file
  content_type = "text/html"
}

# Upload image to the source bucket 
resource "aws_s3_object" "image" {
  provider = aws.source
  depends_on = [aws_s3_bucket_versioning.source_versioning, aws_s3_bucket_replication_configuration.replication] # Ensure versioning and replication are enabled on source bucket before uploading
  bucket       = aws_s3_bucket.source_bucket.id
  key          = "aotm.jpg"
  source       = "./website2/aotm.jpg" # Path to your local file
  content_type = "image/jpeg"
}