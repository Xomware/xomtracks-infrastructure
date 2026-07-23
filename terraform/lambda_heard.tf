########################################
# Xomtracks "heard" API Lambda -- per-(track, user) LISTEN tracking. Any
# signed-in Xomware member marks a song heard/unheard; the flag is keyed by a
# normalized SONG identity (trackKey) so it follows the SONG across all of its
# share instances, NOT per-share (same identity model as ratings). Backs
# xomtracks-backend's heard_set handler and the inline `heard` enrichment on
# /shares/list + /me/shares (the frontend's "unheard" filter).
#
# The route is authed via the native COGNITO_USER_POOLS authorizer against the
# shared xomware_users pool, same as the ratings / shares list / me routes. Uses
# the same API lambda role (aws_iam_role.lambda_role) -- it already grants
# DynamoDB read/write on the whole `xomtracks*` table ARN prefix (see
# iam_lambda.tf), which COVERS the new xomtracks-heard table, and SSM on
# /xomtracks/* -- so NO IAM change is needed here, same as ratings.
#
# Mirrors lambda_ratings.tf exactly (stub zip now, real code via CI once the
# backend handler folder is merged).
#
# Folder -> function name (deploy-backend.yml first-underscore split:
# DOMAIN=heard, REST=set):
#   lambdas/heard_set -> xomtracks-heard-set
#
# ROUTE NOTE (2-path-level module constraint): the api-gateway-service module
# (v2.7.0) supports exactly two path levels -- a service `path_prefix` (`heard`)
# and one `path_part` per endpoint beneath it -- so it cannot attach a method to
# the bare `heard` resource. Same constraint that made `GET /shares` into
# `GET /shares/list` and `POST /ratings` into `POST /ratings/set`. Resolved the
# same way: the endpoint is `POST /heard/set`. The handler reads the Cognito
# authorizer context + body only, not the URL path, so this needs ZERO backend
# code changes -- callers hit `/heard/set`.
########################################

locals {
  heard_lambdas = [
    {
      name          = "set"
      description   = "Upsert the caller's heard flag for a song; return the fresh per-caller heard state (authed) -- POST /heard/set"
      path_part     = "set"
      http_method   = "POST"
      authorization = "COGNITO_USER_POOLS"
    },
  ]
}

resource "aws_lambda_function" "heard" {
  for_each         = { for lambda in local.heard_lambdas : lambda.name => lambda }
  function_name    = "${var.app_name}-heard-${each.value.name}"
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

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-heard-${each.value.name}", "lambda_type" = "heard" }))

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
