output "ecr_repository_url" {
  description = "Push images here."
  value       = aws_ecr_repository.app.repository_url
}

output "aws_region" {
  value = var.aws_region
}

output "rds_endpoint" {
  description = "RDS host:port."
  value       = "${aws_db_instance.main.address}:${aws_db_instance.main.port}"
}

output "database_secret_arn" {
  description = "Secrets Manager ARN holding DATABASE_URL."
  value       = aws_secretsmanager_secret.database_url.arn
}

output "database_url" {
  description = "Full connection string (sensitive). Use for local migrations."
  value       = local.database_url
  sensitive   = true
}

output "github_actions_role_arn" {
  description = "ARN of the CI deploy role. Set this as the AWS_DEPLOY_ROLE_ARN GitHub secret."
  value       = var.github_repo == null ? null : aws_iam_role.github_actions[0].arn
}

output "service_arn" {
  description = "ARN of the ECS Express service (once deployed)."
  value       = var.deploy_service ? aws_ecs_express_gateway_service.app[0].service_arn : "(set deploy_service=true and apply)"
}

output "ingress_paths" {
  description = <<-EOT
    Ingress info for the ECS Express service. The public HTTPS endpoint is in
    here (an *.on.aws address); browse to https://<that-endpoint>/.
  EOT
  value = var.deploy_service ? aws_ecs_express_gateway_service.app[0].ingress_paths : null
}
