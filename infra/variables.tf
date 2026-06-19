variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "budget-app"
}

# ---- Database ----
variable "db_name" {
  description = "Initial Postgres database name."
  type        = string
  default     = "budget"
}

variable "db_username" {
  description = "Master DB username."
  type        = string
  default     = "budgetadmin"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS storage in GiB."
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = <<-EOT
    Postgres engine version. Specifying only the MAJOR version (e.g. "16")
    lets RDS pick the latest supported minor in your region, which avoids
    "Cannot find version X" errors. To pin an exact minor, list what's
    available first:
      aws rds describe-db-engine-versions --engine postgres \
        --query "DBEngineVersions[].EngineVersion" --output table --region <your-region>
  EOT
  type    = string
  default = "17"
}

variable "db_publicly_accessible" {
  description = <<-EOT
    If true, RDS gets a public endpoint so you can run migrations from your
    laptop. Convenient for development. Set false for production and run
    migrations from inside the VPC instead. When true, set my_ip_cidr.
  EOT
  type        = bool
  default     = true
}

variable "my_ip_cidr" {
  description = <<-EOT
    Your public IP in CIDR form (e.g. "203.0.113.4/32") allowed to reach RDS
    on 5432. Only used when db_publicly_accessible = true. Find it with:
    curl -s https://checkip.amazonaws.com
  EOT
  type    = string
  default = null
}

variable "use_latest_snapshot" {
  description = <<-EOT
    Restore the database from the most recent snapshot instead of creating it
    empty. Leave false for the very first create. After you've let it create a
    final snapshot (any `terraform destroy` makes one), set true so a later
    apply brings the DB back WITH its data. Lets you tear the DB down to save
    money and restore it on demand.
  EOT
  type    = bool
  default = false
}

# ---- App / container ----
variable "container_port" {
  description = "Port the Next.js server listens on."
  type        = number
  default     = 3000
}

variable "image_tag" {
  description = "ECR image tag App Runner runs."
  type        = string
  default     = "latest"
}

variable "app_cpu" {
  description = "ECS task CPU units (powers of 2, 256-4096). e.g. 256, 512, 1024."
  type        = string
  default     = "256"
}

variable "app_memory" {
  description = "ECS task memory in MiB (512-8192). Must be valid for the CPU. e.g. 512, 1024."
  type        = string
  default     = "512"
}

variable "deploy_service" {
  description = <<-EOT
    Create the ECS Express service. Leave false for the FIRST apply (which
    creates ECR/RDS/secret); push an image and run migrations; then set true
    and apply again to launch the service. See README.
  EOT
  type    = bool
  default = false
}

# ---- CI/CD (GitHub Actions OIDC) ----
variable "github_repo" {
  description = <<-EOT
    GitHub repo (owner/name) allowed to assume the deploy role via OIDC, e.g.
    "nblaisdell2/nextjs-test". Leave null to skip creating the CI role.
  EOT
  type    = string
  default = null
}

variable "create_oidc_provider" {
  description = <<-EOT
    Create the GitHub Actions OIDC provider in this account. An account can only
    have ONE provider for token.actions.githubusercontent.com. If you already
    have one (e.g. from a previous project), leave this false and it will be
    referenced instead.
  EOT
  type    = bool
  default = false
}

variable "state_bucket" {
  description = <<-EOT
    Optional override for the S3 Terraform state bucket. Leave empty to use the
    convention "<project_name>-tfstate" (which backend.hcl and bootstrap-backend
    also use). The CI deploy role is granted read/write on it.
  EOT
  type    = string
  default = ""
}
