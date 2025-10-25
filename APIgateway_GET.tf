
resource "aws_api_gateway_resource" "geturl" {
    rest_api_id = aws_api_gateway_rest_api.main.id # Modify this to reference your API
  parent_id   = aws_api_gateway_resource.parent.id # Modify this to reference your parent resource
  path_part   = "geturl" # Change the path part as needed
}

resource "aws_api_gateway_method" "get_method" {
     rest_api_id   = aws_api_gateway_rest_api.main.id # Modify this to reference your API
  resource_id   = aws_api_gateway_resource.geturl.id
  http_method   = "GET" # Change to the appropriate method
  authorization = "NONE" # Modify if authorization is needed
}

resource "aws_api_gateway_integration" "get_integration" {
 rest_api_id             = aws_api_gateway_rest_api.main.id # Modify this to reference your API
  resource_id             = aws_api_gateway_resource.geturl.id
  http_method             = aws_api_gateway_method.get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY" # Or another type as appropriate
  uri                     = "arn:aws:lambda:us-west-2:123456789012:function:your-function" # Replace with your Lambda URI

  request_templates = {
    "application/json" = <<EOF
    { 
      "short_id": "$input.params('shortid')" 
    }
    EOF
  }
}

resource "aws_api_gateway_method_response" "response_302" {
  rest_api_id   = aws_api_gateway_rest_api.main.id # Modify this to reference your API
  resource_id   = aws_api_gateway_resource.geturl.id
  http_method   = aws_api_gateway_method.get_method.http_method
  status_code   = "302"

  response_parameters = {
    "method.response.header.Location" = true
  }
}

resource "aws_api_gateway_integration_response" "get_integration_response" {
   rest_api_id = aws_api_gateway_rest_api.main.id # Modify this to reference your API
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