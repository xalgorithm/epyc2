# Proxmox VM Creation Configuration
# This file creates the VMs needed for the Kubernetes cluster using bpg/proxmox provider

# Proxmox Provider Configuration
provider "proxmox" {
  endpoint = var.proxmox_api_url

  # Use API token if provided, otherwise fall back to username/password
  api_token = var.proxmox_api_token_id != "" ? "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}" : null
  username  = var.proxmox_api_token_id != "" ? null : var.proxmox_user
  password  = var.proxmox_api_token_id != "" ? null : var.proxmox_password

  insecure = var.proxmox_tls_insecure
}

# Control Plane VM - Bumblebee
resource "proxmox_virtual_environment_vm" "bumblebee" {
  name      = "bumblebee"
  node_name = var.proxmox_node

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  # VM Configuration
  cpu {
    cores = 8
    type  = "host"
  }

  memory {
    dedicated = 16384
  }

  # SCSI Controller for iothread support
  scsi_hardware = "virtio-scsi-single"

  # Disk Configuration - 256GB
  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    iothread     = true
    size         = 256
  }

  # Network Configuration
  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  # Cloud-init configuration
  initialization {
    ip_config {
      ipv4 {
        address = "${var.control_plane_ip}/24"
        gateway = var.vm_gateway
      }
    }

    user_account {
      username = var.ssh_user
      keys     = [trimspace(file("${var.ssh_private_key_path}.pub"))]
    }
  }

  # VM Settings
  agent {
    enabled = true
  }

  started = true
  on_boot = true

  # Minimal lifecycle rules for stability
  lifecycle {
    ignore_changes = [
      # Ignore agent changes
      agent,
    ]
  }
}

# Worker VM 1 - Prime
resource "proxmox_virtual_environment_vm" "prime" {
  name      = "prime"
  node_name = var.proxmox_node

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  # VM Configuration
  cpu {
    cores = 8
    type  = "host"
  }

  memory {
    dedicated = 16384
  }

  # SCSI Controller for iothread support
  scsi_hardware = "virtio-scsi-single"

  # Disk Configuration - 256GB
  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    iothread     = true
    size         = 256
  }

  # Network Configuration
  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  # Cloud-init configuration
  initialization {
    ip_config {
      ipv4 {
        address = "${var.worker_ips[0]}/24"
        gateway = var.vm_gateway
      }
    }

    user_account {
      username = var.ssh_user
      keys     = [trimspace(file("${var.ssh_private_key_path}.pub"))]
    }
  }

  # VM Settings
  agent {
    enabled = true
  }

  started = true
  on_boot = true

  # Minimal lifecycle rules for stability
  lifecycle {
    ignore_changes = [
      # Ignore agent changes
      agent,
    ]
  }
}

# Worker VM 2 - Wheeljack
resource "proxmox_virtual_environment_vm" "wheeljack" {
  name      = "wheeljack"
  node_name = var.proxmox_node

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  # VM Configuration
  cpu {
    cores = 8
    type  = "host"
  }

  memory {
    dedicated = 16384
  }

  # SCSI Controller for iothread support
  scsi_hardware = "virtio-scsi-single"

  # Disk Configuration - 256GB
  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    iothread     = true
    size         = 256
  }

  # Network Configuration
  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  # Cloud-init configuration
  initialization {
    ip_config {
      ipv4 {
        address = "${var.worker_ips[1]}/24"
        gateway = var.vm_gateway
      }
    }

    user_account {
      username = var.ssh_user
      keys     = [trimspace(file("${var.ssh_private_key_path}.pub"))]
    }
  }

  # VM Settings
  agent {
    enabled = true
  }

  started = true
  on_boot = true

  # Minimal lifecycle rules for stability
  lifecycle {
    ignore_changes = [
      # Ignore agent changes
      agent,
    ]
  }
}

# Output VM information
output "vm_info" {
  description = "Created VM information"
  value = {
    bumblebee = {
      name = proxmox_virtual_environment_vm.bumblebee.name
      ip   = var.control_plane_ip
      role = "control-plane"
      disk = "256GB"
    }
    prime = {
      name = proxmox_virtual_environment_vm.prime.name
      ip   = var.worker_ips[0]
      role = "worker"
      disk = "256GB"
    }
    wheeljack = {
      name = proxmox_virtual_environment_vm.wheeljack.name
      ip   = var.worker_ips[1]
      role = "worker"
      disk = "256GB"
    }
  }
}