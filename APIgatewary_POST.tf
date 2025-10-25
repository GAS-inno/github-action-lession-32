############# CREATE URL RESOURCES #####################

resource "aws_api_gateway_resource" "newurl" {
  rest_api_id = aws_api_gateway_rest_api.api.id # Modify this to reference your API
  parent_id   = aws_api_gateway_resource.parent.id # Modify if needed to reference your parent resource
  path_part   = "newurl" # Change the path part as needed
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id # Modify this to reference your API
  resource_id = aws_api_gateway_resource.newurl.id
  http_method = "POST" # Change if necessary
  authorization = "NONE" # Modify if authorization is needed
}

resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id # Modify this to reference your API
  resource_id             = aws_api_gateway_resource.newurl.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:lambda:us-west-2:123456789012:function:your-function" # Replace with your Lambda function ARN
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id   = aws_api_gateway_rest_api.api.id # Modify this to reference your API
  resource_id   = aws_api_gateway_resource.newurl.id
  http_method   = aws_api_gateway_method.post_method.http_method
  status_code   = "200"

  response_models = {
    "application/json" = "Empty" # Change to the appropriate model or keep as "Empty" if no body is returned
  }
}
