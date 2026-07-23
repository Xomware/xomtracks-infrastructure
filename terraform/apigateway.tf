## API Gateway Account (account-level singleton)

resource "aws_api_gateway_account" "api_gateway_account" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
}

#**********************
# API Gateway (via reusable module)
#**********************

locals {
  # `authorization` is carried through per-endpoint so the module can mix
  # auth types on one API: authed routes use the native COGNITO_USER_POOLS
  # authorizer (validated by API Gateway against the shared xomware_users
  # pool -- see data_cognito.tf and the module block below, matching
  # meals-infrastructure), while public routes override to NONE. The ingest
  # route is NONE at the API Gateway layer -- auth for it happens INSIDE the
  # handler via the SSM-scoped bearer key
  # (utility_helpers.require_ingest_bearer_key), not Cognito. The auth/login
  # route is also NONE (it MINTS xomtracks' own Spotify-derived token; it is
  # not gated by Cognito).
  auth_endpoints = [
    for l in local.auth_lambdas : {
      name          = l.name
      path_part     = l.path_part
      http_method   = l.http_method
      invoke_arn    = aws_lambda_function.auth[l.name].invoke_arn
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
}

module "api" {
  source = "git::https://github.com/domgiordano/api-gateway-service.git?ref=v2.7.0"

  app_name      = var.app_name
  stage_name    = var.api_stage_name
  authorization = "COGNITO_USER_POOLS"
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
    auth      = { path_prefix = "auth", endpoints = local.auth_endpoints }
    shares    = { path_prefix = "shares", endpoints = local.shares_endpoints }
    playlists = { path_prefix = "playlists", endpoints = local.playlists_endpoints }
    me        = { path_prefix = "me", endpoints = local.me_endpoints }
    ratings   = { path_prefix = "ratings", endpoints = local.ratings_endpoints }
  }
}
