#!/usr/bin/env bash
# Set the GitHub repo secrets the deploy workflow needs, reading the CI role ARN
# from Terraform outputs. Run after the first full `terraform apply` (which
# creates the role) and after the repo exists. Requires the GitHub CLI (gh).
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

echo "==> Setting GitHub secrets on the current repo"
gh secret set AWS_DEPLOY_ROLE_ARN -b "$ROLE_ARN"
gh secret set AWS_REGION -b "$REGION"

echo "Done. Push to main to trigger a deploy."
