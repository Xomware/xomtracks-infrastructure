locals {
  domain_name     = "${var.app_name}${var.domain_suffix}"
  api_domain_name = "api.${local.domain_name}"

  # Get the AWS account id
  web_app_account_id = data.aws_caller_identity.web_app_account.account_id

  # Standard tags for all resources
  standard_tags = {
    "source"      = "terraform"
    "app_name"    = var.app_name
    "environment" = var.environment
    "owner"       = var.owner
  }

  # Lambda environment variables (names match what xomtracks-backend's
  # lambdas/common/constants.py reads). Secrets (Spotify creds, SoundCloud
  # client_id, ingest bearer key, API_SECRET_KEY) are DELIBERATELY NOT
  # here -- lambdas/common/ssm_helpers.py fetches those lazily from SSM at
  # runtime via boto3, same convention as xomify/xomforms. Only non-secret
  # config (table/index names, Cognito ids) goes in the environment block.
  lambda_variables = {
    APP_NAME               = var.app_name
    DYNAMODB_KMS_ALIAS     = aws_kms_alias.dynamodb.name
    SHARES_TABLE_NAME      = aws_dynamodb_table.shares.id
    SHARES_DIRECTION_INDEX = "direction-messageDate-index"
    SHARES_SHARER_INDEX    = "sharerHandle-messageDate-index"
    # Multi-tenant Phase 1: owner-scoped GSI-3 + the owner key + the read-cutover
    # kill-switch. DEFAULT_OWNER_ID also has a hardcoded backend default so ingest
    # stamping works before this env applies; OWNER_SCOPING_ENABLED gates the
    # /shares/list read cutover (flip to false = instant rollback to GSI-1).
    SHARES_OWNER_DIRECTION_INDEX = "ownerDirection-messageDate-index"
    DEFAULT_OWNER_ID             = var.default_owner_id
    OWNER_SCOPING_ENABLED        = var.owner_scoping_enabled
    USERS_TABLE_NAME             = aws_dynamodb_table.users.id
    RATINGS_TABLE_NAME           = aws_dynamodb_table.ratings.id
    HEARD_TABLE_NAME             = aws_dynamodb_table.heard.id
    LINK_REQUESTS_TABLE_NAME     = aws_dynamodb_table.link_requests.id
    # Per-user extractor ingest tokens (self-serve foundation Phase 3). Stores
    # only the SHA-256 hash of each token; the ingest handler resolves a
    # presented token -> ownerId (dual-accepting the legacy SSM key -> Dom).
    INGEST_TOKENS_TABLE_NAME = aws_dynamodb_table.ingest_tokens.id
    APP_SERVICE_USER_EMAIL   = var.app_service_user_email
    AUTO_HEARD_RATER_EMAIL   = var.auto_heard_rater_email
    # Single admin allowed to hit /admin/* (require_admin gates on caller email
    # == this). Also who the phone-link notification email is sent TO.
    ADMIN_EMAIL    = var.admin_email
    AWS_ACCOUNT_ID = data.aws_caller_identity.web_app_account.account_id

    # Shared Cognito pool (see data_cognito.tf) -- the ported authorizer
    # validates real Cognito-issued (RS256) JWTs against this pool's JWKS,
    # same pattern as xomforms-infrastructure.
    COGNITO_USER_POOL_ID = data.aws_ssm_parameter.cognito_user_pool_id.value
    COGNITO_JWKS_URL     = data.aws_ssm_parameter.cognito_user_pool_jwks_url.value
    COGNITO_CLIENT_ID    = data.aws_ssm_parameter.cognito_client_xomtracks_id.value
  }

  # API Gateway allowed headers
  api_allow_headers = [
    "Authorization",
    "Content-Type",
    "X-Amz-Date",
    "X-Amz-Security-Token",
    "X-Api-Key",
    "Origin",
    "Accept",
    "Access-Control-Allow-Origin",
    "Accept-Language"
  ]
}
