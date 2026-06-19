# Create the S3 bucket that holds Terraform remote state. Run ONCE per project,
# before `terraform init`.
#
#   .\scripts\bootstrap-backend.ps1
#
# The bucket name, region, and key are read from infra/backend.hcl (which
# init-from-template sets to "<project-name>-tfstate"). Pass -BucketName to
# override (e.g. if the convention name is already taken globally).

[CmdletBinding()]
param(
    [string]$BucketName,
    [string]$Region,
    [string]$StateKey
)

$ErrorActionPreference = "Stop"
$infraDir    = (Resolve-Path (Join-Path $PSScriptRoot "..\infra")).Path
$backendPath = Join-Path $infraDir "backend.hcl"

function Get-HclValue([string]$key) {
    if (Test-Path $backendPath) {
        $m = Select-String -Path $backendPath -Pattern "^\s*$key\s*=\s*`"([^`"]+)`""
        if ($m) { return $m.Matches[0].Groups[1].Value }
    }
    return $null
}

# Defaults come from backend.hcl; parameters override.
if (-not $BucketName) { $BucketName = Get-HclValue "bucket" }
if (-not $Region)     { $Region     = Get-HclValue "region" }
if (-not $StateKey)   { $StateKey   = Get-HclValue "key" }
if (-not $Region)     { $Region     = "us-east-1" }
if (-not $StateKey)   { $StateKey   = "terraform.tfstate" }

if (-not $BucketName -or $BucketName -eq "REPLACE_WITH_YOUR_STATE_BUCKET") {
    throw "No bucket name in backend.hcl. Run init-from-template first, or pass -BucketName."
}

aws s3api head-bucket --bucket $BucketName 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "==> Bucket '$BucketName' already exists; skipping create"
} else {
    Write-Host "==> Creating state bucket '$BucketName' in $Region"
    if ($Region -eq "us-east-1") {
        aws s3api create-bucket --bucket $BucketName --region $Region | Out-Null
    } else {
        aws s3api create-bucket --bucket $BucketName --region $Region `
            --create-bucket-configuration "LocationConstraint=$Region" | Out-Null
    }
}

Write-Host "==> Enabling versioning (state history / recovery)"
aws s3api put-bucket-versioning --bucket $BucketName `
    --versioning-configuration "Status=Enabled" | Out-Null

Write-Host "==> Blocking public access"
aws s3api put-public-access-block --bucket $BucketName `
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" | Out-Null

Write-Host "==> Writing $backendPath"
@"
# Backend config for ``terraform init -backend-config=backend.hcl``.
bucket       = "$BucketName"
key          = "$StateKey"
region       = "$Region"
encrypt      = true
use_lockfile = true
"@ | Set-Content -Path $backendPath -Encoding UTF8

Write-Host ""
Write-Host "Done. Next:"
Write-Host "  cd infra"
Write-Host "  terraform init -backend-config=backend.hcl"
