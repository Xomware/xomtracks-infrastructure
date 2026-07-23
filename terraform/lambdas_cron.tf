########################################
# Xomtracks cron Lambdas -- EventBridge-scheduled, mirrors
# xomify-infrastructure's lambdas_cron.tf (Lambda + schedule rule + target
# + invoke permission bundled per-cron in one file).
#
# FLAGGED: none of these three Lambdas' Python source exists yet in
# xomtracks-backend -- lambdas/common/matching.py, spotify.py, and
# playlist.py (the logic each cron would call) are built and unit-tested,
# but no `cron_token_keepalive/`, `cron_rolling_playlists/`, or
# `cron_matching_sweep/` handler.py has been written. Same stub-zip pattern
# every freshly-scaffolded Lambda in this repo uses -- the Terraform
# resource + schedule is real and applyable now (references the generic
# stub zip, deploys real code later via CI), but these three cron Lambdas
# will run stub code until their handlers are written.
#
# AUTO-HEARD (added later): reads Dom's Spotify recently-played via the same
# service token the playlists crons use (Dom's, in xomtracks-users) and marks
# matching tracks heard for Dom in xomtracks-heard. Uses the SAME
# cron_lambda_role -- it already grants DynamoDB read/write on the whole
# `xomtracks*` ARN prefix (covers xomtracks-heard) and SSM read on /xomtracks/*
# (Spotify creds) -- so NO IAM change is needed. Requires the
# `user-read-recently-played` scope on the reused xomify refresh token (verified
# present); a scope regression surfaces as a 403 that fails the cron loud.
#
# 3.3 (matching trigger) resolves PLAN.md's Open Question in favor of a
# periodic sweep of `pending` rows over a post-ingest synchronous Lambda
# invoke -- simpler infra (no ingest-handler-invokes-matcher wiring), and
# naturally retries transient resolver failures (SoundCloud/iTunes down,
# Spotify rate limit) on the next sweep rather than needing its own retry
# logic.
########################################

locals {
  cron_lambdas = [
    {
      name             = "token-keepalive"
      description      = "Monthly refresh of xomtracks' own Spotify service-account token"
      cron_schedule    = "cron(0 4 15 * ? *)"
      cron_description = "Triggers xomtracks token keepalive on the 15th of each month at 4 AM UTC"
    },
    {
      name             = "rolling-playlists"
      description      = "Weekly rebuild of both rolling 'last 30 days' playlists (in + out)"
      cron_schedule    = "cron(0 11 ? * SAT *)"
      cron_description = "Triggers xomtracks rolling playlist rebuild every Saturday at 7 AM Eastern (aligned with xomify's release radar cadence)"
    },
    {
      name             = "matching-sweep"
      description      = "Periodic sweep of pending shares -- resolves cross-platform matches (Spotify/SoundCloud/Apple -> Spotify)"
      cron_schedule    = "rate(10 minutes)"
      cron_description = "Triggers a matching sweep of pending shares every 10 minutes"
    },
    {
      name             = "auto-heard"
      description      = "Reads Dom's Spotify recently-played and auto-marks matching tracks heard for Dom (Dom-only; per-user OAuth is a fast-follow)"
      cron_schedule    = "rate(30 minutes)"
      cron_description = "Triggers the auto-heard job every 30 minutes (Spotify recently-played -> heard for Dom)"
    },
  ]
}

resource "aws_lambda_function" "cron" {
  for_each         = { for lambda in local.cron_lambdas : lambda.name => lambda }
  function_name    = "${var.app_name}-cron-${each.value.name}"
  description      = each.value.description
  filename         = "./templates/lambda_stub.zip"
  source_code_hash = filebase64sha256("./templates/lambda_stub.zip")
  handler          = "handler.handler"
  layers           = [aws_lambda_layer_version.lambda_layer.arn]
  runtime          = var.lambda_runtime
  memory_size      = var.lambda_memory_size
  timeout          = var.lambda_timeout
  role             = aws_iam_role.cron_lambda_role.arn

  environment {
    variables = local.lambda_variables
  }

  tracing_config {
    mode = var.lambda_trace_mode
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-cron-${each.value.name}", "lambda_type" = "cron" }))

  lifecycle {
    ignore_changes = [
      description,
      filename,
      source_code_hash,
      layers
    ]
  }

  depends_on = [
    aws_iam_role_policy.cron_lambda_role_policy,
    aws_iam_role.cron_lambda_role
  ]
}

resource "aws_cloudwatch_event_rule" "cron_schedule" {
  for_each            = { for lambda in local.cron_lambdas : lambda.name => lambda }
  name                = "${var.app_name}-${each.value.name}-schedule"
  description         = each.value.cron_description
  schedule_expression = each.value.cron_schedule
}

resource "aws_cloudwatch_event_target" "cron_target" {
  for_each  = { for lambda in local.cron_lambdas : lambda.name => lambda }
  rule      = aws_cloudwatch_event_rule.cron_schedule[each.value.name].name
  target_id = "${var.app_name}-${each.value.name}-target-id"
  arn       = aws_lambda_function.cron[each.value.name].arn
}

resource "aws_lambda_permission" "allow_cloudwatch_cron" {
  for_each      = { for lambda in local.cron_lambdas : lambda.name => lambda }
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cron[each.value.name].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cron_schedule[each.value.name].arn
}
