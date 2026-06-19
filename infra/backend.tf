# Remote state in S3 so your laptop and CI share one source of truth.
#
# The bucket must exist BEFORE `terraform init` (chicken-and-egg), so it's
# created by scripts/bootstrap-backend.ps1, not by Terraform itself.
#
# Config values are supplied at init time from backend.hcl:
#   terraform init -backend-config=backend.hcl
#
# use_lockfile = true uses S3-native state locking (Terraform >= 1.10), so no
# DynamoDB table is needed.
terraform {
  backend "s3" {}
}
