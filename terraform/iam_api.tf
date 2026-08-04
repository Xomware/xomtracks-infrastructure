## API Gateway IAM for CloudWatch Logging

data "aws_iam_policy_document" "api_gateway_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}
# Retained even though `aws_api_gateway_account` is no longer managed here (see
# apigateway.tf): the live account-level cloudwatch_role_arn may still point at
# this role, so destroying it would leave a dangling pointer and break
# account-wide API Gateway CloudWatch logging until the owning repo reconciles.
# Safe to remove only AFTER the owning repo (xomforms today; ideally
# xomware-infrastructure) has taken over the account setting.
resource "aws_iam_role" "api_gateway_cloudwatch" {
  name               = "${var.app_name}-api_gateway-logs"
  tags               = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-api_gateway-logs" }))
  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role.json
}

data "aws_iam_policy_document" "api_gateway_cloudwatch_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
      "logs:GetLogEvents",
      "logs:FilterLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_role_policy" {
  name   = "${var.app_name}-api_gateway_cloudwatch-role-policy"
  role   = aws_iam_role.api_gateway_cloudwatch.id
  policy = data.aws_iam_policy_document.api_gateway_cloudwatch_policy.json
}

# NOTE: the API-Gateway-assumes-role-to-invoke-authorizer-Lambda wiring was
# removed when authed routes moved to the native COGNITO_USER_POOLS
# authorizer. API Gateway validates Cognito JWTs itself -- there is no
# authorizer Lambda to invoke.
