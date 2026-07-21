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

# ============================================
# App secrets
#
# REMOVED as of the SSM-fix pass (see ssm.tf's per-resource comments):
# spotify_client_id / spotify_client_secret / soundcloud_client_id /
# ingest_bearer_key / api_secret_key are no longer Terraform variables.
# The first apply attempt sourced all five from no-default variables wired
# via TF_VAR_* GitHub secrets that were never set -> resolved to an empty
# string -> `terraform plan`/`validate` accepted that silently, but AWS
# SSM's real `PutParameter` API rejects an empty Value outright
# (ValidationException: length >= 1), which is exactly what failed on the
# first real apply. Each of the five now has its value resolved a
# different way that doesn't depend on a human-supplied Terraform
# variable: Spotify creds are a placeholder Dom sets once via the AWS CLI
# (own-app requirement, can't be generated); SoundCloud's client_id is
# mirrored from xomcloud's existing scraped value via a data source;
# the ingest bearer key and API_SECRET_KEY are generated in-stack
# (random.tf) since both are purely-internal secrets with no external
# registration step.
# ============================================

variable "app_service_user_email" {
  description = "Email key for xomtracks' single Spotify-connected service-account user row (the app plays/searches/builds playlists through this one account -- not a per-browsing-user OAuth flow)."
  type        = string
  default     = "xomtracks-app@xomware.com"
}
