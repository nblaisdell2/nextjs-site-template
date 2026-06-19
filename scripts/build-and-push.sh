#!/usr/bin/env bash
# Build the Docker image and push it to ECR.
# Run from the project root. Requires: aws cli, docker, terraform.
#
#   ./scripts/build-and-push.sh [image_tag]
#
# If no tag is given, uses the current git short SHA (or a timestamp). The
# image is pushed under that tag AND :latest.
#
# ECS Express does not auto-deploy on push: after pushing, roll out the new
# image with a canary deployment by pointing the service at the tag:
#   cd infra && terraform apply -var="image_tag=<tag>"

set -euo pipefail

DEFAULT_TAG="$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)"
IMAGE_TAG="${1:-$DEFAULT_TAG}"
INFRA_DIR="$(cd "$(dirname "$0")/../infra" && pwd)"

REGION="$(terraform -chdir="$INFRA_DIR" output -raw aws_region)"
ECR_URL="$(terraform -chdir="$INFRA_DIR" output -raw ecr_repository_url)"
REGISTRY="${ECR_URL%/*}"

echo "Region:   $REGION"
echo "ECR repo: $ECR_URL"
echo "Tag:      $IMAGE_TAG (+ latest)"

echo "==> Logging in to ECR"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo "==> Building image (linux/amd64 for Fargate)"
docker build --platform linux/amd64 \
  -t "$ECR_URL:$IMAGE_TAG" -t "$ECR_URL:latest" .

echo "==> Pushing"
docker push "$ECR_URL:$IMAGE_TAG"
docker push "$ECR_URL:latest"

echo
echo "Pushed $ECR_URL:$IMAGE_TAG"
echo "To roll it out:  cd infra && terraform apply -var=\"image_tag=$IMAGE_TAG\""
