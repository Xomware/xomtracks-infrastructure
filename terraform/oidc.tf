#**********************
# GitHub Actions OIDC
# Keyless auth for the frontend and backend deploy workflows
#**********************

# Account-wide and already created by whichever stack migrated first.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# One role per repo. The trust policy is the entire security boundary for OIDC,
# so a token minted in the frontend repo must not be able to touch lambdas.
locals {
  github_oidc_repos = {
    frontend = var.github_frontend_subjects
    backend  = var.github_backend_subjects
  }
}

data "aws_iam_policy_document" "github_actions_trust" {
  for_each = local.github_oidc_repos

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Any ref in the repo: the deploy workflows also run via workflow_dispatch
    # from other refs, which a ref-pinned subject would break.
    #
    # Both spellings of the subject are listed because GitHub has moved newer
    # repos to IMMUTABLE identifiers -- the claim on this repo is
    # `repo:Xomware@263047999/xomtracks-frontend@1307126928:...`, not
    # `repo:Xomware/xomtracks-frontend:...`, and a policy written the obvious
    # way matches nothing. Accepting both survives a flip in either direction.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for subject in each.value : "${subject}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  for_each = local.github_oidc_repos

  name               = "${var.app_name}-github-actions-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust[each.key].json

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-github-actions-${each.key}" }))
}

data "aws_iam_policy_document" "github_actions_frontend" {
  statement {
    sid    = "PublishSite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.site.arn,
      "${aws_s3_bucket.site.arn}/*",
    ]
  }

  # The deploy finds the distribution by alias at runtime rather than taking an
  # id, and ListDistributions has no resource form -- it is account-wide or
  # nothing. Read-only, and the invalidation itself is scoped below.
  statement {
    sid       = "FindDistribution"
    effect    = "Allow"
    actions   = ["cloudfront:ListDistributions"]
    resources = ["*"]
  }

  # GetInvalidation as well as Create: this deploy WAITS for the invalidation
  # to finish rather than firing and forgetting, so it polls.
  statement {
    sid    = "InvalidateCache"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
    ]
    resources = [aws_cloudfront_distribution.site.arn]
  }

  # Cognito wiring baked into the bundle at build time. These live under the
  # SHARED xomware prefix, not this app's own, because the user pool is shared.
  statement {
    sid       = "ReadSharedCognitoConfig"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:parameter/xomware/shared/cognito/*"]
  }
}

resource "aws_iam_role_policy" "github_actions_frontend" {
  name   = "deploy"
  role   = aws_iam_role.github_actions["frontend"].id
  policy = data.aws_iam_policy_document.github_actions_frontend.json
}

data "aws_iam_policy_document" "github_actions_backend" {
  statement {
    sid    = "ManageSharedLayer"
    effect = "Allow"
    actions = [
      "lambda:PublishLayerVersion",
      "lambda:ListLayerVersions",
      "lambda:GetLayerVersion",
    ]
    resources = [
      "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:layer:${var.app_name}-shared-packages",
      "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:layer:${var.app_name}-shared-packages:*",
    ]
  }

  # By name prefix, so a new lambda does not need an IAM change to deploy.
  statement {
    sid    = "DeployFunctions"
    effect = "Allow"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
    ]
    resources = ["arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:function:${var.app_name}-*"]
  }

  statement {
    sid       = "ListLayers"
    effect    = "Allow"
    actions   = ["lambda:ListLayers"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_backend" {
  name   = "deploy"
  role   = aws_iam_role.github_actions["backend"].id
  policy = data.aws_iam_policy_document.github_actions_backend.json
}

output "github_actions_frontend_role_arn" {
  description = "Role the frontend deploy workflow assumes via OIDC"
  value       = aws_iam_role.github_actions["frontend"].arn
}

output "github_actions_backend_role_arn" {
  description = "Role the backend deploy workflow assumes via OIDC"
  value       = aws_iam_role.github_actions["backend"].arn
}
