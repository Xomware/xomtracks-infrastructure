########################################
# 1. xomtracks-shares
# PK: shareId (uuid5 of messageGuid+sourceUrl -- see
#     xomtracks-backend/lambdas/common/shares_dynamo.py::derive_share_id)
# GSI-1 direction-messageDate-index: PK direction, SK messageDate -- MVP
#   time-window-per-direction browse query (GET /shares/list).
# GSI-2 sharerHandle-messageDate-index: PK sharerHandle, SK messageDate --
#   RESERVED for the by-sharer fast-follow (FF.2). Provisioned now (cheap),
#   not queried by any handler yet. Sparse index: `direction=out` shares
#   (Dom is the sender) have no sharerHandle attribute at all -- the
#   backend deliberately omits it rather than writing NULL (DynamoDB
#   rejects NULL on a GSI key attribute), so those rows are correctly
#   absent from this index rather than erroring on write.
# GSI-3 ownerDirection-messageDate-index: PK ownerDirection (`<ownerId>#<direction>`),
#   SK messageDate -- the OWNER-SCOPED time-window browse that makes the app
#   multi-tenant (self-serve foundation Phase 1). Added ONLINE (additive): on
#   PAY_PER_REQUEST the backfill absorbs no provisioned capacity, and the index
#   starts empty/sparse until the ownerId backfill stamps the ~325 legacy rows.
#   Legacy readers keep GSI-1 (direction) as the instant-rollback path. Sparse
#   like GSI-2: rows without an ownerId (pre-backfill) omit ownerDirection and
#   are simply absent from this index. See
#   docs/features/xomtracks-selfserve/PLAN.md Phase 1.
########################################
resource "aws_dynamodb_table" "shares" {
  name           = "${var.app_name}-shares"
  billing_mode   = "PAY_PER_REQUEST"
  read_capacity  = 0
  write_capacity = 0
  hash_key       = "shareId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "shareId"
    type = "S"
  }

  attribute {
    name = "direction"
    type = "S"
  }

  attribute {
    name = "messageDate"
    type = "N"
  }

  attribute {
    name = "sharerHandle"
    type = "S"
  }

  attribute {
    name = "ownerDirection"
    type = "S"
  }

  global_secondary_index {
    name            = "direction-messageDate-index"
    hash_key        = "direction"
    range_key       = "messageDate"
    projection_type = "ALL"
  }

  # Reserved for FF.2 (by-sharer fast-follow) -- see header comment.
  global_secondary_index {
    name            = "sharerHandle-messageDate-index"
    hash_key        = "sharerHandle"
    range_key       = "messageDate"
    projection_type = "ALL"
  }

  # GSI-3: owner-scoped feed (multi-tenant Phase 1) -- see header comment.
  # Additive/online add; sparse until the ownerId backfill runs.
  global_secondary_index {
    name            = "ownerDirection-messageDate-index"
    hash_key        = "ownerDirection"
    range_key       = "messageDate"
    projection_type = "ALL"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-shares" }))
}

########################################
# 2. xomtracks-users
# PK: email
#
# NOT explicitly named in the infra build-out request, but required by
# already-shipped xomtracks-backend code: lambdas/common/dynamo_helpers.py
# ::get_app_service_user() reads this table for xomtracks' OWN single
# Spotify-connected service-account row -- the one account the app plays/
# searches/builds playlists through (self-contained per PLAN.md Option 3,
# NOT a per-browsing-user OAuth flow, NOT xomify's users table). Also the
# target of spotify.py's `_persist_rotated_refresh_token`.
########################################
resource "aws_dynamodb_table" "users" {
  name           = "${var.app_name}-users"
  billing_mode   = "PAY_PER_REQUEST"
  read_capacity  = 0
  write_capacity = 0
  hash_key       = "email"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "email"
    type = "S"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-users" }))
}

########################################
# 3. xomtracks-ratings  (whole-group song ratings -- additive, NEW table)
# PK: trackKey   -- normalized SONG identity so a rating follows the SONG
#     across ALL of its share instances, NOT per-share. Prefers
#     `spotify:<resolvedSpotifyId>`; falls back to a normalized `url:<...>`
#     for unmatched tracks (see xomtracks-backend/lambdas/common/track_key.py
#     ::derive_track_key).
# SK: raterEmail -- the Cognito email of the rater. One item per (track, user)
#     => a member has exactly one rating per song; re-rating is a plain upsert.
#
# Aggregate {avg, count} is computed by Query-ing the trackKey PARTITION (every
# rater row for a song lives together), which also yields the caller's own row
# in the same read -- no denormalized counter to drift. Cheap at friend-group
# scale; a denormalized `#AGG` row is the documented fast-follow if fan-out
# ever costs. Backs POST /ratings/set + GET /ratings/get and the inline
# `rating` enrichment on /shares/list + /me/shares.
#
# Name matches the `${var.app_name}*` ARN prefix the existing lambda_role
# already grants DynamoDB read/write on (see iam_lambda.tf) -- so NO IAM change
# is needed, same as xomtracks-users. Standard pattern: PAY_PER_REQUEST + KMS +
# PITR + standard_tags.
########################################
resource "aws_dynamodb_table" "ratings" {
  name           = "${var.app_name}-ratings"
  billing_mode   = "PAY_PER_REQUEST"
  read_capacity  = 0
  write_capacity = 0
  hash_key       = "trackKey"
  range_key      = "raterEmail"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "trackKey"
    type = "S"
  }

  attribute {
    name = "raterEmail"
    type = "S"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-ratings" }))
}

########################################
# 4. xomtracks-heard  (per-(track, user) LISTEN state -- additive, NEW table)
# PK: trackKey   -- normalized SONG identity so a "heard" flag follows the SONG
#     across ALL of its share instances, NOT per-share. Identical key shape to
#     xomtracks-ratings (see track_key.py::derive_track_key).
# SK: raterEmail -- the Cognito email of the listener. One item per (track, user)
#     => a member has exactly one heard row per song; toggling is a plain upsert.
# attrs (non-key): heard (bool), heardAt (epoch "when heard"), updatedAt (epoch).
#
# Unlike ratings there is NO aggregate: heard is a PER-CALLER boolean, so the
# feed enrichment reads only the caller's own row per track (default False when
# absent -- a GetItem per unique trackKey; see xomtracks-backend/lambdas/common/
# heard_dynamo.py). Backs POST /heard/set, the auto-heard EventBridge cron, and
# the inline `heard` enrichment on /shares/list + /me/shares.
#
# Name matches the `${var.app_name}*` ARN prefix the existing lambda_role AND
# cron_lambda_role already grant DynamoDB read/write on (see iam_lambda.tf) -- so
# NO IAM change is needed, same as xomtracks-ratings/users. Standard pattern:
# PAY_PER_REQUEST + KMS + PITR + standard_tags.
########################################
resource "aws_dynamodb_table" "heard" {
  name           = "${var.app_name}-heard"
  billing_mode   = "PAY_PER_REQUEST"
  read_capacity  = 0
  write_capacity = 0
  hash_key       = "trackKey"
  range_key      = "raterEmail"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "trackKey"
    type = "S"
  }

  attribute {
    name = "raterEmail"
    type = "S"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-heard" }))
}

########################################
# 5. xomtracks-link-requests  (pending phone-link requests -- additive, NEW table)
# PK: requestId (uuid4)
# attrs (non-key): requesterEmail (Cognito caller), phone (NORMALIZED last-10
#   digits), savedName (Dom's saved contact name for the number, or absent),
#   sub (Cognito sub, optional), status ("pending"|"approved"|"denied"),
#   createdAt (epoch), updatedAt (epoch).
#
# Backs the ADMIN-APPROVAL rework of phone linking: a member's POST /me/link-phone
# no longer auto-links (trust-based) -- it creates a PENDING row here, and the
# admin (Dom) approves/denies it via GET /admin/requests + POST /admin/approve|deny
# (see lambda_admin.tf). Approval writes the real link to xomtracks-users via the
# existing user_links logic; denial writes nothing.
#
# No GSI: the admin queue (list pending) and GET /me/get's "pending" check are
# both filtered Scans -- the right tool at friend-group scale, matching the
# scan_shares_by_match_status precedent. A status GSI is the documented
# fast-follow if request volume grows.
#
# Name matches the `${var.app_name}*` ARN prefix the existing lambda_role already
# grants DynamoDB read/write on (see iam_lambda.tf) -- so NO IAM change is needed
# for table access, same as xomtracks-ratings/heard/users. Standard pattern:
# PAY_PER_REQUEST + KMS + PITR + standard_tags.
########################################
resource "aws_dynamodb_table" "link_requests" {
  name           = "${var.app_name}-link-requests"
  billing_mode   = "PAY_PER_REQUEST"
  read_capacity  = 0
  write_capacity = 0
  hash_key       = "requestId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.dynamodb.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "requestId"
    type = "S"
  }

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-link-requests" }))
}
