# Set the GitHub repo secret (CI role ARN) and variable (AWS region) the deploy
# workflow needs, reading both from Terraform outputs. Run after the first full
# `terraform apply` (which creates the role) and after the repo exists.
# Requires the GitHub CLI (gh).
#
#   .\scripts\set-deploy-secrets.ps1

$ErrorActionPreference = "Stop"

$infraDir = (Resolve-Path (Join-Path $PSScriptRoot "..\infra")).Path

$roleArn = terraform "-chdir=$infraDir" output -raw github_actions_role_arn
$region  = terraform "-chdir=$infraDir" output -raw aws_region

if (-not $roleArn -or $roleArn -eq "null") {
    throw "github_actions_role_arn is empty. Set github_repo in terraform.tfvars and apply first."
}

Write-Host "==> Setting GitHub secret + variable on the current repo"
gh secret set AWS_DEPLOY_ROLE_ARN -b $roleArn
# Region is not sensitive; a variable keeps it readable in CI logs.
gh variable set AWS_REGION -b $region

Write-Host "Done. Push to main to trigger a deploy."
