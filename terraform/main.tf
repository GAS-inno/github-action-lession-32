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

resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-url-shortener"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "create_url" {
  function_name = "create-url-lambda"
  runtime       = "python3.12"
  handler       = "create-url-lambda.lambda_handler"
  role          = aws_iam_role.lambda_role.arn
  filename      = "lambda/create-url-lambda.zip"

  environment {
    variables = {
      APP_URL     = "https://group2-urlshortener.sctp-sandbox.com/"
      REGION_AWS  = "ap-southeast-1"
      DB_NAME     = aws_dynamodb_table.urls.name
      MIN_CHAR    = 12
      MAX_CHAR    = 16
    }
  }

  tracing_config {
    mode = "Active" # X-Ray enabled
  }
}

resource "aws_lambda_function" "retrieve_url" {
  function_name = "retrieve-url-lambda"
  runtime       = "python3.12"
  handler       = "retrieve-url-lambda.lambda_handler"
  role          = aws_iam_role.lambda_role.arn
  filename      = "lambda/retrieve-url-lambda.zip"

  environment {
    variables = {
      REGION_AWS = "ap-southeast-1"
      DB_NAME    = aws_dynamodb_table.urls.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}
