# One-time personalization after "Use this template" (PowerShell).
#
#   .\scripts\init-from-template.ps1 -ProjectName my-app `
#       -GitHubRepo owner/my-app -Region us-east-1 [-CreateOidcProvider]
#
# This is OFFLINE and idempotent-ish: it only rewrites files in this repo
# (no AWS, no network). It replaces the template's identity (the "nextjs-test"
# token + region) and generates infra/terraform.tfvars from the example.
# Run it ONCE, review `git diff`, commit, then run the First-time AWS setup.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectName,
    [string]$GitHubRepo,
    [string]$Region = "us-east-1",
    [switch]$CreateOidcProvider
)

$ErrorActionPreference = "Stop"

if ($ProjectName -notmatch '^[a-z][a-z0-9-]{1,28}[a-z0-9]$') {
    throw "ProjectName must be lowercase letters/digits/hyphens, 3-30 chars (e.g. 'my-app'). AWS resource names derive from it."
}

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$OLD  = "nextjs-test"

function Replace-In([string]$rel, [string]$from, [string]$to) {
    $p = Join-Path $root $rel
    if (Test-Path $p) {
        (Get-Content $p -Raw) -replace [regex]::Escape($from), $to |
            Set-Content $p -NoNewline -Encoding UTF8
    }
}

# 1. Replace the project identity token.
$projectFiles = @(
    "infra/ci.tfvars", "infra/backend.hcl", "infra/terraform.tfvars.example",
    ".github/workflows/deploy.yml", "README.md",
    "scripts/bootstrap-backend.ps1", "scripts/bootstrap-backend.sh",
    "scripts/destroy-all.ps1", "scripts/destroy-all.sh"
)
foreach ($f in $projectFiles) { Replace-In $f $OLD $ProjectName }

# 2. Replace the default region in config/workflow/scripts only.
$regionFiles = @(
    "infra/ci.tfvars", "infra/backend.hcl", ".github/workflows/deploy.yml",
    "scripts/bootstrap-backend.ps1", "scripts/bootstrap-backend.sh"
)
foreach ($f in $regionFiles) { Replace-In $f "us-east-1" $Region }

# 3. Generate infra/terraform.tfvars (your local, gitignored vars).
$tfvars = Join-Path $root "infra/terraform.tfvars"
$repo   = if ($GitHubRepo) { $GitHubRepo } else { "OWNER/$ProjectName" }
$oidc   = if ($CreateOidcProvider) { "true" } else { "false" }
if (Test-Path $tfvars) {
    Write-Host "infra/terraform.tfvars already exists - leaving it as is."
} else {
@"
aws_region   = "$Region"
project_name = "$ProjectName"

# Fill after running scripts/bootstrap-backend:
state_bucket = "REPLACE_AFTER_BOOTSTRAP"

# For local migrations (curl https://checkip.amazonaws.com -> "<ip>/32"):
my_ip_cidr = "REPLACE_WITH_YOUR_IP/32"

github_repo          = "$repo"
create_oidc_provider = $oidc

# Flip to true after the first image push + migrations:
deploy_service      = false
image_tag           = "latest"
use_latest_snapshot = false
"@ | Set-Content $tfvars -Encoding UTF8
    Write-Host "Wrote infra/terraform.tfvars"
}

Write-Host ""
Write-Host "Personalized to '$ProjectName' (region $Region)."
Write-Host "Next:"
Write-Host "  1. Review changes:  git diff"
Write-Host "  2. Edit infra/terraform.tfvars (my_ip_cidr, github_repo, create_oidc_provider)"
Write-Host "  3. Follow 'First-time AWS setup' in the README"
Write-Host "  4. Optionally delete this script: git rm scripts/init-from-template.*"
