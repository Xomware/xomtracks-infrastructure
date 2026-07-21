## API Gateway Account (account-level singleton)

resource "aws_api_gateway_account" "api_gateway_account" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
}

#**********************
# API Gateway (via reusable module)
#**********************

locals {
  # `authorization` is carried through per-endpoint so the module skips the
  # custom Lambda authorizer (NONE) for public routes rather than
  # inheriting the module-level default (CUSTOM). The ingest route is
  # NONE at the API Gateway layer -- auth for it happens INSIDE the
  # handler via the SSM-scoped bearer key
  # (utility_helpers.require_ingest_bearer_key), not Cognito.
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
}

module "api" {
  source = "git::https://github.com/domgiordano/api-gateway-service.git?ref=v2.7.0"

  app_name              = var.app_name
  stage_name            = var.api_stage_name
  authorizer_invoke_arn = aws_lambda_function.authorizer.invoke_arn
  authorizer_role_arn   = aws_iam_role.apigw_authorizer_invoke.arn
  tags                  = local.standard_tags
  allow_headers         = local.api_allow_headers
  allow_origin          = var.cors_allowed_origins

  # Custom domain
  domain_name     = local.api_domain_name
  certificate_arn = aws_acm_certificate_validation.api.certificate_arn

  services = {
    auth   = { path_prefix = "auth", endpoints = local.auth_endpoints }
    shares = { path_prefix = "shares", endpoints = local.shares_endpoints }
  }
}
