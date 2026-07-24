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
#   lambdas/admin_requests    -> xomtracks-admin-requests
#   lambdas/admin_approve     -> xomtracks-admin-approve
#   lambdas/admin_deny        -> xomtracks-admin-deny
#   lambdas/admin_users       -> xomtracks-admin-users
#   lambdas/admin_userfeed    -> xomtracks-admin-userfeed
#   lambdas/admin_calls       -> xomtracks-admin-calls
#   lambdas/admin_tokens      -> xomtracks-admin-tokens
#   lambdas/admin_revoketoken -> xomtracks-admin-revoketoken
#
# ROUTE NOTE (2-path-level module constraint): the api-gateway-service module
# (v2.7.0) supports exactly two path levels -- a service `path_prefix` (`admin`)
# and one `path_part` per endpoint beneath it. path_part is independent of the
# function name (hyphenated route vs first-underscore function name), same as
# me_link_phone -> function xomtracks-me-link_phone at path /me/link-phone. The
# endpoints are:
#   GET  /admin/requests      (list pending link requests)
#   POST /admin/approve       (approve {requestId})
#   POST /admin/deny          (deny {requestId})
#   GET  /admin/users         (user directory -- WS6)
#   GET  /admin/user-feed     (impersonation / view-as, read-only -- WS6)
#   GET  /admin/calls         (calls & errors dashboard -- WS6)
#   GET  /admin/tokens        (list ingest tokens per owner -- WS6)
#   POST /admin/revoke-token  (admin override revoke {tokenHash} -- WS6)
# Every route is authorization NONE at the gateway; the ADMIN gate (caller email
# == ADMIN_EMAIL) is enforced IN-HANDLER via utility_helpers.require_admin. The
# handlers read query/body + caller identity only, not the URL path. The shared
# lambda_role already grants DynamoDB on the whole xomtracks* prefix (covers the
# new xomtracks-request-log table) + SSM on /xomtracks/* + /xomify/api/*, so NO
# IAM change is needed. See docs/features/xomtracks-xomify-merge/PLAN.md WS6.
########################################

locals {
  admin_lambdas = [
    {
      name          = "requests"
      description   = "List pending phone-link requests for the admin queue (admin-gated) -- GET /admin/requests"
      path_part     = "requests"
      http_method   = "GET"
      authorization = "NONE"
    },
    {
      name          = "approve"
      description   = "Approve a pending link request -- creates the real link + marks approved (admin-gated) -- POST /admin/approve"
      path_part     = "approve"
      http_method   = "POST"
      authorization = "NONE"
    },
    {
      name          = "deny"
      description   = "Deny a pending link request -- marks denied, no link (admin-gated) -- POST /admin/deny"
      path_part     = "deny"
      http_method   = "POST"
      authorization = "NONE"
    },
    # ---- Admin portal v1 (WS6) ----
    {
      name          = "users"
      description   = "User directory -- everyone who signed into Xomtracks (admin-gated) -- GET /admin/users"
      path_part     = "users"
      http_method   = "GET"
      authorization = "NONE"
    },
    {
      name          = "userfeed"
      description   = "Impersonation / view-as a target user's feed, read-only (admin-gated) -- GET /admin/user-feed"
      path_part     = "user-feed"
      http_method   = "GET"
      authorization = "NONE"
    },
    {
      name          = "calls"
      description   = "Calls & errors dashboard -- aggregates the TTL'd request log (admin-gated) -- GET /admin/calls"
      path_part     = "calls"
      http_method   = "GET"
      authorization = "NONE"
    },
    {
      name          = "tokens"
      description   = "List ingest tokens per owner, metadata only (admin-gated) -- GET /admin/tokens"
      path_part     = "tokens"
      http_method   = "GET"
      authorization = "NONE"
    },
    {
      name          = "revoketoken"
      description   = "Admin override revoke of any user's ingest token {tokenHash} (admin-gated) -- POST /admin/revoke-token"
      path_part     = "revoke-token"
      http_method   = "POST"
      authorization = "NONE"
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
