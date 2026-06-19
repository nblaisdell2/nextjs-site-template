#!/usr/bin/env bash
# One-shot local onboarding for a freshly cloned project (Bash).
#   ./scripts/setup-local.sh [--password=...] [--region=us-east-1] [--db-name=test]
#
# 1) prompt for the local Postgres password
# 2) npm install
# 3) write .env (DATABASE_URL -> local database, default name "test")
# 4) npm run migrate (against that local DB)
# 5) personalize from the template (project name = folder, repo = <gh-user>/<folder>)
# 6) set my_ip_cidr in infra/terraform.tfvars to your current public IP
#
# Prereq for step 4: a local Postgres is running and has the database from step 3.

set -euo pipefail

REGION="us-east-1"
DB_NAME="test"
DB_PASSWORD=""
for arg in "$@"; do
  case "$arg" in
    --password=*) DB_PASSWORD="${arg#*=}" ;;
    --region=*)   REGION="${arg#*=}" ;;
    --db-name=*)  DB_NAME="${arg#*=}" ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
INFRA="$ROOT/infra"

urlencode() { # URL-safe encode of $1
  local s="$1" out="" i c
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in [a-zA-Z0-9.~_-]) out+="$c" ;; *) out+=$(printf '%%%02X' "'$c") ;; esac
  done
  printf '%s' "$out"
}

echo "==> [1/6] Local Postgres password"
if [ -z "$DB_PASSWORD" ]; then
  read -r -s -p "Local Postgres password: " DB_PASSWORD; echo
fi
[ -n "$DB_PASSWORD" ] || { echo "Database password is required." >&2; exit 1; }

echo "==> [2/6] npm install"
(cd "$ROOT" && npm install)

echo "==> [3/6] Writing .env (database '$DB_NAME')"
ENC="$(urlencode "$DB_PASSWORD")"
DBURL="postgres://postgres:$ENC@localhost:5432/$DB_NAME"
if [ -f "$ROOT/.env.example" ]; then cp "$ROOT/.env.example" "$ROOT/.env"; else printf 'DATABASE_URL=\nDATABASE_SSL=disable\n' > "$ROOT/.env"; fi
sed -i.bak -E "s|^DATABASE_URL=.*|DATABASE_URL=$DBURL|" "$ROOT/.env" && rm -f "$ROOT/.env.bak"

echo "==> [4/6] Ensure database '$DB_NAME' exists, then migrate"
(cd "$ROOT" && npm run db:ensure) || { echo "could not ensure database '$DB_NAME' - is a local Postgres running?" >&2; exit 1; }
(cd "$ROOT" && npm run migrate) || { echo "migrate failed" >&2; exit 1; }

echo "==> [5/6] init-from-template"
PROJECT_NAME="$(basename "$ROOT" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]/-/g; s/^-+//; s/-+$//')"
OWNER="$(gh api user --jq .login 2>/dev/null || true)"
[ -n "$OWNER" ] || OWNER="OWNER"
bash "$SCRIPTS_DIR/init-from-template.sh" --name "$PROJECT_NAME" --repo "$OWNER/$PROJECT_NAME" --region "$REGION"

echo "==> [6/6] Detecting public IP -> my_ip_cidr"
IP="$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')"
if [ -f "$INFRA/terraform.tfvars" ] && [ -n "$IP" ]; then
  sed -i.bak -E "s|^([[:space:]]*my_ip_cidr[[:space:]]*=[[:space:]]*).*|\1\"$IP/32\"|" "$INFRA/terraform.tfvars" && rm -f "$INFRA/terraform.tfvars.bak"
  echo "    my_ip_cidr = \"$IP/32\""
else
  echo "    terraform.tfvars not found or IP undetectable; skipped."
fi

echo ""
echo "Done. Local dev: 'npm run dev'.  Deploy: 'npm run aws:setup'."
