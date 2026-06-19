# Tear down EVERYTHING this project created in AWS (PowerShell).
#
#   .\scripts\destroy-all.ps1 [-DeleteSnapshots] [-DeleteStateBucket] [-Yes]
#
# By default: runs `terraform destroy` (removes ECS, RDS, ECR, secret, IAM,
# networking). RDS leaves a final snapshot behind.
#   -DeleteSnapshots    also delete this project's RDS snapshots (irreversible)
#   -DeleteStateBucket  also empty + delete the S3 state bucket (removes remote state)
#   -Yes                skip the confirmation prompt

[CmdletBinding()]
param(
    [switch]$DeleteSnapshots,
    [switch]$DeleteStateBucket,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$infraDir = (Resolve-Path (Join-Path $PSScriptRoot "..\infra")).Path

function Get-Tfvar([string]$name, [string]$default) {
    $f = Join-Path $infraDir "terraform.tfvars"
    if (Test-Path $f) {
        $m = Select-String -Path $f -Pattern "^\s*$name\s*=\s*`"([^`"]+)`""
        if ($m) { return $m.Matches[0].Groups[1].Value }
    }
    return $default
}

$projectName = Get-Tfvar "project_name" "nextjs-test"
$region      = Get-Tfvar "aws_region" "us-east-1"

if (-not $Yes) {
    Write-Host "This will DESTROY all AWS resources for project '$projectName'." -ForegroundColor Yellow
    if ($DeleteSnapshots)   { Write-Host "  + delete RDS snapshots (DATA LOSS)" -ForegroundColor Red }
    if ($DeleteStateBucket) { Write-Host "  + delete the Terraform state bucket" -ForegroundColor Red }
    $answer = Read-Host "Type the project name ('$projectName') to confirm"
    if ($answer -ne $projectName) { Write-Host "Aborted."; exit 1 }
}

Write-Host "==> terraform destroy"
terraform "-chdir=$infraDir" destroy -auto-approve
if ($LASTEXITCODE -ne 0) { throw "terraform destroy failed" }

if ($DeleteSnapshots) {
    Write-Host "==> Deleting RDS snapshots for '$projectName-db'"
    $snaps = aws rds describe-db-snapshots --snapshot-type manual --region $region `
        --query "DBSnapshots[?starts_with(DBSnapshotIdentifier, '$projectName-db')].DBSnapshotIdentifier" `
        --output text
    foreach ($s in ($snaps -split "\s+" | Where-Object { $_ })) {
        Write-Host "   - $s"
        aws rds delete-db-snapshot --db-snapshot-identifier $s --region $region | Out-Null
    }
}

if ($DeleteStateBucket) {
    $bucket = $null
    $bh = Join-Path $infraDir "backend.hcl"
    if (Test-Path $bh) {
        $m = Select-String -Path $bh -Pattern '^\s*bucket\s*=\s*"([^"]+)"'
        if ($m) { $bucket = $m.Matches[0].Groups[1].Value }
    }
    if ($bucket -and $bucket -ne "REPLACE_WITH_YOUR_STATE_BUCKET") {
        Write-Host "==> Emptying + deleting state bucket '$bucket' (incl. all versions)"
        # Versioned bucket: must delete every version and delete-marker first.
        foreach ($sel in @("Versions[].{Key:Key,VersionId:VersionId}",
                           "DeleteMarkers[].{Key:Key,VersionId:VersionId}")) {
            $json = aws s3api list-object-versions --bucket $bucket --region $region `
                --query "{Objects: $sel}" --output json
            if ($json -and $json -notmatch '"Objects":\s*null') {
                $tmp = New-TemporaryFile
                $json | Set-Content -Path $tmp -Encoding UTF8
                aws s3api delete-objects --bucket $bucket --region $region --delete "file://$tmp" | Out-Null
                Remove-Item $tmp
            }
        }
        aws s3api delete-bucket --bucket $bucket --region $region | Out-Null
    } else {
        Write-Host "No real state bucket found in backend.hcl; skipping."
    }
}

Write-Host "Done."
