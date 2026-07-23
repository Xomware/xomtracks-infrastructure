# =============================================================================
# SES (Simple Email Service) -- Xomtracks sending identity
# =============================================================================
# Provisions the xomtracks.xomware.com domain identity with Easy DKIM + a custom
# MAIL FROM subdomain, mirroring xomforms-infrastructure/terraform/ses.tf (which
# in turn mirrors the console-created xomify/xomper/derby pattern).
#
# WHY: the ADMIN-APPROVAL rework of phone linking emails Dom on every new
# link request (POST /me/link-phone) so he can approve/deny it in the admin
# portal (see lambda_admin.tf + xomtracks-backend/lambdas/common/email_notify.py).
#
# Additive: this file only creates NEW records under the xomtracks.xomware.com
# subdomain + its mail.<...> MAIL FROM subdomain. The website A record
# (s3_cloudfront.tf / route53.tf) is on the SAME apex name but a different
# record type, so there's no collision. It does not read/import/modify any
# other app's identity.
#
# The AWS account already has SES PRODUCTION access (ProductionAccessEnabled =
# true, 50k/day) -- no sandbox-exit request is required, so once the domain
# identity verifies, sends to any recipient (incl. Dom's gmail) work.
#
# Sender used by the admin-notify Lambda: noreply@xomtracks.xomware.com
# (published to SSM below so the backend reads it at runtime).

locals {
  ses_domain           = local.domain_name              # xomtracks.xomware.com
  ses_mail_from_domain = "mail.${local.domain_name}"    # mail.xomtracks.xomware.com
  ses_from_address     = "noreply@${local.domain_name}" # noreply@xomtracks.xomware.com
}

# -----------------------------------------------------------------------------
# Configuration set -- tracks reputation (bounce/complaint) metrics for the
# notification stream and enforces TLS on delivery. The admin-notify Lambda
# passes this set name on every SendEmail call.
# -----------------------------------------------------------------------------
resource "aws_sesv2_configuration_set" "xomtracks" {
  configuration_set_name = "${var.app_name}-notifications"

  delivery_options {
    tls_policy = "REQUIRE"
  }

  reputation_options {
    reputation_metrics_enabled = true
  }

  sending_options {
    sending_enabled = true
  }

  tags = local.standard_tags
}

# -----------------------------------------------------------------------------
# Domain identity with Easy DKIM (SES-managed RSA-2048 keys). SES generates 3
# DKIM tokens; the CNAME records below publish them so verification succeeds.
# -----------------------------------------------------------------------------
resource "aws_sesv2_email_identity" "xomtracks" {
  email_identity         = local.ses_domain
  configuration_set_name = aws_sesv2_configuration_set.xomtracks.configuration_set_name

  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }

  tags = local.standard_tags
}

# Custom MAIL FROM (Return-Path) domain -- aligns SPF/bounce handling with the
# sending domain, matching the other apps' mail.<app>.xomware.com convention.
resource "aws_sesv2_email_identity_mail_from_attributes" "xomtracks" {
  email_identity         = aws_sesv2_email_identity.xomtracks.email_identity
  mail_from_domain       = local.ses_mail_from_domain
  behavior_on_mx_failure = "USE_DEFAULT_VALUE"
}

# -----------------------------------------------------------------------------
# Route53 records (all under the shared xomware.com hosted zone) -- additive.
# -----------------------------------------------------------------------------

# DKIM: 3 CNAMEs -> <token>.dkim.amazonses.com
resource "aws_route53_record" "ses_dkim" {
  count   = 3
  zone_id = data.aws_route53_zone.web_zone.zone_id
  name    = "${aws_sesv2_email_identity.xomtracks.dkim_signing_attributes[0].tokens[count.index]}._domainkey.${local.ses_domain}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_sesv2_email_identity.xomtracks.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}

# MAIL FROM: MX record pointing at the regional SES feedback endpoint.
resource "aws_route53_record" "ses_mail_from_mx" {
  zone_id = data.aws_route53_zone.web_zone.zone_id
  name    = local.ses_mail_from_domain
  type    = "MX"
  ttl     = 600
  records = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]
}

# MAIL FROM: SPF authorizing Amazon SES to send for the MAIL FROM domain.
resource "aws_route53_record" "ses_mail_from_spf" {
  zone_id = data.aws_route53_zone.web_zone.zone_id
  name    = local.ses_mail_from_domain
  type    = "TXT"
  ttl     = 600
  records = ["v=spf1 include:amazonses.com ~all"]
}

# DMARC (subdomain-scoped, monitor-only p=none) -- improves deliverability and
# gives aggregate reporting without affecting the apex xomware.com policy.
resource "aws_route53_record" "ses_dmarc" {
  zone_id = data.aws_route53_zone.web_zone.zone_id
  name    = "_dmarc.${local.ses_domain}"
  type    = "TXT"
  ttl     = 600
  records = ["v=DMARC1; p=none; rua=mailto:dominickj.giordano@gmail.com; fo=1"]
}

# -----------------------------------------------------------------------------
# SSM -- publish the sender address + config set name so the backend
# admin-notify Lambda reads them at runtime (matching ssm.tf's convention +
# xomtracks-backend/lambdas/common/ssm_helpers.py's SES_FROM_ADDRESS /
# SES_CONFIGURATION_SET lookups under /xomtracks/ses/*). Not secret, so stored
# as plain String.
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "ses_from_address" {
  name        = "/${var.app_name}/ses/FROM_ADDRESS"
  description = "Verified SES sender for Xomtracks admin notification emails"
  type        = "String"
  value       = local.ses_from_address

  lifecycle { ignore_changes = [tags, tags_all] }
}

resource "aws_ssm_parameter" "ses_configuration_set" {
  name        = "/${var.app_name}/ses/CONFIGURATION_SET"
  description = "SES configuration set applied to Xomtracks admin notification sends"
  type        = "String"
  value       = aws_sesv2_configuration_set.xomtracks.configuration_set_name

  lifecycle { ignore_changes = [tags, tags_all] }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "ses_from_address" {
  description = "Verified SES sender address for Xomtracks admin notification emails"
  value       = local.ses_from_address
}

output "ses_domain_identity_arn" {
  description = "ARN of the xomtracks.xomware.com SES domain identity"
  value       = aws_sesv2_email_identity.xomtracks.arn
}

output "ses_configuration_set_name" {
  description = "SES configuration set used for Xomtracks admin notification sends"
  value       = aws_sesv2_configuration_set.xomtracks.configuration_set_name
}
