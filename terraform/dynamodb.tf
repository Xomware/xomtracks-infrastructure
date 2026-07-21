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
