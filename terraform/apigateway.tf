## API Gateway Account (account-level singleton) — INTENTIONALLY NOT MANAGED HERE
#
# `aws_api_gateway_account` is ONE setting per AWS account per region. Multiple
# app repos in this account (xomtracks, xomforms, …) were each managing it and
# each pointing `cloudwatch_role_arn` at their OWN `<app>-api_gateway-logs`
# role — so every apply from either repo flipped the account's logging role
# back and forth (xomforms-api_gateway-logs <-> xomtracks-api_gateway-logs),
# showing as perpetual drift on every plan.
#
# A shared account-level singleton must have a SINGLE owner. xomtracks defers
# ownership: it no longer declares this resource, so its applies stop churning
# it. Removing this resource is safe — the AWS provider's destroy of
# `aws_api_gateway_account` is a no-op (there is no AWS API to reset account
# settings), so the LIVE cloudwatch_role_arn is left intact; it just drops out
# of xomtracks' state. The `api_gateway_cloudwatch` role below is retained so
# that live pointer stays valid until the owning repo reconciles it.
#
# Long-term home: this belongs in the shared `xomware-infrastructure` bootstrap
# (the same repo that owns the shared Cognito pool), not per-app.

#**********************
# API Gateway (via reusable module)
#**********************

locals {
  # `authorization` is carried through per-endpoint. WS-AUTH: xomify is the
  # SOLE frontend and authenticates via a homegrown HS256 JWT (claims email +
  # userId, secret at SSM /xomify/api/API_SECRET_KEY) -- there is NO Cognito.
  # So EVERY route is now `NONE` at the API Gateway layer and each handler
  # validates the caller's Bearer token IN-HANDLER via
  # xomify_auth.verify_xomify_token (mirroring how the ingest route already
  # validates its SSM-scoped bearer key in-handler). The module-level
  # authorization is NONE too, so the previously-provisioned Cognito authorizer
  # is removed (needs_cognito_authorizer -> false). /shares/recent is also NONE
  # -- it is the PUBLIC hub showcase, server-side-scoped to the showcase owner.
  auth_endpoints = [
    for l in local.auth_lambdas : {
      name          = l.name
      path_part     = l.path_part
      http_method   = l.http_method
      invoke_arn    = aws_lambda_function.auth[l.name].invoke_arn
      authorization = l.authorization
    }
  ]

  ingest_tokens_endpoints = [
    for l in local.ingest_tokens_lambdas : {
      name          = l.name
      path_part     = l.path_part
      http_method   = l.http_method
      invoke_arn    = aws_lambda_function.ingest_tokens[l.name].invoke_arn
      authorization = l.authorization
    }
  ]

  shares_endpoints = [
    for l in local.shares_lambdas : {
      name          = l.name
      path_part     = l.path_part
      http_method   = l.http_method
      invoke_arn    = aws_lambda_function.shares[l.name].invoke_arn
      authorization = l.authorization
    }
  ]

  ingest_endpoints = [
    for l in local.ingest_lambdas : {
      name          = l.name
      path_part     = l.path_part
      http_method   = l.http_method
      invoke_arn    = aws_lambda_function.ingest[l.name].invoke_arn
      authorization = l.authorization
    }
  ]

  playlists_endpoints = [
    for l in local.playlists_lambdas : {
      name          = l.name
      path_part     = l.path_part
      http_method   = l.http_method
      invoke_arn    = aws_lambda_function.playlists[l.name].invoke_arn
      authorization = l.authorization
    }
  ]

  me_endpoints = [
    for l in local.me_lambdas : {
      name          = l.name
      path_part     = l.path_part
      http_method   = l.http_method
      invoke_arn    = aws_lambda_function.me[l.name].invoke_arn
      authorization = l.authorization
    }
  ]

  ratings_endpoints = [
    for l in local.ratings_lambdas : {
      name          = l.name
      path_part     = l.path_part
      http_method   = l.http_method
      invoke_arn    = aws_lambda_function.ratings[l.name].invoke_arn
      authorization = l.authorization
    }
  ]

  heard_endpoints = [
    for l in local.heard_lambdas : {
      name          = l.name
      path_part     = l.path_part
      http_method   = l.http_method
      invoke_arn    = aws_lambda_function.heard[l.name].invoke_arn
      authorization = l.authorization
    }
  ]

  admin_endpoints = [
    for l in local.admin_lambdas : {
      name          = l.name
      path_part     = l.path_part
      http_method   = l.http_method
      invoke_arn    = aws_lambda_function.admin[l.name].invoke_arn
      authorization = l.authorization
    }
  ]
}

module "api" {
  source = "git::https://github.com/domgiordano/api-gateway-service.git?ref=v2.7.0"

  app_name      = var.app_name
  stage_name    = var.api_stage_name
  authorization = "NONE"
  cognito_user_pool_arns = [
    data.aws_ssm_parameter.cognito_user_pool_arn.value
  ]
  tags          = local.standard_tags
  allow_headers = local.api_allow_headers
  allow_origin  = var.cors_allowed_origins

  # Custom domain
  domain_name     = local.api_domain_name
  certificate_arn = aws_acm_certificate_validation.api.certificate_arn

  services = {
    auth          = { path_prefix = "auth", endpoints = local.auth_endpoints }
    ingest_tokens = { path_prefix = "ingest-tokens", endpoints = local.ingest_tokens_endpoints }
    shares        = { path_prefix = "shares", endpoints = local.shares_endpoints }
    ingest        = { path_prefix = "ingest", endpoints = local.ingest_endpoints }
    playlists     = { path_prefix = "playlists", endpoints = local.playlists_endpoints }
    me            = { path_prefix = "me", endpoints = local.me_endpoints }
    ratings       = { path_prefix = "ratings", endpoints = local.ratings_endpoints }
    heard         = { path_prefix = "heard", endpoints = local.heard_endpoints }
    admin         = { path_prefix = "admin", endpoints = local.admin_endpoints }
  }
}
