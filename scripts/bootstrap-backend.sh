#!/usr/bin/env bash
# Create the S3 bucket that holds Terraform remote state, then write
# infra/backend.hcl. Run ONCE per project, before `terraform init`.
#
#   ./scripts/bootstrap-backend.sh [bucket-name] [region] [state-key]
#
# Bucket names are globally unique; pass one or let it generate a unique name.

set -euo pipefail

BUCKET="${1:-}"
REGION="${2:-us-east-1}"
STATE_KEY="${3:-nextjs-test/terraform.tfstate}"

if [ -z "$BUCKET" ]; then
  SUFFIX="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c6)"
  BUCKET="nextjs-test-tfstate-$SUFFIX"
fi

echo "==> Creating state bucket '$BUCKET' in $REGION"
if [ "$REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
fi

echo "==> Enabling versioning (state history / recovery)"
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled >/dev/null

echo "==> Blocking public access"
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

INFRA_DIR="$(cd "$(dirname "$0")/../infra" && pwd)"
cat > "$INFRA_DIR/backend.hcl" <<EOF
# Backend config for \`terraform init -backend-config=backend.hcl\`.
bucket       = "$BUCKET"
key          = "$STATE_KEY"
region       = "$REGION"
encrypt      = true
use_lockfile = true
EOF

echo ""
echo "Done. Next:"
echo "  cd infra"
echo "  terraform init -backend-config=backend.hcl -migrate-state"
