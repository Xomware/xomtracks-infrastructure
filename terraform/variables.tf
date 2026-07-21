variable "app_name" {
  description = "The name for the application."
  type        = string
  default     = "xomtracks"
}

variable "domain_suffix" {
  description = "Suffix for the domain of the app."
  type        = string
  default     = ".xomware.com"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# CloudFront Variables
variable "cloudfront_origin_path" {
  description = "Optional element for cloudfront distribution that causes CloudFront to request your content from a directory in your Amazon S3 bucket."
  type        = string
  default     = ""
}

variable "us_canada_only" {
  description = "If a georestriction should be placed on the distribution to only provide access to the US and Canada"
  type        = bool
  default     = true
}

variable "custom_error_response_page_path" {
  description = "Custom error response page path for SPA routing."
  type        = string
  default     = "/index.html"
}

variable "retain_on_delete" {
  description = "Disables the distribution instead of deleting it when destroying the resource through Terraform."
  type        = bool
  default     = false
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for CloudFront"
  type        = string
  default     = "TLSv1.2_2018"
}

variable "enable_cloudfront_cache" {
  description = "This variable controls the cloudfront cache. Setting this to false will set the default_ttl and max_ttl values to zero"
  type        = bool
  default     = true
}

# Lambda Variables
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.12"
}

variable "lambda_trace_mode" {
  description = "X-Ray tracing mode for Lambda"
  type        = string
  default     = "Active"
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
}

# API Gateway
variable "api_stage_name" {
  description = "API Gateway deployment stage name"
  type        = string
  default     = "dev"
}

variable "cors_allowed_origins" {
  description = "Comma-delimited allowed CORS origins for the API. First entry is the default Access-Control-Allow-Origin; additional entries are echoed back via startsWith matching by the api module."
  type        = string
  default     = "https://xomtracks.xomware.com,https://xomware.com,https://www.xomware.com"
}

# Route53
variable "route53_zone_name" {
  description = "Route53 hosted zone name for DNS records"
  type        = string
  default     = "xomware.com"
}

# Tags
variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "owner" {
  description = "Owner of the infrastructure"
  type        = string
  default     = "domgiordano"
}

# Authorizer-specific settings
variable "authorizer_memory_size" {
  description = "Memory size for authorizer Lambda in MB"
  type        = number
  default     = 256
}

variable "authorizer_timeout" {
  description = "Timeout for authorizer Lambda in seconds"
  type        = number
  default     = 30
}

# ============================================
# App secrets -- no defaults (empty string if unset). Wired via TF_VAR_*
# in .github/workflows/terraform.yml from GitHub Actions secrets, matching
# xomify-infrastructure / meals-infrastructure's api_secret_key convention.
# Dom needs to set the real values as repo secrets before `terraform apply`
# actually persists usable credentials -- an empty-string plan is fine for
# the plan-only review checkpoint this phase stops at.
# ============================================

variable "spotify_client_id" {
  description = "Xomtracks' OWN Spotify Web API Client ID (self-contained per PLAN.md Option 3 -- not xomify's app)."
  type        = string
  sensitive   = true
}

variable "spotify_client_secret" {
  description = "Xomtracks' OWN Spotify Web API Client Secret."
  type        = string
  sensitive   = true
}

variable "soundcloud_client_id" {
  description = "Scraped SoundCloud client_id (xomcloud pattern) -- used by the cross-platform matcher to resolve SoundCloud metadata."
  type        = string
  sensitive   = true
}

variable "ingest_bearer_key" {
  description = "Scoped bearer key the local extractor sends to POST /shares/ingest. NOT the Cognito-validated user JWT -- a separate shared secret."
  type        = string
  sensitive   = true
}

variable "api_secret_key" {
  description = "HS256 signing key for auth_login's minted JWT."
  type        = string
  sensitive   = true
}

variable "app_service_user_email" {
  description = "Email key for xomtracks' single Spotify-connected service-account user row (the app plays/searches/builds playlists through this one account -- not a per-browsing-user OAuth flow)."
  type        = string
  default     = "xomtracks-app@xomware.com"
}
