# Set the GitHub repo secrets the deploy workflow needs, reading the CI role ARN
# from Terraform outputs. Run after the first full `terraform apply` (which
# creates the role) and after the repo exists. Requires the GitHub CLI (gh).
#
#   .\scripts\set-deploy-secrets.ps1

$ErrorActionPreference = "Stop"

$infraDir = (Resolve-Path (Join-Path $PSScriptRoot "..\infra")).Path

$roleArn = terraform "-chdir=$infraDir" output -raw github_actions_role_arn
$region  = terraform "-chdir=$infraDir" output -raw aws_region

if (-not $roleArn -or $roleArn -eq "null") {
    throw "github_actions_role_arn is empty. Set github_repo in terraform.tfvars and apply first."
}

Write-Host "==> Setting GitHub secrets on the current repo"
gh secret set AWS_DEPLOY_ROLE_ARN -b $roleArn
gh secret set AWS_REGION -b $region

Write-Host "Done. Push to main to trigger a deploy."
