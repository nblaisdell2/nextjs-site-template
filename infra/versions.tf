terraform {
  required_version = ">= 1.10.0" # use_lockfile (S3-native state locking)

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # ECS Express Mode (aws_ecs_express_gateway_service) requires a recent
      # provider. Pin to the current 6.x line.
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
