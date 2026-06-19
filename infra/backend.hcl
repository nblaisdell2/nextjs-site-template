# Backend config for `terraform init -backend-config=backend.hcl`.
# Bucket names are globally unique and NOT secret, so this file is committed.
# scripts/bootstrap-backend.ps1 creates the bucket and fills this in.
bucket       = "REPLACE_WITH_YOUR_STATE_BUCKET"
key          = "nextjs-test/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
