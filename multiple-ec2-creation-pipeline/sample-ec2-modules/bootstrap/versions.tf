terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Local backend intentionally — this state can't live in the bucket it creates.
  # Keep the resulting terraform.tfstate out of git (see .gitignore) and safe.
}

provider "aws" {
  region = var.region
}
