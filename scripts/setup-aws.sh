#!/usr/bin/env bash
# First-time AWS setup, end to end (Bash). Encapsulates the README's
# "First-time AWS setup". Terraform runs with -auto-approve.
#
#   ./scripts/setup-aws.sh [--skip-migrations] [--image-tag=<tag>]
#
# Prerequisites: terraform.tfvars exists (run init-from-template first) with
# my_ip_cidr + github_repo set; AWS CLI, Docker, Terraform, gh all authenticated;
# you're inside the project's git repo. Safe to re-run.

set -euo pipefail

SKIP_MIGRATIONS=false
IMAGE_TAG=""
for arg in "$@"; do
  case "$arg" in
    --skip-migrations) SKIP_MIGRATIONS=true ;;
    --image-tag=*)     IMAGE_TAG="${arg#*=}" ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(cd "$SCRIPTS_DIR/../infra" && pwd)"
TFVARS="$INFRA_DIR/terraform.tfvars"

[ -f "$TFVARS" ] || { echo "infra/terraform.tfvars not found. Run init-from-template first." >&2; exit 1; }
[ -n "$IMAGE_TAG" ] || IMAGE_TAG="$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)"

step() { echo ""; echo "==> $1"; }

step "[1/7] Create remote-state bucket"
bash "$SCRIPTS_DIR/bootstrap-backend.sh"

step "[2/7] terraform init"
terraform -chdir="$INFRA_DIR" init -backend-config=backend.hcl

step "[3/7] terraform apply (base infra: ECR, RDS, secret, IAM)"
terraform -chdir="$INFRA_DIR" apply -auto-approve

step "[4/7] Build + push image ($IMAGE_TAG)"
bash "$SCRIPTS_DIR/build-and-push.sh" "$IMAGE_TAG"

step "[5/7] Run database migrations"
if [ "$SKIP_MIGRATIONS" = true ]; then
  echo "skipped (--skip-migrations)"
else
  bash "$SCRIPTS_DIR/run-migrations.sh"
fi

step "[6/7] Launch ECS Express service"
# Flip deploy_service to true so future applies keep the service.
sed -i.bak -E 's/(deploy_service[[:space:]]*=[[:space:]]*)false/\1true/' "$TFVARS" && rm -f "$TFVARS.bak"
terraform -chdir="$INFRA_DIR" apply -auto-approve -var="image_tag=$IMAGE_TAG"

step "[7/7] Set GitHub deploy secrets"
bash "$SCRIPTS_DIR/set-deploy-secrets.sh"

echo ""
echo "Done. Service URL:"
terraform -chdir="$INFRA_DIR" output ingress_paths
