data "aws_route53_zone" "sctp_zone" {
  name = "sctp-sandbox.com"
  }

  resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.sctp_zone.zone_id
  name = "${var.name_prefix}s3" # Bucket prefix before sctp-sandbox.com
  type = "A"
  }