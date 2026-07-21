# SPOTIFY -- xomtracks' OWN app credentials (self-contained per PLAN.md
# Option 3, NOT xomify's -- deliberately not cross-referencing
# /xomify/spotify/* even though that param exists and is populated. PLAN.md
# is explicit that xomtracks needs its own registered Spotify app ("clean
# app boundary with zero risk to the deployed xomify" -- sharing xomify's
# client_id/secret would put every xomtracks API call under xomify's
# Spotify app dashboard/quota/scopes, exactly what Option 3 was chosen to
# avoid).
#
# PLACEHOLDER value, NOT sourced from a variable -- an earlier version of
# this file sourced these from `var.spotify_client_id`/`var.spotify_client_secret`
# with no Terraform default, wired via TF_VAR_* from GitHub secrets that
# were never set; those resolved to an empty string in CI, which
# `terraform plan`/`validate` accepted but AWS SSM's real `PutParameter`
# API rejected outright (`ValidationException: Value must have length >=
# 1`) -- the exact failure from the first apply attempt. A real secret
# requires a human to register a Spotify app for Xomtracks; Terraform
# can't generate one. `ignore_changes = [value]` so this placeholder is
# only ever written ONCE -- Dom sets the real value out-of-band via the AWS
# CLI (see xomtracks-infrastructure's PR description for the exact
# commands) and subsequent `terraform apply` runs never fight it back to
# the placeholder.
resource "aws_ssm_parameter" "spotify_client_id" {
  name        = "/${var.app_name}/spotify/CLIENT_ID"
  description = "Xomtracks' own Spotify Web API Client ID -- PLACEHOLDER until Dom sets the real value (see PR description for the aws ssm put-parameter command)"
  type        = "SecureString"
  value       = "REPLACE_ME"

  lifecycle { ignore_changes = [tags, tags_all, value] }
}

resource "aws_ssm_parameter" "spotify_client_secret" {
  name        = "/${var.app_name}/spotify/CLIENT_SECRET"
  description = "Xomtracks' own Spotify Web API Client Secret -- PLACEHOLDER until Dom sets the real value (see PR description for the aws ssm put-parameter command)"
  type        = "SecureString"
  value       = "REPLACE_ME"

  lifecycle { ignore_changes = [tags, tags_all, value] }
}

# SOUNDCLOUD -- MIRRORED from xomcloud's existing scraped client_id, not a
# new secret. Unlike Spotify's per-app OAuth client_id/secret, this
# "scraped" credential (extracted from SoundCloud's own web client, per
# xomcloud-backend/lambdas/common/config.py) isn't a registered, per-app
# identity -- it's effectively a public token SoundCloud's own web app
# uses, which is exactly why PLAN.md's Approach section says to resolve
# SoundCloud metadata "via scraped soundcloud_client_id (**xomcloud
# path**)" rather than "xomtracks' own SoundCloud app" the way it does for
# Spotify. Reusing the value xomcloud already has (confirmed live,
# non-empty, populated 2026-05-21) needs zero Dom action and creates no
# new secret to manage. Materialized under xomtracks' OWN SSM path (not
# read directly from /xomcloud/* at Lambda runtime) so the already-shipped
# xomtracks-backend code (lambdas/common/ssm_helpers.py expects
# /xomtracks/soundcloud/CLIENT_ID) and this app's IAM scoping
# (ssm:GetParameter limited to /xomtracks/*) both need zero changes.
# Deliberately NOT `ignore_changes = [value]` -- if xomcloud re-scrapes a
# rotated client_id, the next `terraform apply` here picks it up
# automatically rather than silently going stale.
data "aws_ssm_parameter" "xomcloud_soundcloud_client_id" {
  name = "/xomcloud/soundcloud/CLIENT_ID"
}

resource "aws_ssm_parameter" "soundcloud_client_id" {
  name        = "/${var.app_name}/soundcloud/CLIENT_ID"
  description = "Scraped SoundCloud client_id for metadata resolution -- mirrored from xomcloud's existing credential"
  type        = "SecureString"
  value       = data.aws_ssm_parameter.xomcloud_soundcloud_client_id.value

  lifecycle { ignore_changes = [tags, tags_all] }
}

# INGEST -- the scoped bearer key the local extractor sends to
# POST /shares/ingest. Read at runtime by lambdas/shares_ingest/handler.py
# via require_ingest_bearer_key(); NOT a Cognito-validated route.
#
# GENERATED in-stack (random.tf) -- purely internal, shared-secret-style
# credential with no external registration step, so there's no reason to
# make Dom invent/supply one. The SAME SSM param path
# (/xomtracks/ingest/BEARER_KEY) the already-shipped backend code reads is
# still the source of truth; Dom's one remaining step is reading the
# generated value back out to configure the extractor's `--bearer-key`
# (see PR description for the exact `aws ssm get-parameter` command --
# this is a READ, not a value Dom has to choose).
resource "aws_ssm_parameter" "ingest_bearer_key" {
  name        = "/${var.app_name}/ingest/BEARER_KEY"
  description = "Scoped bearer key for the extractor's POST /shares/ingest push -- generated in-stack"
  type        = "SecureString"
  value       = random_password.ingest_bearer_key.result

  lifecycle { ignore_changes = [tags, tags_all] }
}

# API -- HS256 signing key for auth_login's minted JWT. GENERATED in-stack
# (random.tf), same rationale as the ingest bearer key -- this key is only
# ever consumed server-side (auth_login mints, nothing else currently
# verifies it independently -- see the auth_login/authorizer design note
# in EXECUTION_LOG.md), so there's no external party that needs to choose
# or be told this value.
resource "aws_ssm_parameter" "api_secret_key" {
  name        = "/${var.app_name}/api/API_SECRET_KEY"
  description = "HS256 signing key for auth_login's minted JWT -- generated in-stack"
  type        = "SecureString"
  value       = random_password.api_secret_key.result

  lifecycle { ignore_changes = [tags, tags_all] }
}

resource "aws_ssm_parameter" "api_id" {
  name        = "/${var.app_name}/api/API_ID"
  description = "API Gateway ID"
  type        = "SecureString"
  value       = module.api.rest_api_id

  lifecycle { ignore_changes = [tags, tags_all] }
}

# ============================================
# Persisted rolling playlist ids
#
# Per PLAN.md Phase 4.1 these were originally sketched as living on
# xomtracks' own user/config DynamoDB row; this build-out phase instead
# persists them in SSM (both directions get their own param), matching
# the explicit instruction for this pass. Values start empty -- the
# rolling-playlists cron (not written yet, see lambdas_cron.tf) creates
# each playlist on its first successful run and PUTs the resulting id back
# via `ssm:PutParameter` (see iam_lambda.tf's cron_lambda_role_policy,
# scoped to exactly these two ARNs). `ignore_changes = [value]` so
# Terraform doesn't fight the Lambda-managed runtime value on subsequent
# plans/applies once the cron starts writing to it.
#
# NOTE: "unset" (not "") is a real, non-empty placeholder -- these two
# never hit the empty-string SSM validation error the other five did.
# ============================================

resource "aws_ssm_parameter" "rolling_in_playlist_id" {
  name        = "/${var.app_name}/playlists/ROLLING_IN_PLAYLIST_ID"
  description = "Spotify playlist id for the rolling 'last 30 days' shared-with-me playlist -- runtime-managed by the rolling-playlists cron"
  type        = "SecureString"
  value       = "unset"

  lifecycle {
    ignore_changes = [tags, tags_all, value]
  }
}

resource "aws_ssm_parameter" "rolling_out_playlist_id" {
  name        = "/${var.app_name}/playlists/ROLLING_OUT_PLAYLIST_ID"
  description = "Spotify playlist id for the rolling 'last 30 days' shared-by-me playlist -- runtime-managed by the rolling-playlists cron"
  type        = "SecureString"
  value       = "unset"

  lifecycle {
    ignore_changes = [tags, tags_all, value]
  }
}
