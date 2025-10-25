provider "aws" {
  region = "us-east-1"
}

terraform {

  required_version = ">= 1.0.0" # Specify a suitable version constraint

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Specify a version relevant to your deployment
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
  backend "s3" {
    bucket = "sctp-ce11-tfstate"
    key    = "saw-s3-tf-ci.tfstate" #Change this
    region = "us-east-1"
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = split("/", data.aws_caller_identity.current.arn)[1]
  # name_prefix = split("/", "${data.aws_caller_identity.current.arn}")[1] #if your name contains any invalid characters like “.”, hardcode this name_prefix value = <YOUR NAME>
  account_id = data.aws_caller_identity.current.account_id
  #account_id  = data.aws_caller_identity.current.account_id
}


resource "aws_s3_bucket" "s3_tf" {
  # Note: You successfully fixed the TFLint issue by using format()
  # checkov:skip=CKV_AWS_145: Not using KMS encryption for this challenge.
  # checkov:skip=CKV_AWS_18: Access logging is not required for this challenge.
  # checkov:skip=CKV2_AWS_62: Event notifications are not required for this challenge.
  # checkov:skip=CKV2_AWS_6: Public access blocks are not required for this challenge's purpose.
  # checkov:skip=CKV2_AWS_61: Lifecycle configuration is not required for this challenge.
  # checkov:skip=CKV_AWS_21: Versioning is not required for this challenge.
  # checkov:skip=CKV_AWS_144: Cross-region replication is not required for this challenge.
  bucket = format("%s-s3-tf-bkt-%s", local.name_prefix, local.account_id)
}

# DynamoDB Table for URL shortener
resource "aws_dynamodb_table" "url_table" {
  # checkov:skip=CKV_AWS_119: KMS encryption is not required for this challenge
  name         = "${local.name_prefix}-url-shortener"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "short_id"

  attribute {
    name = "short_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

# CloudWatch Log Group for WAF
resource "aws_cloudwatch_log_group" "waf_logs" {
  # checkov:skip=CKV_AWS_158: KMS encryption is not required for this challenge
  # checkov:skip=CKV_AWS_338: Long-term log retention is not required for this challenge
  name              = "aws-waf-logs-${local.name_prefix}-api-gw"
  retention_in_days = 7
}

# WAF Web ACL
resource "aws_wafv2_web_acl" "api_gw_waf" {
  # checkov:skip=CKV_AWS_192: Log4j protection is not required for this challenge
  name  = "${local.name_prefix}-api-gw-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-api-gw-waf"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "api" {
  # checkov:skip=CKV_AWS_237: Create before destroy is not required for this challenge
  name        = "${local.name_prefix}-url-shortener-api"
  description = "URL Shortener API"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.newurl.id,
      aws_api_gateway_method.post_method.id,
      aws_api_gateway_integration.post_integration.id,
      aws_api_gateway_resource.geturl.id,
      aws_api_gateway_method.get_method.id,
      aws_api_gateway_integration.get_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.post_integration,
    aws_api_gateway_integration.get_integration
  ]
}

# API Gateway Stage
resource "aws_api_gateway_stage" "api" {
  # checkov:skip=CKV_AWS_76: Access logging is not required for this challenge
  # checkov:skip=CKV_AWS_120: API Gateway caching is not required for this challenge
  # checkov:skip=CKV_AWS_73: X-Ray tracing is not required for this challenge
  # checkov:skip=CKV2_AWS_51: Client certificate authentication is not required for this challenge
  # checkov:skip=CKV2_AWS_29: WAF is already associated via separate resource
  # checkov:skip=CKV2_AWS_77: Log4j AMR protection is not required for this challenge
  # checkov:skip=CKV2_AWS_4: Detailed logging level is not required for this challenge
  deployment_id = aws_api_gateway_deployment.api.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}

# WAF Association with API Gateway
resource "aws_wafv2_web_acl_association" "api_gw" {
  resource_arn = aws_api_gateway_stage.api.arn
  web_acl_arn  = aws_wafv2_web_acl.api_gw_waf.arn
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.url_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda Function - Create URL
data "archive_file" "create_url_lambda" {
  type        = "zip"
  source_file = "${path.module}/create_url_lambda.py"
  output_path = "${path.module}/create_url_lambda.zip"
}

resource "aws_lambda_function" "create_url" {
  # checkov:skip=CKV_AWS_117: VPC configuration is not required for this challenge
  # checkov:skip=CKV_AWS_363: Python 3.9 is acceptable for this challenge
  # checkov:skip=CKV_AWS_116: Dead Letter Queue is not required for this challenge
  # checkov:skip=CKV_AWS_50: X-Ray tracing is not required for this challenge
  # checkov:skip=CKV_AWS_173: KMS encryption for environment variables is not required for this challenge
  # checkov:skip=CKV_AWS_115: Concurrent execution limit is not required for this challenge
  # checkov:skip=CKV_AWS_272: Code signing is not required for this challenge
  filename         = data.archive_file.create_url_lambda.output_path
  function_name    = "${local.name_prefix}-create-url"
  role             = aws_iam_role.lambda_role.arn
  handler          = "create_url_lambda.lambda_handler"
  source_code_hash = data.archive_file.create_url_lambda.output_base64sha256
  runtime          = "python3.9"
  timeout          = 30

  environment {
    variables = {
      APP_URL    = "https://${local.name_prefix}.sctp-sandbox.com/"
      MIN_CHAR   = "12"
      MAX_CHAR   = "16"
      REGION_AWS = "us-east-1"
      DB_NAME    = aws_dynamodb_table.url_table.name
    }
  }
}

# Lambda Function - Retrieve URL
data "archive_file" "retrieve_url_lambda" {
  type        = "zip"
  source_file = "${path.module}/retrieve_url_lambda.py"
  output_path = "${path.module}/retrieve_url_lambda.zip"
}

resource "aws_lambda_function" "retrieve_url" {
  # checkov:skip=CKV_AWS_117: VPC configuration is not required for this challenge
  # checkov:skip=CKV_AWS_363: Python 3.9 is acceptable for this challenge
  # checkov:skip=CKV_AWS_116: Dead Letter Queue is not required for this challenge
  # checkov:skip=CKV_AWS_50: X-Ray tracing is not required for this challenge
  # checkov:skip=CKV_AWS_173: KMS encryption for environment variables is not required for this challenge
  # checkov:skip=CKV_AWS_115: Concurrent execution limit is not required for this challenge
  # checkov:skip=CKV_AWS_272: Code signing is not required for this challenge
  filename         = data.archive_file.retrieve_url_lambda.output_path
  function_name    = "${local.name_prefix}-retrieve-url"
  role             = aws_iam_role.lambda_role.arn
  handler          = "retrieve_url_lambda.lambda_handler"
  source_code_hash = data.archive_file.retrieve_url_lambda.output_base64sha256
  runtime          = "python3.9"
  timeout          = 30

  environment {
    variables = {
      REGION_AWS = "us-east-1"
      DB_NAME    = aws_dynamodb_table.url_table.name
    }
  }
}

# Lambda Permissions for API Gateway
resource "aws_lambda_permission" "create_url_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/*"
}

resource "aws_lambda_permission" "retrieve_url_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.retrieve_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/*"
}

data "aws_route53_zone" "main" {
  name         = "sctp-sandbox.com"
  private_zone = false
}

# ACM Certificate for custom domain
resource "aws_acm_certificate" "main" {
  # checkov:skip=CKV2_AWS_71: Wildcard certificate is required for this use case
  domain_name       = "*.sctp-sandbox.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# ACM Certificate Validation
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Route53 records for ACM certificate validation
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${local.name_prefix}.sctp-sandbox.com"
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.shortener.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.shortener.regional_zone_id
    evaluate_target_health = true
  }
}

resource "aws_api_gateway_domain_name" "shortener" {
  # checkov:skip=CKV_AWS_206: Modern security policy is not required for this challenge
  domain_name              = "${local.name_prefix}.sctp-sandbox.com"
  regional_certificate_arn = aws_acm_certificate.main.arn

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  depends_on = [aws_acm_certificate_validation.main]
}

resource "aws_api_gateway_base_path_mapping" "shortener" {
  api_id      = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.api.stage_name
  domain_name = aws_api_gateway_domain_name.shortener.domain_name
}

resource "aws_wafv2_web_acl_logging_configuration" "api_gw_waf_logging" {
  resource_arn = aws_wafv2_web_acl.api_gw_waf.arn
  log_destination_configs = [
    "${aws_cloudwatch_log_group.waf_logs.arn}:*"
  ]

  logging_filter {
    # Default behavior when no filters match
    default_behavior = "DROP" # means "do not log" if no filter matches

    filter {
      behavior    = "KEEP" # keep logs if the condition matches
      requirement = "MEETS_ANY"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }
    }
  }
}

############# CREATE URL RESOURCES#####################
resource "aws_api_gateway_resource" "newurl" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "newurl"
}

resource "aws_api_gateway_method" "post_method" {
  # checkov:skip=CKV_AWS_59: Authorization is not required for this challenge
  # checkov:skip=CKV2_AWS_53: Request validation is not required for this challenge
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.newurl.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.newurl.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.create_url.invoke_arn
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.newurl.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_resource" "geturl" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{shortid}"
}

resource "aws_api_gateway_method" "get_method" {
  # checkov:skip=CKV_AWS_59: Authorization is not required for this challenge
  # checkov:skip=CKV2_AWS_53: Request validation is not required for this challenge
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.geturl.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.geturl.id
  http_method             = aws_api_gateway_method.get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.retrieve_url.invoke_arn
  request_templates = {
    "application/json" = <<EOF
    { 
      "short_id": "$input.params('shortid')" 
    }
    EOF
  }
}

resource "aws_api_gateway_method_response" "response_302" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.geturl.id
  http_method = aws_api_gateway_method.get_method.http_method
  status_code = "302"

  response_parameters = {
    "method.response.header.Location" = true
  }
}

resource "aws_api_gateway_integration_response" "get_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.geturl.id
  http_method = aws_api_gateway_method.get_method.http_method
  status_code = aws_api_gateway_method_response.response_302.status_code

  response_parameters = {
    "method.response.header.Location" = "integration.response.body.location"
  }
  depends_on = [
    aws_api_gateway_integration.get_integration
  ]
}

# Outputs
output "application_domain" {
  description = "Custom domain for the URL shortener application"
  value       = "https://${aws_api_gateway_domain_name.shortener.domain_name}"
}

output "api_gateway_url" {
  description = "API Gateway invoke URL (fallback)"
  value       = aws_api_gateway_stage.api.invoke_url
}

output "create_url_endpoint" {
  description = "Endpoint to create short URLs"
  value       = "https://${aws_api_gateway_domain_name.shortener.domain_name}/newurl"
}

output "dynamodb_table" {
  description = "DynamoDB table name for URL storage"
  value       = aws_dynamodb_table.url_table.name
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN protecting the API"
  value       = aws_wafv2_web_acl.api_gw_waf.arn
}
