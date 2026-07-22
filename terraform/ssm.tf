# SPOTIFY -- MIRRORED from xomify's existing registered Spotify app
# credentials, NOT a separate xomtracks app. This reverses the earlier
# "Option 3 / self-contained own app" decision: Dom is explicitly opting
# to REUSE xomify's Spotify app creds (client_id/secret) rather than
# register a second Spotify app for xomtracks. Reuse is preferred -- it
# means zero Dom action (no new app to register, no REPLACE_ME to fill in)
# and one Spotify app dashboard to manage. Both apps are Dom's own personal
# projects under the same Spotify developer account, so there's no
# cross-tenant concern.
#
# Sourced exactly like the SoundCloud credential below is sourced from
# xomcloud: a cross-app `data "aws_ssm_parameter"` read of the existing,
# populated `/xomify/spotify/*` params (confirmed live, non-empty, set
# 2025-03-03). Materialized under xomtracks' OWN SSM path
# (/xomtracks/spotify/*) -- read directly by the already-shipped
# xomtracks-backend code (lambdas/common expects /xomtracks/spotify/*) and
# covered by this app's existing IAM scoping (ssm:GetParameter limited to
# /xomtracks/*), so neither the backend nor IAM needs any change.
#
# Deliberately NOT `ignore_changes = [value]` -- if xomify ever rotates its
# Spotify client secret, the next `terraform apply` here picks up the new
# value automatically rather than silently going stale (same rationale as
# SoundCloud's mirror below).
data "aws_ssm_parameter" "xomify_spotify_client_id" {
  name = "/xomify/spotify/CLIENT_ID"
}

data "aws_ssm_parameter" "xomify_spotify_client_secret" {
  name = "/xomify/spotify/CLIENT_SECRET"
}

resource "aws_ssm_parameter" "spotify_client_id" {
  name        = "/${var.app_name}/spotify/CLIENT_ID"
  description = "Spotify Web API Client ID -- mirrored from xomify's existing registered app credential"
  type        = "SecureString"
  value       = data.aws_ssm_parameter.xomify_spotify_client_id.value

  lifecycle { ignore_changes = [tags, tags_all] }
}

resource "aws_ssm_parameter" "spotify_client_secret" {
  name        = "/${var.app_name}/spotify/CLIENT_SECRET"
  description = "Spotify Web API Client Secret -- mirrored from xomify's existing registered app credential"
  type        = "SecureString"
  value       = data.aws_ssm_parameter.xomify_spotify_client_secret.value

  lifecycle { ignore_changes = [tags, tags_all] }
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
