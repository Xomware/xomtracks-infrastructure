########################################
# Xomtracks Playlists API Lambda(s)
#
# On-the-spot playlist builder: POST /playlists/create (authed via the
# native COGNITO_USER_POOLS authorizer against the shared xomware_users
# pool, same as the shares list/match-override routes). Backs the feed's
# multi-select "make your own playlist from history" action -- takes a
# selection of shareIds/trackIds + a name and creates a public Spotify
# playlist on Dom's service account (single-service-account model).
#
# Mirrors lambda.tf's shares block exactly (stub zip now, real code via CI
# once xomtracks-backend/lambdas/playlists_create/ is merged). Uses the same
# API lambda role (needs SSM Spotify creds + DynamoDB read on
# xomtracks-shares/users), NOT the cron role.
#
# Folder -> function name: lambdas/playlists_create -> xomtracks-playlists-create
# (deploy-backend.yml's first-underscore split: DOMAIN=playlists, REST=create).
########################################

locals {
  playlists_lambdas = [
    {
      name          = "create"
      description   = "On-the-spot: build a public Spotify playlist from a hand-picked selection (authed)"
      path_part     = "create"
      http_method   = "POST"
      authorization = "COGNITO_USER_POOLS"
    },
  ]
}

resource "aws_lambda_function" "playlists" {
  for_each         = { for lambda in local.playlists_lambdas : lambda.name => lambda }
  function_name    = "${var.app_name}-playlists-${each.value.name}"
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

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-playlists-${each.value.name}", "lambda_type" = "playlists" }))

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
