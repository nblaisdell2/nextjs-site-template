# Amazon ECS Express Mode service.
#
# Express Mode takes a container image + two IAM roles and provisions the whole
# stack for you: a Fargate ECS service, an Application Load Balancer with an
# HTTPS cert, target groups, security groups, autoscaling, CloudWatch logs, and
# a public *.on.aws URL. We only configure the app-specific bits.
#
# Gated behind var.deploy_service: the service can only be created once an
# image exists in ECR (see README for the ordering).

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 14
}

resource "aws_ecs_express_gateway_service" "app" {
  count = var.deploy_service ? 1 : 0

  service_name            = var.project_name
  execution_role_arn      = aws_iam_role.execution.arn
  infrastructure_role_arn = aws_iam_role.infrastructure.arn

  cpu               = var.app_cpu
  memory            = var.app_memory
  health_check_path = "/api/health"

  primary_container {
    image          = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    container_port = var.container_port

    aws_logs_configuration {
      log_group         = aws_cloudwatch_log_group.app.name
      log_stream_prefix = var.project_name
    }

    environment {
      name  = "NODE_ENV"
      value = "production"
    }

    # The execution role fetches this from Secrets Manager at task startup and
    # injects it as the DATABASE_URL env var.
    secret {
      name       = "DATABASE_URL"
      value_from = aws_secretsmanager_secret.database_url.arn
    }
  }

  # Run the tasks in the same VPC as RDS, with our security group so RDS can
  # allow them on 5432. Express Mode handles the ALB and its own SGs.
  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  scaling_target {
    min_task_count = 1
    max_task_count = 3
    # Set these explicitly to match the AWS-side defaults; omitting them
    # triggers a provider "inconsistent result after apply" error.
    auto_scaling_metric       = "AVERAGE_CPU"
    auto_scaling_target_value = 60
  }

  # Per the provider docs: depend on the role policies so they aren't destroyed
  # before the service during teardown (which would wedge it in DRAINING).
  depends_on = [
    aws_iam_role_policy_attachment.execution_managed,
    aws_iam_role_policy.execution_read_secret,
    aws_iam_role_policy_attachment.infrastructure_managed,
    aws_secretsmanager_secret_version.database_url,
  ]
}
