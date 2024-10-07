terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region     = "sa-east-1"
}

# API Gateway
data "aws_iam_policy_document" "gateway-assume-role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["apigateway.amazonaws.com"]
      type = "Service"
    }
  }
}

resource "aws_iam_role" "gateway-iam-role" {
  name               = "gateway-iam-role"
  assume_role_policy = data.aws_iam_policy_document.gateway-assume-role.json
}

resource "aws_iam_role_policy_attachment" "gateway-sqs-iam-policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
  role       = aws_iam_role.gateway-iam-role.name
}

resource "aws_api_gateway_rest_api" "email-api" {
  name = "email-api"
}

resource "aws_api_gateway_resource" "email_gateway_resource" {
  rest_api_id = aws_api_gateway_rest_api.email-api.id
  parent_id   = aws_api_gateway_rest_api.email-api.root_resource_id
  path_part   = "email"
}

resource "aws_api_gateway_method" "email-gateway-method" {
  rest_api_id      = aws_api_gateway_rest_api.email-api.id
  resource_id      = aws_api_gateway_resource.email_gateway_resource.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = false
}

resource "aws_api_gateway_integration" "email-sqs-gateway-integration" {
  rest_api_id             = aws_api_gateway_rest_api.email-api.id
  resource_id             = aws_api_gateway_resource.email_gateway_resource.id
  http_method             = "POST"
  type                    = "AWS"
  integration_http_method = "POST"
  passthrough_behavior    = "NEVER"
  credentials             = aws_iam_role.gateway-iam-role.arn
  uri                     = "arn:aws:apigateway:sa-east-1:sqs:path/${aws_sqs_queue.email_sqs_queue.name}"

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$input.body"
  }
}

resource "aws_api_gateway_method_response" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.email-api.id
  resource_id = aws_api_gateway_resource.email_gateway_resource.id
  http_method = aws_api_gateway_method.email-gateway-method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.email-api.id
  resource_id = aws_api_gateway_resource.email_gateway_resource.id
  http_method = aws_api_gateway_method.email-gateway-method.http_method
  status_code = aws_api_gateway_method_response.proxy.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [
    aws_api_gateway_method.email-gateway-method,
    aws_api_gateway_integration.email-sqs-gateway-integration
  ]
}

# SES (Simple Email Service)

resource "aws_ses_configuration_set" "ses_configuration_set" {
  name                       = "ses_configuration_set"
  reputation_metrics_enabled = false
}

# SQS (Simple Queue Service)

resource "aws_sqs_queue" "email_sqs_queue" {
  name          = "email-sqs-queue"
  delay_seconds = 0
}

data "aws_iam_policy_document" "email_sqs_policy" {
  statement {
    sid = "email-sqs-queue-policy"

    principals {
      type = "AWS"
      identifiers = ["*"]
    }

    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage"
    ]
    resources = [
      aws_sqs_queue.email_sqs_queue.arn
    ]
  }
}

resource "aws_sqs_queue_policy" "sh_sqs_policy" {
  queue_url = aws_sqs_queue.email_sqs_queue.id
  policy    = data.aws_iam_policy_document.email_sqs_policy.json
}

# Lambda Function - SES handler

data "aws_iam_policy_document" "ses-assume-role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["*"]
      type = "AWS"
    }
  }
}

resource "aws_iam_role" "ses-lambda-iam-role" {
  name               = "iam-for-ses-lambda"
  assume_role_policy = data.aws_iam_policy_document.ses-assume-role.json
}

resource "aws_iam_role_policy_attachment" "ses-lambda-basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.ses-lambda-iam-role.name
}

resource "aws_iam_role_policy_attachment" "ses-lambda-ses" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSESFullAccess"
  role       = aws_iam_role.ses-lambda-iam-role.name
}

resource "aws_iam_role_policy_attachment" "ses-lambda-sqs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
  role       = aws_iam_role.ses-lambda-iam-role.name
}

data "archive_file" "ses-lambda" {
  source_dir  = "ses-lambda"
  output_path = "ses-lambda.zip"
  type        = "zip"
}

resource "aws_lambda_function" "ses-lambda-function" {
  function_name    = "ses-lambda-function"
  filename         = "ses-lambda.zip"
  role             = aws_iam_role.ses-lambda-iam-role.arn
  source_code_hash = data.archive_file.ses-lambda.output_base64sha256
  runtime          = "nodejs18.x"
  handler          = "index.handler"
}

resource "aws_cloudwatch_log_group" "ses-lambda-cloudwatch-log-group" {
  name              = "/aws/lambda/ses-lambda-function"
  retention_in_days = 14
}

# Linking SQS and Lambda

resource "aws_lambda_event_source_mapping" "event_source_mapping" {
  event_source_arn = aws_sqs_queue.email_sqs_queue.arn
  function_name    = aws_lambda_function.ses-lambda-function.function_name
  batch_size       = 1
  enabled          = true
}
