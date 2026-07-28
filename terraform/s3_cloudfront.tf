#**********************
# Standalone site: xomtracks.xomware.com -> 301 REDIRECT to xomify
#**********************
#
# The standalone xomtracks-frontend is DEPRECATED -- the app now lives inside
# xomify at https://xomify.xomware.com/shares. This file makes the old site's
# CloudFront distribution permanently (301) redirect every request there, while
# KEEPING the distribution, its ACM cert, and the DNS record intact (no delete).
#
# WHY THIS IS NO LONGER `module "web"`:
# The site was previously provisioned by the external web-hosting module
# (git::.../web-hosting.git?ref=v1.1.0), which does NOT expose a way to attach
# an arbitrary viewer-request CloudFront Function, and whose newer built-in
# redirect (canonical_host) only rewrites the HOST while preserving the path --
# it cannot send every path to a single fixed URL (.../shares). So the module's
# resources are inlined here VERBATIM (byte-for-byte the v1.1.0 config that is
# already deployed, so the plan is a no-op for them) plus ONE addition: a
# viewer-request function on the default behavior that returns 301 to
# https://xomify.xomware.com/shares.
#
# STATE MIGRATION: every resource below is paired with a `moved` block that
# renames it FROM module.web.<addr> TO this root address, so Terraform UPDATES
# them in place rather than destroying + recreating. Reviewing the plan, the
# ONLY expected changes are (1) the new aws_cloudfront_function.redirect and
# (2) an in-place update to aws_cloudfront_distribution.site adding the
# function_association. If the plan shows ANY resource being destroyed/replaced
# (distribution, bucket, or cert), DO NOT APPLY -- that would violate the "keep
# the distribution/cert/DNS" requirement.

locals {
  # The single URL the deprecated standalone site redirects to.
  xomtracks_redirect_target = "https://xomify.xomware.com/shares"
}

#######################################
# Viewer-request redirect function (NEW)
#######################################

resource "aws_cloudfront_function" "redirect" {
  name    = "${var.app_name}-redirect-to-xomify"
  runtime = "cloudfront-js-2.0"
  comment = "301-redirect the deprecated standalone site to ${local.xomtracks_redirect_target}"
  publish = true
  code    = <<-EOF
    function handler(event) {
      return {
        statusCode: 301,
        statusDescription: 'Moved Permanently',
        headers: {
          location: { value: '${local.xomtracks_redirect_target}' }
        }
      };
    }
  EOF
}

#######################################
# S3 Bucket (inlined verbatim from web-hosting v1.1.0)
#######################################

resource "aws_s3_bucket" "site" {
  bucket        = local.domain_name
  force_destroy = true
  tags          = merge(local.standard_tags, { "name" = local.domain_name })
}

moved {
  from = module.web.aws_s3_bucket.site
  to   = aws_s3_bucket.site
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

moved {
  from = module.web.aws_s3_bucket_ownership_controls.site
  to   = aws_s3_bucket_ownership_controls.site
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

moved {
  from = module.web.aws_s3_bucket_public_access_block.site
  to   = aws_s3_bucket_public_access_block.site
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

moved {
  from = module.web.aws_s3_bucket_versioning.site
  to   = aws_s3_bucket_versioning.site
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_alias.web_app.target_key_arn
    }
  }
}

moved {
  from = module.web.aws_s3_bucket_server_side_encryption_configuration.site
  to   = aws_s3_bucket_server_side_encryption_configuration.site
}

resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    id = "delete-older-than-latest-3-versions"
    noncurrent_version_expiration {
      newer_noncurrent_versions = 3
      noncurrent_days           = 1
    }
    status = "Enabled"
  }

  rule {
    id = "delete-old-versions-after-90-days"
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    status = "Enabled"
  }
}

moved {
  from = module.web.aws_s3_bucket_lifecycle_configuration.site
  to   = aws_s3_bucket_lifecycle_configuration.site
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontAccess"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.site.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.site.arn
          }
        }
      }
    ]
  })
}

moved {
  from = module.web.aws_s3_bucket_policy.site
  to   = aws_s3_bucket_policy.site
}

#######################################
# ACM Certificate (inlined verbatim from web-hosting v1.1.0)
#######################################

resource "aws_acm_certificate" "cert" {
  domain_name       = local.domain_name
  validation_method = "DNS"
  tags              = merge(local.standard_tags, { "name" = "${var.app_name}-certificate" })

  lifecycle {
    create_before_destroy = true
  }
}

moved {
  from = module.web.aws_acm_certificate.cert
  to   = aws_acm_certificate.cert
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
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
  zone_id         = data.aws_route53_zone.web_zone.zone_id
}

moved {
  from = module.web.aws_route53_record.cert_validation
  to   = aws_route53_record.cert_validation
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

moved {
  from = module.web.aws_acm_certificate_validation.cert
  to   = aws_acm_certificate_validation.cert
}

#######################################
# CloudFront (inlined from web-hosting v1.1.0 + the redirect function)
#######################################

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "oac-for-${var.app_name}"
  description                       = "OAC for S3 bucket ${var.app_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

moved {
  from = module.web.aws_cloudfront_origin_access_control.site
  to   = aws_cloudfront_origin_access_control.site
}

resource "aws_cloudfront_distribution" "site" {
  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "${var.app_name}-origin"
    origin_path              = var.cloudfront_origin_path
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  web_acl_id          = data.aws_ssm_parameter.shared_cloudfront_waf_arn.value != "" ? data.aws_ssm_parameter.shared_cloudfront_waf_arn.value : null
  aliases             = [local.domain_name]
  retain_on_delete    = var.retain_on_delete
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  dynamic "custom_error_response" {
    for_each = var.custom_error_response_page_path != "" ? [1] : []
    content {
      error_code         = 403
      response_code      = 200
      response_page_path = var.custom_error_response_page_path
    }
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "${var.app_name}-origin"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id

    # The ONE addition vs. the v1.1.0 module: a viewer-request function that
    # 301-redirects every request to xomify BEFORE any origin fetch. The S3
    # origin below is now effectively unused (kept so the plan stays a no-op
    # for the distribution's structure), since the function short-circuits.
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.redirect.arn
    }

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = var.enable_cloudfront_cache ? 60 : 0
    max_ttl                = var.enable_cloudfront_cache ? 60 : 0
    viewer_protocol_policy = "redirect-to-https"
  }

  dynamic "restrictions" {
    for_each = var.us_canada_only ? [1] : []
    content {
      geo_restriction {
        restriction_type = "whitelist"
        locations        = ["US", "CA"]
      }
    }
  }

  dynamic "restrictions" {
    for_each = var.us_canada_only ? [] : [1]
    content {
      geo_restriction {
        restriction_type = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = aws_acm_certificate.cert.arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = var.minimum_tls_version
  }

  depends_on = [aws_acm_certificate_validation.cert]

  tags = merge(local.standard_tags, { "name" = "${var.app_name}-cloudfront" })
}

moved {
  from = module.web.aws_cloudfront_distribution.site
  to   = aws_cloudfront_distribution.site
}

resource "aws_cloudfront_response_headers_policy" "site" {
  name = "security-headers-policy-for-${var.app_name}"

  security_headers_config {
    content_type_options {
      override = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
      preload                    = true
    }
    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    xss_protection {
      mode_block = true
      override   = true
      protection = true
    }
  }
}

moved {
  from = module.web.aws_cloudfront_response_headers_policy.site
  to   = aws_cloudfront_response_headers_policy.site
}

#######################################
# Route53 A record for the site (inlined verbatim from web-hosting v1.1.0)
#######################################

resource "aws_route53_record" "site" {
  zone_id = data.aws_route53_zone.web_zone.zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = true
  }
}

moved {
  from = module.web.aws_route53_record.site
  to   = aws_route53_record.site
}
