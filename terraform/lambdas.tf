resource "aws_lambda_function" "create_url" {
  function_name = "create-url-lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "main.lambda_handler"
  runtime       = "python3.9"
  filename      = "${path.module}/../lambdas/create_url.zip"
  environment {
    variables = {
      APP_URL    = "https://${var.app_domain}/"
      DB_NAME    = aws_dynamodb_table.shortener.name
      REGION_AWS = var.region
      MIN_CHAR   = "12"
      MAX_CHAR   = "16"
    }
  }
}

resource "aws_lambda_function" "retrieve_url" {
  function_name = "retrieve-url-lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "main.lambda_handler"
  runtime       = "python3.9"
  filename      = "${path.module}/../lambdas/retrieve_url.zip"
  environment {
    variables = {
      DB_NAME    = aws_dynamodb_table.shortener.name
      REGION_AWS = var.region
    }
  }
}
