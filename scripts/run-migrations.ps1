# Run database migrations against RDS (PowerShell).
# Uses the connection string Terraform stored in Secrets Manager. Requires RDS
# to be reachable from here (db_publicly_accessible = true and my_ip_cidr set
# to your IP).
#
#   .\scripts\run-migrations.ps1

$ErrorActionPreference = "Stop"

$InfraDir    = (Resolve-Path (Join-Path $PSScriptRoot "..\infra")).Path
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

Write-Host "==> Reading DATABASE_URL from Terraform outputs"
$DatabaseUrl = terraform "-chdir=$InfraDir" output -raw database_url

Write-Host "==> Applying migrations"
Push-Location $ProjectRoot
try {
    $env:DATABASE_URL = $DatabaseUrl
    # Force TLS on for RDS, overriding any DATABASE_SSL=disable from a local .env.
    $env:DATABASE_SSL = "require"
    npm run migrate
    if ($LASTEXITCODE -ne 0) { throw "migrations failed" }
}
finally {
    Remove-Item Env:\DATABASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:\DATABASE_SSL -ErrorAction SilentlyContinue
    Pop-Location
}

Write-Host "Done."
