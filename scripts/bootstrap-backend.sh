#!/usr/bin/env bash
# Create the S3 bucket that holds Terraform remote state. Run ONCE per project,
# before `terraform init`.
#
#   ./scripts/bootstrap-backend.sh [bucket-name] [region] [state-key]
#
# The bucket name, region, and key default to what's in infra/backend.hcl (which
# init-from-template sets to "<project-name>-tfstate"). Pass a bucket name to
# override (e.g. if the convention name is already taken globally).

set -euo pipefail

BUCKET="${1:-}"
REGION="${2:-}"
STATE_KEY="${3:-}"

INFRA_DIR="$(cd "$(dirname "$0")/../infra" && pwd)"
BACKEND="$INFRA_DIR/backend.hcl"

hcl_value() { # key
  grep -E "^\s*$1\s*=" "$BACKEND" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/'
}

[ -n "$BUCKET" ]    || BUCKET="$(hcl_value bucket)"
[ -n "$REGION" ]    || REGION="$(hcl_value region)"
[ -n "$STATE_KEY" ] || STATE_KEY="$(hcl_value key)"
[ -n "$REGION" ]    || REGION="us-east-1"
[ -n "$STATE_KEY" ] || STATE_KEY="terraform.tfstate"

if [ -z "$BUCKET" ] || [ "$BUCKET" = "REPLACE_WITH_YOUR_STATE_BUCKET" ]; then
  echo "No bucket name in backend.hcl. Run init-from-template first, or pass a bucket name." >&2
  exit 1
fi

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "==> Bucket '$BUCKET' already exists; skipping create"
else
  echo "==> Creating state bucket '$BUCKET' in $REGION"
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
  fi
fi

echo "==> Enabling versioning (state history / recovery)"
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled >/dev/null

echo "==> Blocking public access"
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

echo "==> Writing $BACKEND"
cat > "$BACKEND" <<EOF
# Backend config for \`terraform init -backend-config=backend.hcl\`.
bucket       = "$BUCKET"
key          = "$STATE_KEY"
region       = "$REGION"
encrypt      = true
use_lockfile = true
EOF

echo ""
echo "Done. Next:"
echo "  cd infra && terraform init -backend-config=backend.hcl"
