########################################
# Xomtracks "ratings" API Lambdas -- whole-group song ratings. Any signed-in
# Xomware member can rate a song 1-5; a song shows its aggregate {avg, count}
# plus the caller's own rating. Ratings are keyed by a normalized SONG identity
# (trackKey) so they follow the SONG across all of its share instances, not
# per-share. Backs xomtracks-backend's ratings_set / ratings_get handlers and
# the inline `rating` enrichment on /shares/list + /me/shares.
#
# Both routes are authed via the native COGNITO_USER_POOLS authorizer against
# the shared xomware_users pool, same as the shares list / me / playlists
# routes. Uses the same API lambda role (aws_iam_role.lambda_role) -- it already
# grants DynamoDB read/write on the whole `xomtracks*` table ARN prefix (see
# iam_lambda.tf), which COVERS the new xomtracks-ratings table, and SSM on
# /xomtracks/* -- so NO IAM change is needed here, same as playlists_create /
# the me lambdas.
#
# Mirrors lambda_me.tf exactly (stub zip now, real code via CI once the backend
# handler folders are merged).
#
# Folder -> function name (deploy-backend.yml first-underscore split:
# DOMAIN=ratings, REST=<rest>):
#   lambdas/ratings_set  -> xomtracks-ratings-set
#   lambdas/ratings_get  -> xomtracks-ratings-get
#   lambdas/ratings_list -> xomtracks-ratings-list
#
# ROUTE NOTE (2-path-level module constraint): the api-gateway-service module
# (v2.7.0) supports exactly two path levels -- a service `path_prefix`
# (`ratings`) and one `path_part` per endpoint beneath it -- so it cannot attach
# a method to the bare `ratings` resource. This is the SAME constraint that made
# `GET /shares` into `GET /shares/list`. Resolved the same way: the endpoints
# are `POST /ratings/set` and `GET /ratings/get`. The handlers read the Cognito
# authorizer context + body/querystring only, not the URL path, so this needs
# ZERO backend code changes -- callers hit `/ratings/set` and `/ratings/get`.
########################################

locals {
  ratings_lambdas = [
    {
      name          = "set"
      description   = "Upsert the caller's 1-5 rating for a song; return the aggregate {avg,count,myRating} (authed) -- POST /ratings/set"
      path_part     = "set"
      http_method   = "POST"
      authorization = "COGNITO_USER_POOLS"
    },
    {
      name          = "get"
      description   = "Batch aggregate ratings + the caller's own rating per trackKey (authed) -- GET /ratings/get?trackKeys=a,b,c"
      path_part     = "get"
      http_method   = "GET"
      authorization = "COGNITO_USER_POOLS"
    },
    {
      name          = "list"
      description   = "Every track the caller has rated, across BOTH directions, with track info + rating value (authed) -- GET /ratings/list"
      path_part     = "list"
      http_method   = "GET"
      authorization = "COGNITO_USER_POOLS"
    },
  ]
}

resource "aws_lambda_function" "ratings" {
  for_each         = { for lambda in local.ratings_lambdas : lambda.name => lambda }
  function_name    = "${var.app_name}-ratings-${each.value.name}"
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

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-ratings-${each.value.name}", "lambda_type" = "ratings" }))

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
