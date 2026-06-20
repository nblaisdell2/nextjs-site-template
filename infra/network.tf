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

# Security group for RDS. Its rules are managed as SEPARATE resources below — NOT
# inline — so this SG references nothing and is byte-for-byte identical in every
# environment. That keeps it out of CI's targeted deploy graph: CI can't drift it
# and try to revoke your migration rule. (Don't add inline ingress/egress here;
# mixing inline + separate rules makes them fight each other.)
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-"
  description = "Postgres access"
  vpc_id      = data.aws_vpc.default.id
}

# Always: allow Postgres from the ECS tasks.
resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Postgres from ECS tasks"
  referenced_security_group_id = aws_security_group.ecs_tasks.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# Optional (laptop only): allow Postgres from your IP for running migrations.
# This is a standalone resource, so CI's targeted deploy never includes it.
resource "aws_vpc_security_group_ingress_rule" "rds_from_my_ip" {
  count             = var.db_publicly_accessible && var.my_ip_cidr != null ? 1 : 0
  security_group_id = aws_security_group.rds.id
  description       = "Postgres from my IP (migrations)"
  cidr_ipv4         = var.my_ip_cidr
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "rds_all_out" {
  security_group_id = aws_security_group.rds.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db"
  subnet_ids = data.aws_subnets.default.ids
}
