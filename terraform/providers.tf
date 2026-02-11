# Provider Configurations
# This file contains all provider configurations for the infrastructure

# Kubernetes Provider
# IMPORTANT: For fresh deployments, use a two-stage apply:
# Stage 1: Create VMs and cluster
#   terraform apply -target=module.cluster_bootstrap -var="bootstrap_cluster=true"
# Stage 2: Create Kubernetes resources  
#   terraform apply -var="bootstrap_cluster=true"
#
# OR use the helper script: ./scripts/deployment/deploy-full-stack.sh
provider "kubernetes" {
  config_path = "~/.kube/config"
  insecure    = true

  # Ignore connection errors during plan when cluster doesn't exist
  ignore_annotations = []
}

# Helm Provider
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
    insecure    = true
  }
}

# Proxmox Provider Configuration
provider "proxmox" {
  endpoint = var.proxmox_api_url

  # Use API token if provided, otherwise fall back to username/password
  api_token = var.proxmox_api_token_id != "" ? "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}" : null
  username  = var.proxmox_api_token_id != "" ? null : var.proxmox_user
  password  = var.proxmox_api_token_id != "" ? null : var.proxmox_password

  insecure = var.proxmox_tls_insecure

  # SSH configuration for file uploads (cloud-init, snippets, etc.)
  ssh {
    agent    = true
    username = var.nfs_ssh_user != "" ? var.nfs_ssh_user : "root"
  }
}

