terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.22.0"
    }
  }
}

provider "aws" {
  profile = "default"  
  region  = "us-west-2"
	default_tags {
		tags = {
			Name = "JSR"
		}
	}
}

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


# Create a DynamoDB table
resource "aws_dynamodb_table" "counter" {
  name           	= "CounterTable"
  read_capacity  	= 1
  write_capacity 	= 1
	hash_key				= "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# Lambda IAM Permissions
data "aws_iam_policy_document" "lambda_execution_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "lambda_dynamodb_role" {
	statement {
		actions = [
			"dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:Scan",
      "dynamodb:UpdateItem"
		]
		resources = [
			aws_dynamodb_table.counter.arn
		]
	}
}


# Create an IAM Role for the Lambda function
resource "aws_iam_role" "iam_lambda_role" {
  name = "lambda_execution_role"
  # Define policies here for DynamoDB access
  assume_role_policy = data.aws_iam_policy_document.lambda_execution_role.json
}

# Create the Lambda Function
resource "aws_lambda_function" "webapp" {
  function_name = "webapp_function"
	filename			= "jsr_lambda_webapp.zip"
  handler      	= "index.handler"
  runtime      	= "nodejs18.x"
	architectures = [ "x86_64" ]
  role        	= aws_iam_role.iam_lambda_role.arn
  # Add the S3 and DynamoDB permissions policies here
  # Define the code for your Lambda function
}


# API Gateway
resource "aws_lambda_permission" "allow_api" {
	statement_id	= "AllowAPIgatewayInvokation"
	action				= "lambda:InvokeFunction"
	function_name = aws_lambda_function.webapp.arn
	principal			= "apigateway.amazonaws.com"
}

resource "aws_apigatewayv2_api" "webapp" {
  name					= "jsr-webapp"
	protocol_type = "HTTP"
	cors_configuration	{
		allow_credentials = false
		allow_headers 		= [ "content-type" ]
		allow_methods			= [ "DELETE", "GET", "OPTIONS", "PUT" ]
		allow_origins			= [ "http://jsr-bucket.s3-website-us-west-2.amazonaws.com",
													"https://d2oyyk7ksa45fl.cloudfront.net" ]
	}
}

resource "aws_apigatewayv2_stage" "webapp" {
	api_id = aws_apigatewayv2_api.webapp.id
	name = "$default"
	auto_deploy = true
}

resource "aws_apigatewayv2_integration" "webapp" {
	api_id	=	aws_apigatewayv2_api.webapp.id
	integration_type	= "AWS_PROXY"
	connection_type 	= "INTERNET"
	payload_format_version = "2.0"
	integration_uri		= aws_lambda_function.webapp.invoke_arn
}
resource "aws_apigatewayv2_route" "options" {
	api_id		= aws_apigatewayv2_api.webapp.id
	route_key	= "OPTIONS /"
	target 		= "integrations/${aws_apigatewayv2_integration.webapp.id}"
}
resource "aws_apigatewayv2_route" "getItemsId" {
	api_id		= aws_apigatewayv2_api.webapp.id
	route_key	= "GET /items/{id}"
	target 		= "integrations/${aws_apigatewayv2_integration.webapp.id}"
}
resource "aws_apigatewayv2_route" "putItemsId" {
	api_id		= aws_apigatewayv2_api.webapp.id
	route_key	= "PUT /items"
	target 		= "integrations/${aws_apigatewayv2_integration.webapp.id}"
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
}


