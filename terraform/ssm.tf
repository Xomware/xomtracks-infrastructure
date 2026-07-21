# SPOTIFY -- xomtracks' OWN app credentials (self-contained per PLAN.md
# Option 3, not xomify's).
resource "aws_ssm_parameter" "spotify_client_id" {
  name        = "/${var.app_name}/spotify/CLIENT_ID"
  description = "Xomtracks' own Spotify Web API Client ID"
  type        = "SecureString"
  value       = var.spotify_client_id

  lifecycle { ignore_changes = [tags, tags_all] }
}

resource "aws_ssm_parameter" "spotify_client_secret" {
  name        = "/${var.app_name}/spotify/CLIENT_SECRET"
  description = "Xomtracks' own Spotify Web API Client Secret"
  type        = "SecureString"
  value       = var.spotify_client_secret

  lifecycle { ignore_changes = [tags, tags_all] }
}

# SOUNDCLOUD -- scraped client_id (xomcloud pattern), used by the
# cross-platform matcher to resolve SoundCloud metadata.
resource "aws_ssm_parameter" "soundcloud_client_id" {
  name        = "/${var.app_name}/soundcloud/CLIENT_ID"
  description = "Scraped SoundCloud client_id for metadata resolution"
  type        = "SecureString"
  value       = var.soundcloud_client_id

  lifecycle { ignore_changes = [tags, tags_all] }
}

# INGEST -- the scoped bearer key the local extractor sends to
# POST /shares/ingest. Read at runtime by lambdas/shares_ingest/handler.py
# via require_ingest_bearer_key(); NOT a Cognito-validated route.
resource "aws_ssm_parameter" "ingest_bearer_key" {
  name        = "/${var.app_name}/ingest/BEARER_KEY"
  description = "Scoped bearer key for the extractor's POST /shares/ingest push"
  type        = "SecureString"
  value       = var.ingest_bearer_key

  lifecycle { ignore_changes = [tags, tags_all] }
}

# API -- HS256 signing key for auth_login's minted JWT.
resource "aws_ssm_parameter" "api_secret_key" {
  name        = "/${var.app_name}/api/API_SECRET_KEY"
  description = "HS256 signing key for auth_login's minted JWT"
  type        = "SecureString"
  value       = var.api_secret_key

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
