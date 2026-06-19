# Build the Docker image and push it to ECR (PowerShell).
# Run from anywhere. Requires: aws cli, docker, terraform, (git optional).
#
#   .\scripts\build-and-push.ps1 [-ImageTag <tag>]
#
# If no tag is given, uses the current git short SHA (or a timestamp). The
# image is pushed under that tag AND :latest.
#
# ECS Express does not auto-deploy on push: after pushing, roll out the new
# image with a canary deployment by pointing the service at the tag:
#   cd infra ; terraform apply -var="image_tag=<tag>"

[CmdletBinding()]
param(
    [string]$ImageTag
)

$ErrorActionPreference = "Stop"

# Resolve paths relative to this script.
$InfraDir    = (Resolve-Path (Join-Path $PSScriptRoot "..\infra")).Path
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# Default tag: git short SHA, else a timestamp.
if (-not $ImageTag) {
    $ImageTag = (git rev-parse --short HEAD 2>$null)
    if (-not $ImageTag) { $ImageTag = Get-Date -Format "yyyyMMddHHmmss" }
}

$Region   = terraform "-chdir=$InfraDir" output -raw aws_region
$EcrUrl   = terraform "-chdir=$InfraDir" output -raw ecr_repository_url
$Registry = $EcrUrl.Substring(0, $EcrUrl.LastIndexOf("/"))

Write-Host "Region:   $Region"
Write-Host "ECR repo: $EcrUrl"
Write-Host "Tag:      $ImageTag (+ latest)"

Write-Host "==> Logging in to ECR"
aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $Registry
if ($LASTEXITCODE -ne 0) { throw "docker login failed" }

Write-Host "==> Building image (linux/amd64 for Fargate)"
docker build --platform linux/amd64 -t "$($EcrUrl):$ImageTag" -t "$($EcrUrl):latest" $ProjectRoot
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }

Write-Host "==> Pushing"
docker push "$($EcrUrl):$ImageTag"
if ($LASTEXITCODE -ne 0) { throw "docker push failed" }
docker push "$($EcrUrl):latest"
if ($LASTEXITCODE -ne 0) { throw "docker push (latest) failed" }

Write-Host ""
Write-Host "Pushed $($EcrUrl):$ImageTag"
Write-Host "To roll it out:  cd infra ; terraform apply -var=`"image_tag=$ImageTag`""
