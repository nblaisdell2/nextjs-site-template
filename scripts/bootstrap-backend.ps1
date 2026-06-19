# Create the S3 bucket that holds Terraform remote state, then write
# infra/backend.hcl. Run ONCE per project, before `terraform init`.
#
#   .\scripts\bootstrap-backend.ps1 -BucketName my-unique-tfstate-bucket
#
# Bucket names are globally unique across all of AWS, so pick something unique
# (e.g. "<you>-<project>-tfstate"). If you omit -BucketName, one is generated.

[CmdletBinding()]
param(
    [string]$BucketName,
    [string]$Region = "us-east-1",
    [string]$StateKey = "nextjs-test/terraform.tfstate"
)

$ErrorActionPreference = "Stop"

if (-not $BucketName) {
    $suffix = -join ((1..6) | ForEach-Object { "abcdefghijklmnopqrstuvwxyz0123456789"[(Get-Random -Maximum 36)] })
    $BucketName = "nextjs-test-tfstate-$suffix"
}

Write-Host "==> Creating state bucket '$BucketName' in $Region"
# us-east-1 must NOT pass a LocationConstraint; every other region must.
if ($Region -eq "us-east-1") {
    aws s3api create-bucket --bucket $BucketName --region $Region | Out-Null
} else {
    aws s3api create-bucket --bucket $BucketName --region $Region `
        --create-bucket-configuration "LocationConstraint=$Region" | Out-Null
}

Write-Host "==> Enabling versioning (state history / recovery)"
aws s3api put-bucket-versioning --bucket $BucketName `
    --versioning-configuration "Status=Enabled" | Out-Null

Write-Host "==> Blocking public access"
aws s3api put-public-access-block --bucket $BucketName `
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" | Out-Null

$infraDir = (Resolve-Path (Join-Path $PSScriptRoot "..\infra")).Path
$backendPath = Join-Path $infraDir "backend.hcl"

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
Write-Host "  terraform init -backend-config=backend.hcl -migrate-state"
