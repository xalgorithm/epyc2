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
  }
}

# Configure the Kubernetes Provider
provider "kubernetes" {
  config_path = "~/.kube/config"
  insecure    = true
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
    insecure    = true
  }
}

# Variables
variable "control_plane_ip" {
  description = "IP address of the control plane node"
  type        = string
}

variable "worker_ips" {
  description = "IP addresses of worker nodes"
  type        = list(string)
}

variable "worker_names" {
  description = "Names of worker nodes"
  type        = list(string)
  default     = ["prime", "wheeljack"]
}

variable "ssh_user" {
  description = "SSH user for accessing VMs"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
}

variable "metallb_pool_start" {
  description = "Start IP for MetalLB pool"
  type        = string
}

variable "metallb_pool_end" {
  description = "Start IP for MetalLB pool"
  type        = string
}

variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "pod_network_cidr" {
  description = "Pod network CIDR"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Service network CIDR"
  type        = string
  default     = "10.96.0.0/12"
}

# Docker Hub credentials for image pulling
variable "dockerhub_username" {
  description = "Docker Hub username"
  type        = string
  default     = ""
}

variable "dockerhub_password" {
  description = "Docker Hub password or access token"
  type        = string
  default     = ""
  sensitive   = true
}

variable "dockerhub_email" {
  description = "Docker Hub email"
  type        = string
  default     = ""
}

# Proxmox monitoring credentials (for monitoring only, not VM management)
variable "proxmox_password" {
  description = "Password for Proxmox monitoring user"
  type        = string
  default     = ""
  sensitive   = true
}

# Backup configuration
variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "nfs_server_ip" {
  description = "NFS server IP for backup storage"
  type        = string
}

variable "nfs_backup_path" {
  description = "NFS path for backup storage"
  type        = string
  default     = "/data/kubernetes/backups"
}

# VM network configuration (for reference only, VMs managed externally)
variable "vm_gateway" {
  description = "Gateway IP for VM network"
  type        = string
}

# NFS Storage variables
variable "nfs_storage_server" {
  description = "NFS server IP address for Kubernetes storage"
  type        = string
}

variable "nfs_storage_path" {
  description = "NFS server path for Kubernetes storage"
  type        = string
  default     = "/data/kubernetes"
}


variable "bootstrap_cluster" {
  description = "Whether Terraform should bootstrap the Kubernetes cluster (VM init, node setup, copy kubeconfig). Set to false if a control plane already exists and kubeconfig is present locally."
  type        = bool
  default     = true
}

# Ingress settings
variable "ingress_ip" {
  description = "Static IP for ingress-nginx LoadBalancer (must be in MetalLB pool)"
  type        = string
}

variable "grafana_host" {
  description = "Hostname for Grafana Ingress"
  type        = string
  default     = "grafana.home"
}

variable "prometheus_host" {
  description = "Hostname for Prometheus Ingress"
  type        = string
  default     = "prometheus.home"
}

variable "loki_host" {
  description = "Hostname for Loki Ingress"
  type        = string
  default     = "loki.home"
}

variable "mimir_host" {
  description = "Hostname for Mimir Ingress"
  type        = string
  default     = "mimir.home"
}

variable "mylar_host" {
  description = "Hostname for Mylar Ingress"
  type        = string
  default     = "mylar.home"
}





