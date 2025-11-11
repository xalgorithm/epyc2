# Work VM Configuration
# This file creates and manages the work.xalg.im VM

# =============================================================================
# Cloud-Init Configuration for Work VM
# =============================================================================

# Cloud-init user data for work VM
resource "proxmox_virtual_environment_file" "cloud_init_work" {
  depends_on = [null_resource.create_snippets_directory]

  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = <<-EOF
      #cloud-config
      hostname: work
      fqdn: work.xalg.im
      manage_etc_hosts: true
      package_update: true
      package_upgrade: true
      packages:
        - qemu-guest-agent
        - openssh-server
        - nfs-common
        - hstr
      users:
        - name: xalg
          sudo: ALL=(ALL) NOPASSWD:ALL
          groups: sudo
          shell: /bin/bash
          ssh_authorized_keys:
            - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFqb+pKAnvn5NLFR/v2utfFwYxuMj77yUIW1PdHs1yNL New-FS
      mounts:
        - [ "192.168.0.7:/data", "/data", "nfs", "defaults,_netdev", "0", "0" ]
      runcmd:
        - systemctl start qemu-guest-agent
        - systemctl enable qemu-guest-agent
        - mkdir -p /data
        - mount -a
        - systemctl daemon-reload
      EOF

    file_name = "cloud-init-work.yaml"
  }
}

# =============================================================================
# Work VM Definition
# =============================================================================

# Work VM - work.xalg.im (VM ID 110)
resource "proxmox_virtual_environment_vm" "work" {
  vm_id     = 110
  name      = "work"
  node_name = var.proxmox_node

  clone {
    vm_id = var.debian_template_id # You'll need to create a Debian 13 template
    full  = true
  }

  # VM Configuration
  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096 # 4GB
  }

  # SCSI Controller for iothread support
  scsi_hardware = "virtio-scsi-single"

  # Disk Configuration - 64GB
  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    iothread     = true
    size         = 64
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
        address = "${var.work_vm_ip}/24"
        gateway = var.vm_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_work.id
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

