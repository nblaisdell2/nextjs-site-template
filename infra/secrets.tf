# The full Postgres connection string lives in Secrets Manager. App Runner
# injects it into the container as the DATABASE_URL env var at runtime, so the
# credential never appears in the task definition or image.

locals {
  # No sslmode in the URL: TLS is controlled by the app (lib/db.ts), which uses
  # the RDS CA bundle baked into the image for full verification (verify-full).
  # Leaving sslmode out avoids pg's connection-string parser overriding that.
  database_url = format(
    "postgres://%s:%s@%s:%s/%s",
    var.db_username,
    random_password.db.result,
    aws_db_instance.main.address,
    aws_db_instance.main.port,
    var.db_name,
  )
}

resource "aws_secretsmanager_secret" "database_url" {
  name        = "${var.project_name}/database-url"
  description = "Postgres connection string for ${var.project_name}"

  # Allow re-creation under the same name without the 30-day recovery wait
  # while iterating. Raise for production.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = local.database_url
}
