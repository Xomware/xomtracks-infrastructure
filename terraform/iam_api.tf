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
