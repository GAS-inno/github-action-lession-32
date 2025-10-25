# -------------------------------
# Data Source: Route53 Hosted Zone
# -------------------------------
data "aws_route53_zone" "sctp_zone" {
  name = "sctp-sandbox.com"
}

# -------------------------------
# API Gateway Custom Domain
# -------------------------------
resource "aws_api_gateway_domain_name" "shortener" {
  domain_name              = "api.sctp-sandbox.com" # Your custom API domain
  regional_certificate_arn = var.acm_certificate_arn # ACM cert ARN (in same region as API Gateway)

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  # Enable CloudFront domain association
  regional_domain_name = "api.sctp-sandbox.com"
}

# -------------------------------
# Route53 Alias Record → API Gateway Custom Domain
# -------------------------------
resource "aws_route53_record" "api_domain_record" {
  zone_id = data.aws_route53_zone.sctp_zone.zone_id
  name    = "api" # Creates api.sctp-sandbox.com
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.shortener.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.shortener.regional_zone_id
    evaluate_target_health = false
  }
}

# -------------------------------
# Base Path Mapping (links domain to API Gateway)
# -------------------------------
resource "aws_api_gateway_base_path_mapping" "shortener" {
  domain_name = aws_api_gateway_domain_name.shortener.domain_name
  api_id      = aws_api_gateway_rest_api.shortener.id  # <-- replace with your API resource name
  stage_name  = aws_api_gateway_stage.shortener.stage_name # <-- replace with your stage resource
}

# -------------------------------
# Optional: Simple S3 Record (example)
# -------------------------------
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.sctp_zone.zone_id
  name    = "${var.name_prefix}s3" # e.g., myprefixs3.sctp-sandbox.com
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}
