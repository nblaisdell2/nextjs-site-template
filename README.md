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
| `init-from-template` | `npm run template:init` | One-time: personalize a fresh copy (name, region, repo) |
| `setup-aws` | `npm run aws:setup` | Run the **entire** first-time AWS setup end to end |
| `bootstrap-backend` | `npm run aws:bootstrap` | Create the S3 state bucket |
| `build-and-push` | `npm run aws:deploy` | Build the image and push to ECR |
| `run-migrations` | `npm run aws:migrate` | Apply DB migrations against RDS |
| `set-deploy-secrets` | `npm run aws:secrets` | Push the CI role ARN + region to GitHub secrets |
| `destroy-all` | `npm run aws:destroy` | Tear down everything (`--delete-snapshots`, `--delete-state-bucket`, `--yes`) |

Pass arguments after `--`, e.g. `npm run template:init -- -ProjectName my-app -GitHubRepo me/my-app`.
On Linux/macOS without PowerShell 7, call the `.sh` versions directly.

## Prerequisites

- Node.js 20+, Docker, AWS CLI (authenticated), GitHub CLI (`gh auth login`)
- Terraform ≥ 1.10 (needed for S3-native state locking and the ECS Express resource)
- PowerShell 7 (`pwsh`) if you want to use the npm script aliases (optional)

---

## Local development

```bash
npm install
docker run --name budget-pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16
cp .env.example .env        # points at the local container; DATABASE_SSL=disable
npm run migrate
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
  `terraform apply` on just the ECS service to roll out the new image (zero-downtime
  canary). The CI role is scoped to that — it can't change RDS or networking.
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

1. "Use this template" → new repo, then clone it.
2. Personalize it in one command (replaces the name/region, generates `terraform.tfvars`):

   ```powershell
   .\scripts\init-from-template.ps1 -ProjectName my-app -GitHubRepo owner/my-app -Region us-east-1
   ```
   ```bash
   ./scripts/init-from-template.sh --name my-app --repo owner/my-app --region us-east-1
   ```
   Add `-CreateOidcProvider` / `--create-oidc` only if the account has no GitHub OIDC provider yet.
3. Review `git diff`, fill in `infra/terraform.tfvars` (`my_ip_cidr`), then run
   `npm run aws:setup` (the **First-time AWS setup** above).

Terraform provisions all the AWS resources, so there's no big generator script to
maintain — "use template + `terraform apply`" replaces it.

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
