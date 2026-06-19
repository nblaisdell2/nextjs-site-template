# First-time AWS setup, end to end (PowerShell). Encapsulates the README's
# "First-time AWS setup". Terraform runs with -auto-approve.
#
#   .\scripts\setup-aws.ps1 [-SkipMigrations] [-ImageTag <tag>]
#
# Prerequisites: terraform.tfvars exists (run init-from-template first) with
# my_ip_cidr + github_repo set; AWS CLI, Docker, Terraform, gh all authenticated;
# you're inside the project's git repo. Safe to re-run.

[CmdletBinding()]
param(
    [switch]$SkipMigrations,
    [string]$ImageTag
)

$ErrorActionPreference = "Stop"
$scriptsDir = $PSScriptRoot
$infraDir   = (Resolve-Path (Join-Path $PSScriptRoot "..\infra")).Path
$tfvars     = Join-Path $infraDir "terraform.tfvars"

if (-not (Test-Path $tfvars)) {
    throw "infra/terraform.tfvars not found. Run init-from-template first (or copy terraform.tfvars.example)."
}

if (-not $ImageTag) {
    $ImageTag = (git rev-parse --short HEAD 2>$null)
    if (-not $ImageTag) { $ImageTag = Get-Date -Format "yyyyMMddHHmmss" }
}

function Invoke-Step([string]$label, [scriptblock]$action) {
    Write-Host ""
    Write-Host "==> $label" -ForegroundColor Cyan
    & $action
}

Invoke-Step "[1/7] Create remote-state bucket" {
    & (Join-Path $scriptsDir "bootstrap-backend.ps1")
}

Invoke-Step "[2/7] terraform init" {
    terraform "-chdir=$infraDir" init "-backend-config=backend.hcl"
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed" }
}

Invoke-Step "[3/7] terraform apply (base infra: ECR, RDS, secret, IAM)" {
    terraform "-chdir=$infraDir" apply -auto-approve
    if ($LASTEXITCODE -ne 0) { throw "terraform apply (base) failed" }
}

Invoke-Step "[4/7] Build + push image ($ImageTag)" {
    & (Join-Path $scriptsDir "build-and-push.ps1") -ImageTag $ImageTag
}

Invoke-Step "[5/7] Run database migrations" {
    if ($SkipMigrations) { Write-Host "skipped (-SkipMigrations)"; return }
    & (Join-Path $scriptsDir "run-migrations.ps1")
}

Invoke-Step "[6/7] Launch ECS Express service" {
    # Flip deploy_service to true so future applies keep the service.
    (Get-Content $tfvars -Raw) -replace 'deploy_service(\s*)=(\s*)false', 'deploy_service$1=$2true' |
        Set-Content $tfvars -NoNewline -Encoding UTF8
    terraform "-chdir=$infraDir" apply -auto-approve -var="image_tag=$ImageTag"
    if ($LASTEXITCODE -ne 0) { throw "terraform apply (launch) failed" }
}

Invoke-Step "[7/7] Set GitHub deploy secrets" {
    & (Join-Path $scriptsDir "set-deploy-secrets.ps1")
}

Write-Host ""
Write-Host "Done. Service URL:" -ForegroundColor Green
terraform "-chdir=$infraDir" output ingress_paths
