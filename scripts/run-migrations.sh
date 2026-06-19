#!/usr/bin/env bash
# Run database migrations against RDS using the connection string Terraform
# stored in Secrets Manager. Requires RDS to be reachable from here
# (db_publicly_accessible = true and my_ip_cidr set to your IP).
#
#   ./scripts/run-migrations.sh

set -euo pipefail

INFRA_DIR="$(cd "$(dirname "$0")/../infra" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Reading DATABASE_URL from Terraform outputs"
DATABASE_URL="$(terraform -chdir="$INFRA_DIR" output -raw database_url)"

echo "==> Applying migrations"
cd "$PROJECT_ROOT"
# Force TLS on for RDS, overriding any DATABASE_SSL=disable from a local .env.
DATABASE_URL="$DATABASE_URL" DATABASE_SSL=require npm run migrate

echo "Done."
