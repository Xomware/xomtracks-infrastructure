# Shared Cognito SSM data sources
#
# These read the SSM parameters exported by xomware-infrastructure (the
# shared pool owner -- see cognito_ssm.tf there). Xomtracks consumes the
# shared xomware_users User Pool rather than owning its own identity
# surface. Do NOT provision a new pool here.
#
# Pattern matches xomforms-infrastructure/terraform/data_cognito.tf and
# meals-infrastructure/terraform/data_cognito.tf exactly.

data "aws_ssm_parameter" "cognito_user_pool_arn" {
  name = "/xomware/shared/cognito/user-pool-arn"
}

data "aws_ssm_parameter" "cognito_user_pool_id" {
  name = "/xomware/shared/cognito/user-pool-id"
}

data "aws_ssm_parameter" "cognito_user_pool_jwks_url" {
  name = "/xomware/shared/cognito/user-pool-jwks-url"
}

data "aws_ssm_parameter" "cognito_hosted_ui_domain" {
  name = "/xomware/shared/cognito/hosted-ui-domain"
}

# App client -- cognito_client_xomtracks. Lives with the pool owner
# (xomware-infrastructure), matching xomware_com/xomappetit/xomforms
# exactly -- see xomware-infrastructure/terraform/cognito.tf's
# aws_cognito_user_pool_client.xomtracks and its SSM export in
# cognito_ssm.tf's aws_ssm_parameter.cognito_client_xomtracks_id.
#
# NOTE: this data source cannot resolve until the xomware-infrastructure
# PR (adding the xomtracks client) is reviewed AND applied -- do not run
# plan/apply here until that param exists in SSM. This is the dependency
# the coordinator flagged: this repo's PR can only fully plan after the
# xomware-infrastructure PR is applied.
data "aws_ssm_parameter" "cognito_client_xomtracks_id" {
  name = "/xomware/shared/cognito/clients/xomtracks-id"
}
