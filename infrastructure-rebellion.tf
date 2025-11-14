# Rebellion Cluster Infrastructure Configuration
# This file creates and manages the VMs for the Rebellion Kubernetes cluster
# Cluster: rebellion (Luke, Leia, Han)

# =============================================================================
# Cloud-Init Configuration Files
# =============================================================================

# Cloud-init user data for Luke (control plane)
resource "proxmox_virtual_environment_file" "cloud_init_luke" {
  depends_on = [null_resource.create_snippets_directory]

  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = <<-EOF
      #cloud-config
      hostname: luke
      fqdn: luke.rebellion.local
      manage_etc_hosts: true
      package_update: true
      package_upgrade: false
      packages:
        - qemu-guest-agent
        - openssh-server
        - nfs-common
        - git
      users:
        - name: xalg
          sudo: ALL=(ALL) NOPASSWD:ALL
          groups: sudo
          shell: /bin/bash
          ssh_authorized_keys:
            - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFqb+pKAnvn5NLFR/v2utfFwYxuMj77yUIW1PdHs1yNL New-FS
      runcmd:
        - systemctl start qemu-guest-agent
        - systemctl enable qemu-guest-agent
        - swapoff -a
        - sed -i '/ swap / s/^/#/' /etc/fstab
      EOF

    file_name = "cloud-init-luke.yaml"
  }
}

# Cloud-init user data for Leia (worker 1)
resource "proxmox_virtual_environment_file" "cloud_init_leia" {
  depends_on = [null_resource.create_snippets_directory]

  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = <<-EOF
      #cloud-config
      hostname: leia
      fqdn: leia.rebellion.local
      manage_etc_hosts: true
      package_update: true
      package_upgrade: false
      packages:
        - qemu-guest-agent
        - openssh-server
        - nfs-common
        - git
      users:
        - name: xalg
          sudo: ALL=(ALL) NOPASSWD:ALL
          groups: sudo
          shell: /bin/bash
          ssh_authorized_keys:
            - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFqb+pKAnvn5NLFR/v2utfFwYxuMj77yUIW1PdHs1yNL New-FS
      runcmd:
        - systemctl start qemu-guest-agent
        - systemctl enable qemu-guest-agent
        - swapoff -a
        - sed -i '/ swap / s/^/#/' /etc/fstab
      EOF

    file_name = "cloud-init-leia.yaml"
  }
}

# Cloud-init user data for Han (worker 2)
resource "proxmox_virtual_environment_file" "cloud_init_han" {
  depends_on = [null_resource.create_snippets_directory]

  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = <<-EOF
      #cloud-config
      hostname: han
      fqdn: han.rebellion.local
      manage_etc_hosts: true
      package_update: true
      package_upgrade: false
      packages:
        - qemu-guest-agent
        - openssh-server
        - nfs-common
        - git
      users:
        - name: xalg
          sudo: ALL=(ALL) NOPASSWD:ALL
          groups: sudo
          shell: /bin/bash
          ssh_authorized_keys:
            - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFqb+pKAnvn5NLFR/v2utfFwYxuMj77yUIW1PdHs1yNL New-FS
      runcmd:
        - systemctl start qemu-guest-agent
        - systemctl enable qemu-guest-agent
        - swapoff -a
        - sed -i '/ swap / s/^/#/' /etc/fstab
      EOF

    file_name = "cloud-init-han.yaml"
  }
}

# =============================================================================
# Virtual Machine Definitions
# =============================================================================

# Control Plane VM - Luke (VM ID 120)
resource "proxmox_virtual_environment_vm" "luke" {
  vm_id     = 120
  name      = "luke"
  node_name = var.proxmox_node

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  # VM Configuration
  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192 # 8GB
  }

  # SCSI Controller for iothread support
  scsi_hardware = "virtio-scsi-single"

  # Disk Configuration - 128GB
  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    iothread     = true
    size         = 128
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
        address = "${var.rebellion_control_plane_ip}/24"
        gateway = var.vm_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_luke.id
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
      agent,
    ]
  }
}

# Worker VM 1 - Leia (VM ID 121)
resource "proxmox_virtual_environment_vm" "leia" {
  vm_id     = 121
  name      = "leia"
  node_name = var.proxmox_node

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  # VM Configuration
  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192 # 8GB
  }

  # SCSI Controller for iothread support
  scsi_hardware = "virtio-scsi-single"

  # Disk Configuration - 128GB
  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    iothread     = true
    size         = 128
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
        address = "${var.rebellion_worker_ips[0]}/24"
        gateway = var.vm_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_leia.id
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
      agent,
    ]
  }
}

# Worker VM 2 - Han (VM ID 122)
resource "proxmox_virtual_environment_vm" "han" {
  vm_id     = 122
  name      = "han"
  node_name = var.proxmox_node

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  # VM Configuration
  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192 # 8GB
  }

  # SCSI Controller for iothread support
  scsi_hardware = "virtio-scsi-single"

  # Disk Configuration - 128GB
  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    iothread     = true
    size         = 128
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
        address = "${var.rebellion_worker_ips[1]}/24"
        gateway = var.vm_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_han.id
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
      agent,
    ]
  }
}

