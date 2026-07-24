########################################
# Xomtracks API Lambdas -- one per handler in xomtracks-backend/lambdas/.
#
# `authorization` on an endpoint is carried through to apigateway.tf.
# Authed routes use the native COGNITO_USER_POOLS authorizer (validated
# directly by API Gateway against the shared xomware_users pool -- see
# data_cognito.tf and the module block in apigateway.tf, matching
# meals-infrastructure / xomforms-infrastructure). Public routes override
# to NONE.
#
# PATH DESIGN NOTE: the api-gateway-service module (v2.7.0) supports
# exactly two path levels -- a service `path_prefix` and one `path_part`
# per endpoint underneath it (see its endpoints.tf: `service` resource is
# the parent, `endpoint` resources are its direct children only, no
# deeper nesting). PLAN.md's original route sketch used a 3-level path
# (`/shares/{shareId}/match-override`), which this module cannot express.
# Resolved by using API Gateway's `{shareId}` path-parameter syntax
# directly as the match-override endpoint's `path_part` under the `shares`
# prefix -- i.e. `POST /shares/{shareId}` IS the match-override action (a
# share resource has exactly one thing you can POST to it right now).
# xomtracks-backend's shares_match_override/handler.py already reads
# `shareId` from `pathParameters` -- it does not hardcode or care about
# the URL string beyond that parameter key, so this required ZERO backend
# code changes. `GET /shares` similarly became `GET /shares/list` (the
# handler reads querystring/authorizer-context only, not the path).
########################################

locals {
  auth_lambdas = [
    {
      name          = "login"
      description   = "Mint per-user Xomtracks JWT from a Spotify access token (public)"
      path_part     = "login"
      http_method   = "POST"
      authorization = "NONE"
    },
    # Per-user Spotify OAuth (self-serve foundation Phase 2). BOTH are
    # Cognito-authed (unlike the public /auth/login) -- the caller's Cognito
    # identity (email + sub) binds the CSRF state and owns the stored refresh
    # token. Folder -> function name via deploy-backend.yml's first-underscore
    # split: lambdas/auth_spotify_login -> xomtracks-auth-spotify_login,
    # lambdas/auth_spotify_callback -> xomtracks-auth-spotify_callback (matches
    # `${app}-auth-${name}` below). Routes: POST /auth/spotify-login,
    # POST /auth/spotify-callback (module 2-level path: prefix `auth` +
    # path_part). No IAM change -- lambda_role already grants SSM read on
    # /xomtracks/* (Spotify creds + REDIRECT_URI) and DynamoDB on xomtracks-users.
    {
      name          = "spotify_login"
      description   = "Start per-user Spotify OAuth -- return the authorize URL + stamp a CSRF state (authed)"
      path_part     = "spotify-login"
      http_method   = "POST"
      authorization = "COGNITO_USER_POOLS"
    },
    {
      name          = "spotify_callback"
      description   = "Finish per-user Spotify OAuth -- verify state, exchange code, store the owner's refresh token (authed)"
      path_part     = "spotify-callback"
      http_method   = "POST"
      authorization = "COGNITO_USER_POOLS"
    },
  ]

  # Per-user extractor ingest tokens (self-serve foundation Phase 3). BOTH are
  # Cognito-authed -- the caller's Cognito sub is the ownerId the minted token is
  # bound to (and the scope that revoke checks). Folder -> function name via
  # deploy-backend.yml's first-underscore split: lambdas/ingesttokens_create ->
  # xomtracks-ingesttokens-create, lambdas/ingesttokens_revoke ->
  # xomtracks-ingesttokens-revoke (matches `${app}-ingesttokens-${name}` below).
  # Routes: POST /ingest-tokens/create, POST /ingest-tokens/revoke (module
  # 2-level path: prefix `ingest-tokens` + path_part). No IAM change -- the
  # lambda_role already grants DynamoDB on xomtracks-ingest-tokens (name matches
  # the xomtracks* prefix); the mint/revoke handlers use no SSM.
  ingest_tokens_lambdas = [
    {
      name          = "create"
      description   = "Mint a per-user extractor ingest token -- return the plaintext once, store only its hash (authed)"
      path_part     = "create"
      http_method   = "POST"
      authorization = "COGNITO_USER_POOLS"
    },
    {
      name          = "revoke"
      description   = "Revoke one of the caller's ingest tokens by hash (or plaintext), scoped to the caller's ownerId (authed)"
      path_part     = "revoke"
      http_method   = "POST"
      authorization = "COGNITO_USER_POOLS"
    },
  ]

  shares_lambdas = [
    {
      name          = "ingest"
      description   = "Extractor push endpoint -- auth via ingest token (per-user) or legacy SSM key, resolved in-handler, NOT Cognito"
      path_part     = "ingest"
      http_method   = "POST"
      authorization = "NONE"
    },
    {
      name          = "list"
      description   = "Browse shares by direction + time window (authed)"
      path_part     = "list"
      http_method   = "GET"
      authorization = "COGNITO_USER_POOLS"
    },
    {
      name          = "recent"
      description   = "Compact most-recent shares (shared-with-me + shared-by-me) for the xomware.com hub widget (authed) -- GET /shares/recent?limit=5"
      path_part     = "recent"
      http_method   = "GET"
      authorization = "COGNITO_USER_POOLS"
    },
    {
      name          = "match_override"
      description   = "Manual match-override for a share -- POST /shares/{shareId} (authed)"
      path_part     = "{shareId}"
      http_method   = "POST"
      authorization = "COGNITO_USER_POOLS"
    },
  ]
}

resource "aws_lambda_function" "auth" {
  for_each         = { for lambda in local.auth_lambdas : lambda.name => lambda }
  function_name    = "${var.app_name}-auth-${each.value.name}"
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

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-auth-${each.value.name}", "lambda_type" = "auth" }))

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

resource "aws_lambda_function" "ingest_tokens" {
  for_each         = { for lambda in local.ingest_tokens_lambdas : lambda.name => lambda }
  function_name    = "${var.app_name}-ingesttokens-${each.value.name}"
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

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-ingesttokens-${each.value.name}", "lambda_type" = "ingest_tokens" }))

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

resource "aws_lambda_function" "shares" {
  for_each         = { for lambda in local.shares_lambdas : lambda.name => lambda }
  function_name    = "${var.app_name}-shares-${each.value.name}"
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

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-shares-${each.value.name}", "lambda_type" = "shares" }))

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
