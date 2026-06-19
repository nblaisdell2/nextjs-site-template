# GitHub Actions OIDC: lets the CI workflow assume an AWS role with NO long-lived
# access keys. GitHub presents a short-lived OIDC token; AWS trusts it for the
# specific repo configured below.

# Create the provider, or reference the existing one (only one allowed per acct).
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # Thumbprint is no longer used by AWS for this provider, but the API requires a
  # value. This is GitHub's well-known intermediate cert thumbprint.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.create_oidc_provider ? (
    aws_iam_openid_connect_provider.github[0].arn
  ) : data.aws_iam_openid_connect_provider.github[0].arn

  # State bucket follows "<project_name>-tfstate" (matching backend.hcl) unless
  # var.state_bucket overrides it. Derived so it can't drift from the real bucket.
  state_bucket = var.state_bucket != "" ? var.state_bucket : "${var.project_name}-tfstate"
}

# Trust policy: only tokens from var.github_repo can assume this role.
data "aws_iam_policy_document" "gha_assume" {
  count = var.github_repo == null ? 0 : 1
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count              = var.github_repo == null ? 0 : 1
  name               = "${var.project_name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.gha_assume[0].json
}

# Permissions for CI. The workflow only builds/pushes the image and rolls out the
# ECS service via a TARGETED apply, so it needs: ECR push, ECS update, PassRole
# for the task roles, read access to refresh the service's dependencies, and R/W
# on the state bucket. Infra changes (RDS, networking) are done from your laptop.
data "aws_iam_policy_document" "gha_deploy" {
  count = var.github_repo == null ? 0 : 1

  statement {
    sid       = "EcrPush"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrRepo"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
      "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
  statement {
    sid       = "EcsDeploy"
    actions   = ["ecs:*"]
    resources = ["*"]
  }
  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn, aws_iam_role.infrastructure.arn]
  }
  # Read-only describes so `terraform apply` can refresh the targeted resource's
  # dependencies without write access to that infra.
  statement {
    sid = "ReadOnlyRefresh"
    actions = [
      "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:GetOpenIDConnectProvider",
      "secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue",
      "rds:DescribeDBInstances", "rds:DescribeDBSnapshots",
      "ec2:Describe*", "logs:DescribeLogGroups",
      "elasticloadbalancing:Describe*", "application-autoscaling:Describe*",
      "acm:Describe*", "acm:ListCertificates", "cloudwatch:DescribeAlarms",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "TerraformState"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.state_bucket}", "arn:aws:s3:::${local.state_bucket}/*"]
  }
}

resource "aws_iam_role_policy" "gha_deploy" {
  count  = var.github_repo == null ? 0 : 1
  name   = "deploy"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.gha_deploy[0].json
}
