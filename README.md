# Budget App

A YNAB-style budgeting app scaffold. Server-rendered **Next.js** (App Router) in
a Docker container on **Amazon ECS Express Mode** (Fargate), talking to
**PostgreSQL on RDS**, with the DB connection string held in **AWS Secrets
Manager**. State is stored remotely in **S3**, and pushes to `main` auto-deploy
via **GitHub Actions** (OIDC, no stored keys).

```
push to main ─> GitHub Actions ─(OIDC)─> build + push image to ECR
                                          └─> terraform apply (targeted) ─> ECS Express rollout

Browser ──HTTPS──> ECS Express (ALB + Fargate task, image from ECR)
                        │  DATABASE_URL injected from Secrets Manager at startup
                        │  TLS verified with the RDS CA bundle baked into the image
                        ▼
                   RDS PostgreSQL  ◄── Secrets Manager (connection string)
```

## Quick start

Prerequisites: Node.js 20+, Docker, AWS CLI (authenticated), GitHub CLI
(`gh auth login`), Terraform ≥ 1.10, and PowerShell 7 (`pwsh`) for the npm
aliases. On Linux/macOS without `pwsh`, run the matching `scripts/*.sh` directly.

**New project from this template — run in this order:**

```bash
# 1. GitHub → "Use this template" → create the repo, then clone it and cd in.

# 2. Start a local Postgres (skip if you already have one running):
docker run --name pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16

# 3. Onboard: npm install, write .env, create the local DB, migrate,
#    personalize the project (name/repo from the folder), and set your IP.
npm run setup            # prompts for the local Postgres password

# 4. Run locally:
npm run dev              # http://localhost:3000  -> /budget

# 5. Deploy to AWS (provisions everything; prints the live https URL):
npm run aws:setup

# 6. Enable CI auto-deploy — after this, every push to main ships:
git add . && git commit -m "init" && git push -u origin main
```

> If this is a fresh AWS account with **no** existing GitHub OIDC provider, set
> `create_oidc_provider = true` in `infra/terraform.tfvars` before step 5.

The sections below explain each piece in detail.

## What's here

| Path | Purpose |
|------|---------|
| `app/` | Next.js routes: landing, `budget/`, `api/health`, `api/transactions` |
| `lib/db.ts` | `pg` pool; full TLS verification using the bundled RDS CA |
| `db/migrations/` + `db/migrate.mjs` | SQL migrations and a forward-only runner |
| `Dockerfile` | Multi-stage standalone build; bundles the RDS CA cert |
| `infra/` | Terraform: ECR, RDS, Secrets Manager, ECS Express, IAM, OIDC, S3 backend |
| `.github/workflows/deploy.yml` | CI/CD: build, push, deploy on push to `main` |
| `scripts/` | PowerShell helpers (see below) |

### Scripts

Every script ships in both PowerShell (`.ps1`, Windows) and Bash (`.sh`, Linux/macOS).
The common ones are also exposed as **npm scripts**, which call the PowerShell
versions via `pwsh` (so they work on any OS that has PowerShell 7 installed).

| Script | npm | Purpose |
|--------|-----|---------|
| `setup-local` | `npm run setup` | One-shot local onboarding: install, `.env`, migrate, personalize, set your IP |
| `init-from-template` | `npm run template:init` | One-time: personalize a fresh copy (name, region, repo) |
| `setup-aws` | `npm run aws:setup` | Run the **entire** first-time AWS setup end to end |
| `bootstrap-backend` | `npm run aws:bootstrap` | Create the S3 state bucket |
| `build-and-push` | `npm run aws:deploy` | Build the image and push to ECR |
| `run-migrations` | `npm run aws:migrate` | Apply DB migrations against RDS |
| `set-deploy-secrets` | `npm run aws:secrets` | Push the CI role ARN + region to GitHub secrets |
| `destroy-all` | `npm run aws:destroy` | Tear down everything (`--delete-snapshots`, `--delete-state-bucket`, `--yes`) |

Pass arguments after `--`, e.g. `npm run template:init -- -ProjectName my-app -GitHubRepo me/my-app`.
On Linux/macOS without PowerShell 7, call the `.sh` versions directly.

Local-only npm helpers (no shell script): `npm run dev`, `npm run migrate` (apply
migrations), and `npm run db:ensure` (create the local database if it's missing).

## Prerequisites

- Node.js 20+, Docker, AWS CLI (authenticated), GitHub CLI (`gh auth login`)
- Terraform ≥ 1.10 (needed for S3-native state locking and the ECS Express resource)
- PowerShell 7 (`pwsh`) if you want to use the npm script aliases (optional)

---

## Local development

`npm run setup` (see Quick start) already does all of this. To do it by hand —
or for day-to-day work after onboarding:

```bash
npm install
docker run --name pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16
cp .env.example .env        # set the DATABASE_URL password + db name; DATABASE_SSL=disable
npm run db:ensure           # create the database if it doesn't exist
npm run migrate             # apply migrations
npm run dev                 # http://localhost:3000  → /budget
```

Locally there's no RDS CA bundle, so `lib/db.ts` connects without TLS (`DATABASE_SSL=disable`). In the container the CA is present and TLS is fully verified.

---

## First-time AWS setup

First make sure `infra/terraform.tfvars` exists and is filled in. `init-from-template`
creates it; otherwise `cp infra/terraform.tfvars.example infra/terraform.tfvars` and set:

- `my_ip_cidr` — your IP for migrations (`curl https://checkip.amazonaws.com` → `"<ip>/32"`)
- `github_repo` — `"<owner>/<repo>"`
- `create_oidc_provider` — `true`, or `false` if the account already has a GitHub OIDC provider

The state bucket name is derived as `<project_name>-tfstate` automatically — you don't set it.

Then run the **entire** setup in one command (bucket → init → apply → build → migrate →
launch → secrets, all with `-auto-approve`):

```powershell
npm run aws:setup
```
```bash
npm run aws:setup        # or, without pwsh:  ./scripts/setup-aws.sh
```

When it finishes it prints the service URL. Then commit and push:

```bash
git add . && git commit -m "init" && git push -u origin main
```

After that first push, every push to `main` builds, pushes, and rolls out automatically.

<details>
<summary>What <code>aws:setup</code> runs (do it manually if you prefer)</summary>

```powershell
.\scripts\bootstrap-backend.ps1                          # 1. create state bucket
cd infra
terraform init "-backend-config=backend.hcl"             # 2. init  (quote the flag — see note)
terraform apply -auto-approve                            # 3. base infra (deploy_service=false)
cd ..
.\scripts\build-and-push.ps1 -ImageTag <tag>             # 4. build + push image
.\scripts\run-migrations.ps1                             # 5. migrations
# set deploy_service = true in infra\terraform.tfvars
cd infra
terraform apply -auto-approve -var="image_tag=<tag>"     # 6. launch ECS service
cd ..
.\scripts\set-deploy-secrets.ps1                         # 7. GitHub deploy secrets
```
</details>

> **PowerShell gotcha:** always **quote the backend flag** —
> `terraform init "-backend-config=backend.hcl"`. Unquoted, PowerShell mis-splits it and
> Terraform fails with *"Too many command line arguments."*

> **Already have the App Runner-era OIDC provider?** Set `create_oidc_provider = false`
> and Terraform references the existing one instead of failing on a duplicate.

---

## How deploys work

- **CI (push to main)** builds the image, pushes it to ECR, and runs a *targeted*
  `terraform apply -refresh=false` on just the ECS service to roll out the new image
  (zero-downtime canary). `-refresh=false` means CI reads/changes nothing else — so
  the role stays minimal and it can never touch RDS or networking.
- **Infra changes** (RDS, networking, IAM) are applied from your laptop with your
  full credentials: edit `infra/*.tf`, then `terraform apply`.
- **Manual image deploy** (no push): `npm run aws:deploy` (build + push) then
  `terraform apply -var="image_tag=<tag>"`.

Because state lives in S3, your laptop and CI share one source of truth — no drift.

---

## Tearing down / restoring the database (cost saving)

RDS bills continuously while running. To stop paying for it without losing data:

```powershell
cd infra
terraform destroy -target=aws_db_instance.main   # creates a final snapshot automatically
```

To bring it back later **with its data**, set `use_latest_snapshot = true` in
`terraform.tfvars` and apply — it restores from the most recent snapshot:

```powershell
terraform apply
```

(First-ever create must run with `use_latest_snapshot = false`, since no snapshot exists yet.)

---

## Use as a template for new projects

This repo is structured to be a GitHub **template repo** (Settings → "Template repository").
For a new project:

1. "Use this template" → new repo, then clone it and `cd` in.
2. Run `npm run setup`. It personalizes the project (name + repo derived from the
   folder, region `us-east-1`), sets up local dev, and fills in `infra/terraform.tfvars`
   including your public IP.
   - To *only* personalize (no local DB / migrate), run instead:
     `npm run template:init -- -ProjectName my-app -GitHubRepo owner/my-app`
     (add `-CreateOidcProvider` if the account has no GitHub OIDC provider yet).
3. Review `git diff`, then `npm run aws:setup` to deploy (see **First-time AWS setup**).

Terraform provisions all the AWS resources, so there's no big generator script to
maintain — "use template + `npm run aws:setup`" replaces it.

---

## Security notes

- **TLS is fully verified** in the container: the app loads the RDS CA bundle
  (baked into the image at `/app/certs/rds-global-bundle.pem`) and checks the
  server certificate. Locally, set `DATABASE_SSL=disable`.
- **No long-lived AWS keys in CI** — GitHub OIDC issues short-lived credentials,
  trusted only for `repo:<owner>/<name>:*`.
- The DB password is generated by Terraform and only ever lives in state (S3,
  encrypted) and Secrets Manager — never in the image or git.
- `db_publicly_accessible = true` is a dev convenience for running migrations from
  your laptop. For production, set it `false` and run migrations from inside the VPC.
- The CI deploy role is scoped to image rollouts; tighten the read-only `*`
  resources further if you want.
