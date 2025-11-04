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

  # SSH configuration for file uploads (cloud-init, snippets, etc.)
  ssh {
    agent    = true
    username = var.nfs_ssh_user != "" ? var.nfs_ssh_user : "root"
  }
}

# Ensure snippets directory exists on Proxmox host
# Note: This requires passwordless sudo or the directory to already exist
resource "null_resource" "create_snippets_directory" {
  provisioner "local-exec" {
    command = <<-EOT
      # Try to create directory, ignore errors if it already exists or sudo requires password
      ssh -o StrictHostKeyChecking=no ${var.nfs_ssh_user}@${var.nfs_storage_server} \
        "sudo -n mkdir -p /var/lib/vz/snippets 2>/dev/null && sudo -n chmod 755 /var/lib/vz/snippets 2>/dev/null || echo 'Note: Snippets directory may need manual creation. Run: sudo mkdir -p /var/lib/vz/snippets && sudo chmod 755 /var/lib/vz/snippets'" || true
    EOT
  }
}

# Cloud-init user data for control plane (bumblebee)
resource "proxmox_virtual_environment_file" "cloud_init_bumblebee" {
  depends_on = [null_resource.create_snippets_directory]
  
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = <<-EOF
      #cloud-config
      hostname: bumblebee
      fqdn: bumblebee.local
      manage_etc_hosts: true
      package_update: true
      package_upgrade: false
      packages:
        - qemu-guest-agent
        - nfs-common
      users:
        - name: ${var.ssh_user}
          sudo: ALL=(ALL) NOPASSWD:ALL
          groups: sudo
          shell: /bin/bash
          ssh_authorized_keys:
            - ${trimspace(file("${var.ssh_private_key_path}.pub"))}
      runcmd:
        - systemctl start qemu-guest-agent
        - systemctl enable qemu-guest-agent
      EOF

    file_name = "cloud-init-bumblebee.yaml"
  }
}

# Cloud-init user data for worker 1 (prime)
resource "proxmox_virtual_environment_file" "cloud_init_prime" {
  depends_on = [null_resource.create_snippets_directory]
  
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = <<-EOF
      #cloud-config
      hostname: prime
      fqdn: prime.local
      manage_etc_hosts: true
      package_update: true
      package_upgrade: false
      packages:
        - qemu-guest-agent
        - nfs-common
      users:
        - name: ${var.ssh_user}
          sudo: ALL=(ALL) NOPASSWD:ALL
          groups: sudo
          shell: /bin/bash
          ssh_authorized_keys:
            - ${trimspace(file("${var.ssh_private_key_path}.pub"))}
      runcmd:
        - systemctl start qemu-guest-agent
        - systemctl enable qemu-guest-agent
      EOF

    file_name = "cloud-init-prime.yaml"
  }
}

# Cloud-init user data for worker 2 (wheeljack)
resource "proxmox_virtual_environment_file" "cloud_init_wheeljack" {
  depends_on = [null_resource.create_snippets_directory]
  
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = <<-EOF
      #cloud-config
      hostname: wheeljack
      fqdn: wheeljack.local
      manage_etc_hosts: true
      package_update: true
      package_upgrade: false
      packages:
        - qemu-guest-agent
        - nfs-common
      users:
        - name: ${var.ssh_user}
          sudo: ALL=(ALL) NOPASSWD:ALL
          groups: sudo
          shell: /bin/bash
          ssh_authorized_keys:
            - ${trimspace(file("${var.ssh_private_key_path}.pub"))}
      runcmd:
        - systemctl start qemu-guest-agent
        - systemctl enable qemu-guest-agent
      EOF

    file_name = "cloud-init-wheeljack.yaml"
  }
}

# Control Plane VM - Bumblebee (VM ID 100)
resource "proxmox_virtual_environment_vm" "bumblebee" {
  vm_id     = 100
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

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_bumblebee.id
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

# Worker VM 1 - Prime (VM ID 103)
resource "proxmox_virtual_environment_vm" "prime" {
  vm_id     = 103
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

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_prime.id
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

# Worker VM 2 - Wheeljack (VM ID 101)
resource "proxmox_virtual_environment_vm" "wheeljack" {
  vm_id     = 101
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

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_wheeljack.id
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
      vm_id = proxmox_virtual_environment_vm.bumblebee.vm_id
      name  = proxmox_virtual_environment_vm.bumblebee.name
      ip    = var.control_plane_ip
      role  = "control-plane"
      disk  = "256GB"
    }
    prime = {
      vm_id = proxmox_virtual_environment_vm.prime.vm_id
      name  = proxmox_virtual_environment_vm.prime.name
      ip    = var.worker_ips[0]
      role  = "worker"
      disk  = "256GB"
    }
    wheeljack = {
      vm_id = proxmox_virtual_environment_vm.wheeljack.vm_id
      name  = proxmox_virtual_environment_vm.wheeljack.name
      ip    = var.worker_ips[1]
      role  = "worker"
      disk  = "256GB"
    }
  }
}