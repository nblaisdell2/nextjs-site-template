# Use the account's default VPC and its subnets. This keeps the scaffold cheap
# and simple (no NAT gateway). For production you'd typically run RDS in private
# subnets of a dedicated VPC.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group attached to the ECS Express task ENIs. RDS allows this SG on
# 5432; Express Mode manages the load balancer's own security groups.
resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${var.project_name}-ecs-tasks-"
  description = "ECS Express task egress"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Intentionally NO create_before_destroy: with it, a targeted CI apply on the
  # ECS service would cascade into dependent SGs (e.g. rds) and try to modify
  # them. name_prefix already avoids name collisions on replacement.
}

# Security group for RDS: allow Postgres from the ECS tasks, and optionally from
# your IP for running migrations locally.
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-"
  description = "Postgres access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Postgres from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  dynamic "ingress" {
    for_each = var.db_publicly_accessible && var.my_ip_cidr != null ? [1] : []
    content {
      description = "Postgres from my IP (migrations)"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [var.my_ip_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # No create_before_destroy — see the note on the ecs_tasks security group.
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db"
  subnet_ids = data.aws_subnets.default.ids
}
