terraform {
  # Infrastructure Manager (which Cloud Marketplace deploys with) runs Terraform up to 1.5.7.
  required_version = ">= 1.5, < 2.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.14, < 8.0"
    }
  }
}

