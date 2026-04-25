# Create an S3 bucket for hosting the static website
resource "aws_s3_bucket" "website" {
  bucket = "asgardcuisines.io"
}

# Enable Object versioning for better data protection (optional but recommended)
resource "aws_s3_bucket_versioning" "website_versioning" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Automatically delete old versions after 30 days (optional lifecycle rule)
resource "aws_s3_bucket_lifecycle_configuration" "website_lifecycle" {
  bucket = aws_s3_bucket.website.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Disable "Block All Public Access"
resource "aws_s3_bucket_public_access_block" "website_access" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Enable Static Website Hosting
resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Upload index.html
resource "aws_s3_object" "index" {
  depends_on = [aws_s3_bucket_versioning.website_versioning] # Ensure versioning is enabled before uploading
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  source       = "./website_files/index.html" # Path to your local file
  content_type = "text/html"
}

# Upload error.html
resource "aws_s3_object" "error" {
  depends_on = [aws_s3_bucket_versioning.website_versioning] # Ensure versioning is enabled before uploading
  bucket       = aws_s3_bucket.website.id
  key          = "error.html"
  source       = "./website_files/error.html" # Path to your local file
  content_type = "text/html"
}

# Upload an entire 'assets' folder
resource "aws_s3_object" "assets" {
  depends_on = [aws_s3_bucket_versioning.website_versioning] # Ensure versioning is enabled before uploading
  for_each = fileset("./website_files/assets/", "**")

  bucket = aws_s3_bucket.website.id
  key    = "assets/${each.value}"
  source = "./website_files/assets/${each.value}"
  # Terraform doesn't auto-detect content types; 
  # for a lab, this is fine, but in prod you'd use a map.
}

# Create a bucket policy to allow public read access to the website content
resource "aws_s3_bucket_policy" "allow_public_access" {
  # IMPORTANT: This depends on the public access block being disabled first
  depends_on = [aws_s3_bucket_public_access_block.website_access]
  bucket     = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
      },
    ]
  })
}

# Display the website endpoint as an output
output "website_endpoint" {
  value = aws_s3_bucket_website_configuration.website_config.website_endpoint
}