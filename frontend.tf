# Create an S3 Bucket
resource "aws_s3_bucket" "webapp" {
  bucket = "jsr-bucket"
}

resource "aws_s3_bucket_ownership_controls" "webapp" {
  bucket = aws_s3_bucket.webapp.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "webapp" {
  bucket = aws_s3_bucket.webapp.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "webapp" {
  depends_on = [
    aws_s3_bucket_ownership_controls.webapp,
    aws_s3_bucket_public_access_block.webapp
  ]
  bucket  = aws_s3_bucket.webapp.id
  acl     = "public-read"
}

# Configure S3 to host a static website
resource "aws_s3_bucket_website_configuration" "webapp" {
  bucket = "jsr-bucket"
  index_document { 
    suffix = "index.html"
  }
}

# Configure S3 CORS configuration
resource "aws_s3_bucket_cors_configuration" "webapp" {
  bucket = aws_s3_bucket.webapp.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["http://jsr-bucket.s3-website-us-west-2.amazonaws.com/","https://d2oyyk7ksa45fl.cloudfront.net","https://cyb2ykoogvkjmtwhbbtjrb2s4e0ynkbc.lambda-url.us-west-2.on.aws/"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }

  cors_rule {
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
  }
}

# CloudFront
locals {
	s3_origin_id = "myS3Origin"
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "webapp_distribution" {
  # Define the distribution settings
  # Configure S3 as the origin
  # Add the Lambda@Edge function to handle requests
  # Configure WAF using aws_waf_web_acl
	origin {
		domain_name = "${aws_s3_bucket.webapp.bucket_regional_domain_name}"
		origin_id		= local.s3_origin_id
	}
	enabled			= true
	default_root_object	= "index.html"
	price_class = "PriceClass_100"
  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
		viewer_protocol_policy = "allow-all"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
  	}
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
#	web_acl_id = aws_wafv2_web_acl.webapp.arn
}
