## Resources for API Gateway Lambda Authorization
# Ported from xomforms-infrastructure's lambda_authorizer.tf (itself ported
# from xomify-infrastructure). The Lambda's own code
# (lambdas/authorizer/handler.py in xomtracks-backend) is meant to validate
# real Cognito-issued JWTs against the shared pool's JWKS (see
# data_cognito.tf), email-keyed context out, same Allow/Deny policy shape
# xomify/xomforms use.
#
# FLAGGED (matches exactly how xomforms handled the same situation): the
# authorizer's actual Python source does NOT exist yet in xomtracks-backend
# -- this resource references the generic stub zip like every other
# freshly-scaffolded Lambda in this file. It will return the stub's
# hardcoded response (effectively unusable for real auth, not a 200) until
# that handler is written and deployed via CI. Every CUSTOM-authorization
# route in apigateway.tf depends on this Lambda being real before it's
# usable in production -- fine for a plan-only checkpoint, not fine for
# real authed traffic.

resource "aws_lambda_function" "authorizer" {
  function_name    = "${var.app_name}-authorizer"
  description      = "Lambda Authorizer for ${var.app_name}"
  filename         = "./templates/lambda_stub.zip"
  source_code_hash = filebase64sha256("./templates/lambda_stub.zip")
  handler          = "handler.handler"
  layers           = [aws_lambda_layer_version.lambda_layer.arn]
  runtime          = var.lambda_runtime
  memory_size      = var.authorizer_memory_size
  timeout          = var.authorizer_timeout
  role             = aws_iam_role.authorizer_role.arn

  environment {
    variables = local.lambda_variables
  }
  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-authorizer" }))

  tracing_config {
    mode = var.lambda_trace_mode
  }

  lifecycle {
    ignore_changes = [
      description,
      filename,
      source_code_hash,
      layers
    ]
  }
  depends_on = [
    aws_iam_role_policy.authorizer_role_policy,
    aws_iam_role.authorizer_role
  ]
}
