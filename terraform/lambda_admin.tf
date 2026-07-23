########################################
# Xomtracks "admin" API Lambdas -- phone-link approval queue. Backs the
# ADMIN-APPROVAL rework: a member's POST /me/link-phone creates a PENDING
# request (xomtracks-link-requests, see dynamodb.tf); these routes let the
# admin (Dom) list, approve, and deny those requests.
#
# All three routes are authed via the native COGNITO_USER_POOLS authorizer
# against the shared xomware_users pool (same as the shares/me/ratings/heard
# routes). The Cognito authorizer only proves the caller is SOME signed-in
# Xomware member -- the ADMIN gate (caller email == ADMIN_EMAIL) is enforced
# IN-HANDLER via utility_helpers.require_admin (403 for non-admins). ADMIN_EMAIL
# is injected through the shared lambda env (see locals.tf lambda_variables).
#
# Uses the same API lambda role (aws_iam_role.lambda_role) -- it already grants
# DynamoDB read/write on the whole `xomtracks*` table ARN prefix (covers the new
# xomtracks-link-requests + existing xomtracks-users tables) and SSM on
# /xomtracks/* -- so NO IAM change is needed here for table/SSM access. (The
# separate ses:SendEmail grant added in iam_lambda.tf is for me_link_phone's
# notification, not these admin routes.)
#
# Mirrors lambda_me.tf / lambda_ratings.tf exactly (stub zip now, real code via
# CI once the backend handler folders are merged).
#
# Folder -> function name (deploy-backend.yml first-underscore split:
# DOMAIN=admin, REST=<rest>):
#   lambdas/admin_requests -> xomtracks-admin-requests
#   lambdas/admin_approve  -> xomtracks-admin-approve
#   lambdas/admin_deny     -> xomtracks-admin-deny
#
# ROUTE NOTE (2-path-level module constraint): the api-gateway-service module
# (v2.7.0) supports exactly two path levels -- a service `path_prefix` (`admin`)
# and one `path_part` per endpoint beneath it -- so it cannot express the
# 3-level `/admin/requests/approve` sketched in the task. Resolved the SAME way
# `GET /shares` became `GET /shares/list`: the endpoints are
#   GET  /admin/requests   (list pending)
#   POST /admin/approve    (approve {requestId})
#   POST /admin/deny       (deny {requestId})
# The handlers read the Cognito authorizer context + body only, not the URL
# path, so this needs ZERO backend code changes -- callers hit those paths.
########################################

locals {
  admin_lambdas = [
    {
      name          = "requests"
      description   = "List pending phone-link requests for the admin queue (admin-gated) -- GET /admin/requests"
      path_part     = "requests"
      http_method   = "GET"
      authorization = "COGNITO_USER_POOLS"
    },
    {
      name          = "approve"
      description   = "Approve a pending link request -- creates the real link + marks approved (admin-gated) -- POST /admin/approve"
      path_part     = "approve"
      http_method   = "POST"
      authorization = "COGNITO_USER_POOLS"
    },
    {
      name          = "deny"
      description   = "Deny a pending link request -- marks denied, no link (admin-gated) -- POST /admin/deny"
      path_part     = "deny"
      http_method   = "POST"
      authorization = "COGNITO_USER_POOLS"
    },
  ]
}

resource "aws_lambda_function" "admin" {
  for_each         = { for lambda in local.admin_lambdas : lambda.name => lambda }
  function_name    = "${var.app_name}-admin-${each.value.name}"
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

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-admin-${each.value.name}", "lambda_type" = "admin" }))

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
