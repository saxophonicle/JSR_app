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


