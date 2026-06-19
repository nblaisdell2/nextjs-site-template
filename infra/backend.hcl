# Backend config for `terraform init -backend-config=backend.hcl`.
# Bucket names are globally unique and NOT secret, so this file is committed.
# Convention: "<project-name>-tfstate". init-from-template rewrites these values,
# and scripts/bootstrap-backend creates the bucket named here.
bucket       = "nextjs-test-tfstate"
key          = "nextjs-test/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
