########################################
# Xomtracks "me" API Lambdas -- phone->account linking (multi-user
# attribution). Backs xomtracks-backend PR #10: lets any signed-in Xomware
# group member link their phone handle so they see + are attributed for
# THEIR own shares. All three routes are authed via the native
# COGNITO_USER_POOLS authorizer against the shared xomware_users pool, same
# as the shares list/match-override and playlists/create routes.
#
# Mirrors lambda.tf's shares block exactly (stub zip now, real code via CI
# once the backend handler folders are merged). Uses the same API lambda
# role (aws_iam_role.lambda_role) -- it already grants DynamoDB read/write
# on xomtracks-users + xomtracks-shares (table ARN prefix `xomtracks*`, see
# iam_lambda.tf) and SSM on /xomtracks/* -- so NO IAM change is needed here,
# same as playlists_create.
#
# Folder -> function name (deploy-backend.yml first-underscore split:
# DOMAIN=me, REST=<rest>):
#   lambdas/me_link_phone -> xomtracks-me-link_phone
#   lambdas/me_get        -> xomtracks-me-get
#   lambdas/me_shares     -> xomtracks-me-shares
#
# ROUTE NOTE (GET /me): the backend PR describes this endpoint as `GET /me`,
# but the api-gateway-service module (v2.7.0) supports exactly two path
# levels -- a service `path_prefix` (`me`) and one `path_part` per endpoint
# beneath it -- so it cannot attach a method to the bare service resource.
# This is the SAME constraint that already turned `GET /shares` into
# `GET /shares/list` (see lambda.tf's PATH DESIGN NOTE). Resolved the same
# way: `GET /me/get` is the me-get route. The me_get handler reads the
# Cognito authorizer context only, not the URL path, so this needs ZERO
# backend code changes -- callers hit `/me/get`.
########################################

locals {
  me_lambdas = [
    {
      name          = "link_phone"
      description   = "Link the caller's phone handle to their Cognito identity; report matched-share count (authed)"
      path_part     = "link-phone"
      http_method   = "POST"
      authorization = "COGNITO_USER_POOLS"
    },
    {
      name          = "get"
      description   = "Caller's linked handles + share count (authed) -- GET /me/get (module 2-level path; see header)"
      path_part     = "get"
      http_method   = "GET"
      authorization = "COGNITO_USER_POOLS"
    },
    {
      name          = "shares"
      description   = "Caller's OWN shares by linked handle, windowed, newest-first (authed)"
      path_part     = "shares"
      http_method   = "GET"
      authorization = "COGNITO_USER_POOLS"
    },
  ]
}

resource "aws_lambda_function" "me" {
  for_each         = { for lambda in local.me_lambdas : lambda.name => lambda }
  function_name    = "${var.app_name}-me-${each.value.name}"
  description      = each.value.description
  filename         = "./templates/lambda_stub.zip"
  source_code_hash = filebase64sha256("./templates/lambda_stub.zip")
  handler          = "handler.handler"
  layers           = [aws_lambda_layer_version.lambda_layer.arn]
  runtime          = var.lambda_runtime
  memory_size      = var.lambda_memory_size
  timeout          = var.lambda_timeout
  role             = aws_iam_role.lambda_role.arn

  environment {
    variables = local.lambda_variables
  }

  tracing_config {
    mode = var.lambda_trace_mode
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-me-${each.value.name}", "lambda_type" = "me" }))

  lifecycle {
    ignore_changes = [
      description,
      filename,
      source_code_hash,
      layers
    ]
  }

  depends_on = [
    aws_iam_role_policy.lambda_role_policy,
    aws_iam_role.lambda_role
  ]
}
