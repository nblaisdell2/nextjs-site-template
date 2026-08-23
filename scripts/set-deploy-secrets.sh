#!/usr/bin/env bash
# Set the GitHub repo secret (CI role ARN) and variable (AWS region) the deploy
# workflow needs, reading both from Terraform outputs. Run after the first full
# `terraform apply` (which creates the role) and after the repo exists.
# Requires the GitHub CLI (gh).
#
#   ./scripts/set-deploy-secrets.sh

set -euo pipefail

INFRA_DIR="$(cd "$(dirname "$0")/../infra" && pwd)"

ROLE_ARN="$(terraform -chdir="$INFRA_DIR" output -raw github_actions_role_arn)"
REGION="$(terraform -chdir="$INFRA_DIR" output -raw aws_region)"

if [ -z "${ROLE_ARN:-}" ] || [ "$ROLE_ARN" = "null" ]; then
  echo "github_actions_role_arn is empty. Set github_repo in terraform.tfvars and apply first." >&2
  exit 1
fi

echo "==> Setting GitHub secret + variable on the current repo"
gh secret set AWS_DEPLOY_ROLE_ARN -b "$ROLE_ARN"
# Region is not sensitive; a variable keeps it readable in CI logs.
gh variable set AWS_REGION -b "$REGION"

echo "Done. Push to main to trigger a deploy."
