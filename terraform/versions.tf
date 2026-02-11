# Terraform Version and Provider Requirements
# This file defines the minimum Terraform version and required provider versions

terraform {
  required_version = ">= 1.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    remote = {
      source  = "tenstad/remote"
      version = "~> 0.1"
    }

    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.46"
    }
  }
}

