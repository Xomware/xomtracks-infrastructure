# Generated in-stack secrets -- no human input, no external registration
# step. Consumed by ssm.tf's aws_ssm_parameter.ingest_bearer_key /
# api_secret_key. `special = false` keeps both values plain
# alphanumeric -- the ingest key rides in an `Authorization: Bearer <...>`
# header and the API key seeds HS256 JWT signing; neither needs special
# characters, and avoiding them sidesteps any header/shell-escaping
# surprises when Dom reads the ingest key back out for the extractor's
# config (see ssm.tf's comment).
#
# Terraform's `random_password` result is a Terraform-native secret (never
# printed in plan/apply output); the real value only ever lives in the SSM
# SecureString it's written to and in Terraform state (which is itself
# encrypted at rest in the S3 backend, matching this repo's existing
# state-handling posture).

resource "random_password" "ingest_bearer_key" {
  length  = 48
  special = false
}

resource "random_password" "api_secret_key" {
  length  = 64
  special = false
}
