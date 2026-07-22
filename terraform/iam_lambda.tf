# ============================================
# Shared assume role policy for Lambda
# ============================================

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# NOTE: the authorizer Lambda execution role was removed when authed routes
# moved to the native COGNITO_USER_POOLS authorizer -- there is no
# authorizer Lambda to run. API Gateway validates Cognito JWTs against the
# shared xomware_users pool directly (see data_cognito.tf, apigateway.tf).

# ============================================
# API Lambda IAM Role (auth_login, shares_ingest, shares_list,
# shares_match_override)
#
# UNLIKE xomforms (which has zero third-party API secrets), xomtracks'
# handlers read live SSM parameters at runtime via
# lambdas/common/ssm_helpers.py (Spotify creds, SoundCloud client_id,
# ingest bearer key, API_SECRET_KEY) -- so this role, unlike xomforms'
# lambda_role, needs ssm:GetParameter* scoped to /xomtracks/*, matching
# xomify-infrastructure's api lambda role pattern.
# ============================================

data "aws_iam_policy_document" "api_lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.app_name}-lambda-exec"
  tags               = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-lambda-exec" }))
  assume_role_policy = data.aws_iam_policy_document.api_lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_role_policy" {
  # SSM -- Spotify/SoundCloud creds, ingest bearer key, API_SECRET_KEY
  # (see ssm.tf). Scoped to this app's own SSM namespace only.
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:parameter/${var.app_name}/*"
    ]
  }

  # CloudWatch Logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:log-group:/aws/lambda/${var.app_name}*",
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:log-group:/aws/lambda/${var.app_name}*:*"
    ]
  }

  # KMS -- for DynamoDB encryption
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = [
      aws_kms_key.web_app.arn
    ]
  }

  # Lambda -- invoke own functions
  statement {
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction",
      "lambda:GetFunction"
    ]
    resources = [
      "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:function:${var.app_name}*"
    ]
  }

  # API Gateway -- execute API
  statement {
    effect  = "Allow"
    actions = ["execute-api:Invoke"]
    resources = [
      "${module.api.rest_api_execution_arn}/*/*/*"
    ]
  }

  # X-Ray Tracing
  statement {
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets"
    ]
    resources = ["*"]
  }

  # DynamoDB -- scoped to app tables only
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchWriteItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable"
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:table/${var.app_name}*",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:table/${var.app_name}*/index/*"
    ]
  }
}

resource "aws_iam_role_policy" "lambda_role_policy" {
  name   = "${var.app_name}-lambda-role-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_role_policy.json
}

# ============================================
# Cron Lambda IAM Role (token-keepalive, rolling-playlists, matching-sweep)
#
# Same shape as the API lambda role, minus API Gateway execute-api (crons
# are EventBridge-invoked, never called through the API). PLUS
# ssm:PutParameter scoped to the two rolling-playlist-id params only (see
# ssm.tf) -- the rolling-playlists cron persists `rollingInPlaylistId`/
# `rollingOutPlaylistId` back to SSM at runtime once it exists (NOT written
# yet -- see lambdas_cron.tf's header comment).
# ============================================

resource "aws_iam_role" "cron_lambda_role" {
  name               = "${var.app_name}-cron-lambda-exec"
  tags               = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-cron-lambda-exec" }))
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "cron_lambda_role_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:parameter/${var.app_name}/*"
    ]
  }

  # Scoped write access -- ONLY the two rolling-playlist-id parameters,
  # not the whole /xomtracks/* namespace (least privilege: this role never
  # needs to write Spotify creds, the ingest key, etc).
  statement {
    effect = "Allow"
    actions = [
      "ssm:PutParameter"
    ]
    resources = [
      aws_ssm_parameter.rolling_in_playlist_id.arn,
      aws_ssm_parameter.rolling_out_playlist_id.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:log-group:/aws/lambda/${var.app_name}-cron*",
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:log-group:/aws/lambda/${var.app_name}-cron*:*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = [
      aws_kms_key.web_app.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchWriteItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable"
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:table/${var.app_name}*",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:table/${var.app_name}*/index/*"
    ]
  }
}

resource "aws_iam_role_policy" "cron_lambda_role_policy" {
  name   = "${var.app_name}-cron-lambda-role-policy"
  role   = aws_iam_role.cron_lambda_role.id
  policy = data.aws_iam_policy_document.cron_lambda_role_policy.json
}
