#!/usr/bin/env bash
# Tear down EVERYTHING this project created in AWS (Bash).
#
#   ./scripts/destroy-all.sh [--delete-snapshots] [--delete-state-bucket] [--yes]
#
# Default: terraform destroy (ECS, RDS, ECR, secret, IAM, networking). RDS leaves
# a final snapshot behind.
#   --delete-snapshots     also delete this project's RDS snapshots (irreversible)
#   --delete-state-bucket  also empty + delete the S3 state bucket
#   --yes                  skip the confirmation prompt

set -euo pipefail

DELETE_SNAPSHOTS=false
DELETE_STATE_BUCKET=false
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --delete-snapshots)    DELETE_SNAPSHOTS=true ;;
    --delete-state-bucket) DELETE_STATE_BUCKET=true ;;
    --yes)                 ASSUME_YES=true ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

INFRA_DIR="$(cd "$(dirname "$0")/../infra" && pwd)"

get_tfvar() { # name default
  local v
  v="$(grep -E "^\s*$1\s*=" "$INFRA_DIR/terraform.tfvars" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
  echo "${v:-$2}"
}

PROJECT_NAME="$(get_tfvar project_name nextjs-test)"
REGION="$(get_tfvar aws_region us-east-1)"

if [ "$ASSUME_YES" != true ]; then
  echo "This will DESTROY all AWS resources for project '$PROJECT_NAME'."
  $DELETE_SNAPSHOTS    && echo "  + delete RDS snapshots (DATA LOSS)"
  $DELETE_STATE_BUCKET && echo "  + delete the Terraform state bucket"
  read -r -p "Type the project name ('$PROJECT_NAME') to confirm: " answer
  [ "$answer" = "$PROJECT_NAME" ] || { echo "Aborted."; exit 1; }
fi

echo "==> terraform destroy"
terraform -chdir="$INFRA_DIR" destroy -auto-approve

if [ "$DELETE_SNAPSHOTS" = true ]; then
  echo "==> Deleting RDS snapshots for '${PROJECT_NAME}-db'"
  for s in $(aws rds describe-db-snapshots --snapshot-type manual --region "$REGION" \
      --query "DBSnapshots[?starts_with(DBSnapshotIdentifier, '${PROJECT_NAME}-db')].DBSnapshotIdentifier" \
      --output text); do
    echo "   - $s"
    aws rds delete-db-snapshot --db-snapshot-identifier "$s" --region "$REGION" >/dev/null
  done
fi

if [ "$DELETE_STATE_BUCKET" = true ]; then
  BUCKET="$(grep -E '^\s*bucket\s*=' "$INFRA_DIR/backend.hcl" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
  if [ -n "${BUCKET:-}" ] && [ "$BUCKET" != "REPLACE_WITH_YOUR_STATE_BUCKET" ]; then
    echo "==> Emptying + deleting state bucket '$BUCKET' (incl. all versions)"
    for sel in "Versions[].{Key:Key,VersionId:VersionId}" "DeleteMarkers[].{Key:Key,VersionId:VersionId}"; do
      json="$(aws s3api list-object-versions --bucket "$BUCKET" --region "$REGION" --query "{Objects: $sel}" --output json)"
      if ! echo "$json" | grep -q '"Objects": null'; then
        echo "$json" > /tmp/del-objs.json
        aws s3api delete-objects --bucket "$BUCKET" --region "$REGION" --delete file:///tmp/del-objs.json >/dev/null
        rm -f /tmp/del-objs.json
      fi
    done
    aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  else
    echo "No real state bucket found in backend.hcl; skipping."
  fi
fi

echo "Done."
