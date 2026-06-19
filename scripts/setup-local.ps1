# One-shot local onboarding for a freshly cloned project (PowerShell).
#   npm run setup        (or: .\scripts\setup-local.ps1)
#
# 1) prompt for the local Postgres password
# 2) npm install
# 3) write .env (DATABASE_URL -> local database, default name "test")
# 4) npm run migrate (against that local DB)
# 5) personalize from the template (project name = folder, repo = <gh-user>/<folder>)
# 6) set my_ip_cidr in infra/terraform.tfvars to your current public IP
#
# Prereq for step 4: a local Postgres is running and has the database from step 3.

[CmdletBinding()]
param(
    [string]$DbPassword,
    [string]$Region = "us-east-1",
    [string]$DbName = "test"
)

$ErrorActionPreference = "Stop"
$scriptsDir = $PSScriptRoot
$root  = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$infra = Join-Path $root "infra"

# --- 1. password ---
Write-Host "==> [1/6] Local Postgres password" -ForegroundColor Cyan
if (-not $DbPassword) {
    $secure = Read-Host "Local Postgres password" -AsSecureString
    $DbPassword = [System.Net.NetworkCredential]::new("", $secure).Password
}
if ([string]::IsNullOrWhiteSpace($DbPassword)) { throw "Database password is required." }

# --- 2. npm install ---
Write-Host "`n==> [2/6] npm install" -ForegroundColor Cyan
npm install
if ($LASTEXITCODE -ne 0) { throw "npm install failed" }

# --- 3. .env ---
Write-Host "`n==> [3/6] Writing .env (database '$DbName')" -ForegroundColor Cyan
$enc   = [uri]::EscapeDataString($DbPassword)   # URL-safe password
$dbUrl = "postgres://postgres:$enc@localhost:5432/$DbName"
$envExample = Join-Path $root ".env.example"
$envPath    = Join-Path $root ".env"
$content = if (Test-Path $envExample) { Get-Content $envExample -Raw } else { "DATABASE_URL=`nDATABASE_SSL=disable`n" }
if ($content -match '(?m)^DATABASE_URL=') {
    $content = $content -replace '(?m)^DATABASE_URL=.*$', "DATABASE_URL=$dbUrl"
} else {
    $content = "DATABASE_URL=$dbUrl`n" + $content
}
Set-Content -Path $envPath -Value $content -NoNewline -Encoding UTF8

# --- 4. ensure DB exists, then migrate (local) ---
Write-Host "`n==> [4/6] Ensure database '$DbName' exists, then migrate" -ForegroundColor Cyan
npm run db:ensure
if ($LASTEXITCODE -ne 0) { throw "could not ensure database '$DbName' - is a local Postgres running?" }
npm run migrate
if ($LASTEXITCODE -ne 0) { throw "migrate failed" }

# --- 5. personalize from template ---
Write-Host "`n==> [5/6] init-from-template" -ForegroundColor Cyan
$projectName = ((Split-Path $root -Leaf).ToLower() -replace '[^a-z0-9-]', '-').Trim('-')
$owner = $null
try { $owner = (gh api user --jq .login 2>$null) } catch {}
if ([string]::IsNullOrWhiteSpace($owner)) { $owner = "OWNER" }
& (Join-Path $scriptsDir "init-from-template.ps1") -ProjectName $projectName -GitHubRepo "$owner/$projectName" -Region $Region

# --- 6. my_ip_cidr ---
Write-Host "`n==> [6/6] Detecting public IP -> my_ip_cidr" -ForegroundColor Cyan
$ip = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com").Trim()
$tfvars = Join-Path $infra "terraform.tfvars"
if ((Test-Path $tfvars) -and $ip) {
    $rep = '$1"' + $ip + '/32"'
    (Get-Content $tfvars -Raw) -replace '(?m)^(\s*my_ip_cidr\s*=\s*).*$', $rep |
        Set-Content -Path $tfvars -NoNewline -Encoding UTF8
    Write-Host "    my_ip_cidr = `"$ip/32`""
} else {
    Write-Host "    terraform.tfvars not found or IP undetectable; skipped."
}

Write-Host "`nDone. Local dev: 'npm run dev'.  Deploy: 'npm run aws:setup'." -ForegroundColor Green
