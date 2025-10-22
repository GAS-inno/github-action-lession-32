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