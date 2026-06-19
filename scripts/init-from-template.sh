#!/usr/bin/env bash
# One-time personalization after "Use this template" (Bash).
#
#   ./scripts/init-from-template.sh --name my-app \
#       [--repo owner/my-app] [--region us-east-1] [--create-oidc]
#
# OFFLINE: only rewrites files in this repo (no AWS, no network). Replaces the
# template's identity (the "nextjs-test" token + region) and generates
# infra/terraform.tfvars. Run ONCE, review `git diff`, commit, then run the
# First-time AWS setup.

set -euo pipefail

PROJECT_NAME=""
GITHUB_REPO=""
REGION="us-east-1"
CREATE_OIDC="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --name)        PROJECT_NAME="$2"; shift 2 ;;
    --repo)        GITHUB_REPO="$2";  shift 2 ;;
    --region)      REGION="$2";       shift 2 ;;
    --create-oidc) CREATE_OIDC="true"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if ! echo "$PROJECT_NAME" | grep -Eq '^[a-z][a-z0-9-]{1,28}[a-z0-9]$'; then
  echo "Error: --name must be lowercase letters/digits/hyphens, 3-30 chars (e.g. 'my-app')." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OLD="nextjs-test"

replace_in() { # from to file
  local p="$ROOT/$3"
  [ -f "$p" ] || return 0
  sed -i.bak "s/$1/$2/g" "$p" && rm -f "$p.bak"
}

# 1. Project identity token.
for f in \
  infra/ci.tfvars infra/backend.hcl infra/terraform.tfvars.example \
  .github/workflows/deploy.yml README.md \
  scripts/bootstrap-backend.ps1 scripts/bootstrap-backend.sh \
  scripts/destroy-all.ps1 scripts/destroy-all.sh ; do
  replace_in "$OLD" "$PROJECT_NAME" "$f"
done

# 2. Default region in config/workflow/scripts only.
for f in \
  infra/ci.tfvars infra/backend.hcl .github/workflows/deploy.yml \
  scripts/bootstrap-backend.ps1 scripts/bootstrap-backend.sh ; do
  replace_in "us-east-1" "$REGION" "$f"
done

# 3. Generate infra/terraform.tfvars.
TFVARS="$ROOT/infra/terraform.tfvars"
REPO="${GITHUB_REPO:-OWNER/$PROJECT_NAME}"
if [ -f "$TFVARS" ]; then
  echo "infra/terraform.tfvars already exists - leaving it as is."
else
  cat > "$TFVARS" <<EOF
aws_region   = "$REGION"
project_name = "$PROJECT_NAME"

# State bucket is derived as "$PROJECT_NAME-tfstate" automatically.

# For local migrations (curl https://checkip.amazonaws.com -> "<ip>/32"):
my_ip_cidr = "REPLACE_WITH_YOUR_IP/32"

github_repo          = "$REPO"
create_oidc_provider = $CREATE_OIDC

# Flip to true after the first image push + migrations:
deploy_service      = false
image_tag           = "latest"
use_latest_snapshot = false
EOF
  echo "Wrote infra/terraform.tfvars"
fi

echo ""
echo "Personalized to '$PROJECT_NAME' (region $REGION)."
echo "Next:"
echo "  1. Review changes:  git diff"
echo "  2. Edit infra/terraform.tfvars (my_ip_cidr, github_repo, create_oidc_provider)"
echo "  3. Follow 'First-time AWS setup' in the README"
echo "  4. Optionally delete this script: git rm scripts/init-from-template.*"
