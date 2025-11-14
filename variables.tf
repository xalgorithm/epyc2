# Variable Definitions
# This file contains all input variable declarations for the infrastructure

# =============================================================================
# Cluster Configuration
# =============================================================================

variable "bootstrap_cluster" {
  description = "Whether Terraform should bootstrap the Kubernetes cluster (VM init, node setup, copy kubeconfig). Set to false if a control plane already exists and kubeconfig is present locally."
  type        = bool
  default     = true
}

variable "control_plane_ip" {
  description = "IP address of the control plane node"
  type        = string
}

variable "worker_ips" {
  description = "IP addresses of worker nodes"
  type        = list(string)
}

variable "work_vm_ip" {
  description = "IP address for work VM"
  type        = string
  default     = "192.168.0.50"
}

variable "worker_names" {
  description = "Names of worker nodes"
  type        = list(string)
  default     = ["prime", "wheeljack"]
}

# =============================================================================
# Rebellion Cluster Configuration
# =============================================================================

variable "rebellion_control_plane_ip" {
  description = "IP address of the rebellion control plane node (Luke)"
  type        = string
  default     = "192.168.0.40"
}

variable "rebellion_worker_ips" {
  description = "IP addresses of rebellion worker nodes (Leia, Han)"
  type        = list(string)
  default     = ["192.168.0.41", "192.168.0.42"]
}

variable "rebellion_vm_names" {
  description = "Names of rebellion cluster nodes"
  type        = list(string)
  default     = ["luke", "leia", "han"]
}

variable "rebellion_metallb_pool_start" {
  description = "Start IP for rebellion MetalLB pool"
  type        = string
  default     = "192.168.0.43"
}

variable "rebellion_metallb_pool_end" {
  description = "End IP for rebellion MetalLB pool"
  type        = string
  default     = "192.168.0.49"
}

# =============================================================================
# Kubernetes Configuration
# =============================================================================

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

# =============================================================================
# SSH Configuration
# =============================================================================

variable "ssh_user" {
  description = "SSH user for accessing VMs"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "metallb_pool_start" {
  description = "Start IP for MetalLB pool"
  type        = string
}

variable "metallb_pool_end" {
  description = "End IP for MetalLB pool"
  type        = string
}

variable "ingress_ip" {
  description = "Static IP for ingress-nginx LoadBalancer (must be in MetalLB pool)"
  type        = string
}

variable "syslog_ip" {
  description = "Static IP for syslog-ng receiver (for OPNsense logs, must be in MetalLB pool)"
  type        = string
  default     = "192.168.0.36"
}

variable "vm_gateway" {
  description = "Gateway IP for VM network"
  type        = string
}

# =============================================================================
# Ingress Hostnames
# =============================================================================

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

# =============================================================================
# Docker Hub Configuration
# =============================================================================

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

# =============================================================================
# Proxmox API Configuration
# =============================================================================

variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_user" {
  description = "Proxmox user"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Password for Proxmox monitoring user"
  type        = string
  default     = ""
  sensitive   = true
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID (format: user@realm!tokenname)"
  type        = string
  default     = ""
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification for Proxmox API"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

# =============================================================================
# Proxmox VM Configuration
# =============================================================================

variable "vm_template" {
  description = "VM template name to clone from"
  type        = string
  default     = "ubuntu-22.04-template"
}

variable "vm_template_id" {
  description = "VM template ID to clone from"
  type        = number
  default     = 9000
}

variable "debian_template_id" {
  description = "Debian VM template ID to clone from"
  type        = number
  default     = 9001
}

variable "vm_storage" {
  description = "Storage pool for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "vm_network_bridge" {
  description = "Network bridge for VMs"
  type        = string
  default     = "vmbr0"
}

# =============================================================================
# NFS Storage Configuration
# =============================================================================

variable "nfs_storage_server" {
  description = "NFS server IP address for Kubernetes storage"
  type        = string
}

variable "nfs_storage_path" {
  description = "NFS server path for Kubernetes storage"
  type        = string
  default     = "/data/kubernetes"
}

variable "nfs_ssh_user" {
  description = "SSH user for NFS server access"
  type        = string
  default     = "" # If empty, uses ssh_user
}

variable "nfs_ssh_private_key_path" {
  description = "SSH private key path for NFS server access"
  type        = string
  default     = "" # If empty, uses ssh_private_key_path
}

# =============================================================================
# Backup Configuration
# =============================================================================

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

# =============================================================================
# Home Assistant Integration
# =============================================================================

variable "home_assistant_enabled" {
  description = "Enable Home Assistant monitoring integration"
  type        = bool
  default     = true
}

variable "home_assistant_ip" {
  description = "IP address of Home Assistant instance"
  type        = string
  default     = "192.168.0.31"
}

variable "home_assistant_port" {
  description = "Port for Home Assistant web interface"
  type        = number
  default     = 8123
}

variable "home_assistant_api_token" {
  description = "Home Assistant Long-Lived Access Token for API authentication"
  type        = string
  default     = ""
  sensitive   = true
}

