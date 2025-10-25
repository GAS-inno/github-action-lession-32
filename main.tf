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

resource "aws_route53_record" "www" {}

resource "aws_api_gateway_domain_name" "shortener" {
  domain_name              = ""
  regional_certificate_arn = "" # ACM Cert for your domain

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "shortener" {}

resource "aws_wafv2_web_acl_logging_configuration" "api_gw_waf_logging" {
  resource_arn = aws_wafv2_web_acl.api_gw_waf.arn
  log_destination_configs = [
    aws_cloudwatch_log_group.waf_logs.arn
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
resource "aws_api_gateway_resource" "newurl" {}

resource "aws_api_gateway_method" "post_method" {}

resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id             =
  resource_id             = 
  http_method             = 
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = 
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

resource "aws_api_gateway_resource" "geturl" {}

resource "aws_api_gateway_method" "get_method" {}

resource "aws_api_gateway_integration" "get_integration" {
  rest_api_id             =
  resource_id             =
  http_method             =
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     =
  request_templates = {
    "application/json" = <<EOF
    { 
      "short_id": "$input.params('shortid')" 
    }
    EOF
  }
}

resource "aws_api_gateway_method_response" "response_302" {
  rest_api_id =
  resource_id =
  http_method =
  status_code = "302"

  response_parameters = {
    "method.response.header.Location" = true
  }
}

resource "aws_api_gateway_integration_response" "get_integration_response" {
  rest_api_id =
  resource_id =
  http_method =
  status_code = aws_api_gateway_method_response.response_302.status_code

  response_parameters = {
    "method.response.header.Location" = "integration.response.body.location"
  }
  depends_on = [
    aws_api_gateway_integration.get_integration
  ]
}
