resource "random_password" "db" {
  length  = 24
  special = false # keep it URL-safe for the connection string
}

# When use_latest_snapshot is true, find the newest snapshot for this instance
# (covers both the automated and the final snapshots RDS creates on destroy).
data "aws_db_snapshot" "latest" {
  count                  = var.use_latest_snapshot ? 1 : 0
  db_instance_identifier = "${var.project_name}-db"
  most_recent            = true
}

resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = var.db_publicly_accessible

  # Snapshot lifecycle: take a final snapshot on destroy, and optionally restore
  # from the latest snapshot on create (see var.use_latest_snapshot). This lets
  # you destroy the DB to save cost and bring it back later with its data.
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-db-final-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  snapshot_identifier = (
    var.use_latest_snapshot && length(data.aws_db_snapshot.latest) > 0
    ? data.aws_db_snapshot.latest[0].id
    : null
  )

  # Dev-friendly settings. Harden these for production.
  multi_az                = false
  deletion_protection     = false
  backup_retention_period = 1
  apply_immediately       = true

  lifecycle {
    # timestamp() in the final snapshot name changes every plan; and once
    # restored, we don't want a newer snapshot to force a replacement.
    ignore_changes = [final_snapshot_identifier, snapshot_identifier]
  }
}
