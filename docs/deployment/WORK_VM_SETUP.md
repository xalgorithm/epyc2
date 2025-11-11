# Work VM (work.xalg.im) Setup Guide

This guide covers the setup and deployment of the work.xalg.im VM - a Debian 13 server for general workload usage.

## Overview

- **Hostname**: work.xalg.im
- **VM ID**: 110
- **IP Address**: 192.168.0.50
- **Resources**:
  - CPU: 2 cores
  - Memory: 4GB
  - Disk: 64GB
- **OS**: Debian 13 (Trixie)
- **User**: xalg (with sudo access)
- **NFS Mount**: 192.168.0.7:/data → /data

## Prerequisites

### 1. Create Debian 13 Template in Proxmox

Before deploying the VM, you need to create a Debian 13 template in Proxmox. Here's how:

#### Option A: Quick Method (Clone from existing template)

If you already have a Debian template:

```bash
# SSH to Proxmox host
ssh root@192.168.0.7

# Clone existing template to create Debian template
qm clone 9000 9001 --name debian-13-template
```

#### Option B: Create from Scratch

1. **Download Debian 13 Cloud Image**:

```bash
# SSH to Proxmox host
ssh root@192.168.0.7

# Create a VM
qm create 9001 --name debian-13-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0

# Download Debian 13 cloud image
cd /var/lib/vz/template/iso
wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2

# Import the disk
qm importdisk 9001 debian-13-generic-amd64.qcow2 local-lvm

# Configure the VM
qm set 9001 --scsihw virtio-scsi-single
qm set 9001 --scsi0 local-lvm:vm-9001-disk-0
qm set 9001 --boot c --bootdisk scsi0
qm set 9001 --ide2 local-lvm:cloudinit
qm set 9001 --serial0 socket --vga serial0
qm set 9001 --agent enabled=1

# Convert to template
qm template 9001
```

2. **Verify the template**:

```bash
qm list | grep debian
```

You should see VM 9001 with the name `debian-13-template`.

## VM Configuration

The VM is configured via cloud-init with the following settings:

### Packages Installed
- `qemu-guest-agent` - Proxmox integration
- `openssh-server` - SSH access
- `nfs-common` - NFS client support
- `hstr` - Better bash history tool

### User Configuration
- **Username**: xalg
- **Sudo**: Full sudo access without password
- **SSH Key**: ED25519 key from ~/.ssh/id_ed25519.pub
- **Shell**: /bin/bash

### Network Configuration
- **IP**: 192.168.0.50/24
- **Gateway**: 192.168.0.1
- **Hostname**: work.xalg.im

### NFS Mount
- **Server**: 192.168.0.7
- **Share**: /data
- **Mount Point**: /data
- **Options**: defaults,_netdev
- **Auto-mount**: Yes (configured in /etc/fstab via cloud-init)

## Deployment

### Step 1: Initialize Terraform (if not already done)

```bash
cd /Users/xalg/dev/terraform/epyc2
terraform init
```

### Step 2: Validate Configuration

```bash
terraform validate
```

### Step 3: Plan the Deployment

```bash
terraform plan -target=proxmox_virtual_environment_vm.work
```

### Step 4: Deploy the VM

```bash
terraform apply -target=proxmox_virtual_environment_vm.work
```

### Step 5: Verify Deployment

Check the outputs:

```bash
terraform output vm_info
```

You should see the work VM details:

```hcl
work = {
  disk      = "64GB"
  fqdn      = "work.xalg.im"
  ip        = "192.168.0.50"
  name      = "work"
  nfs_mount = "192.168.0.7:/data -> /data"
  role      = "standalone"
  vm_id     = 110
}
```

## Post-Deployment

### SSH Access

Wait a few minutes for cloud-init to complete, then connect:

```bash
ssh xalg@192.168.0.50
```

Or using the hostname (if DNS is configured):

```bash
ssh xalg@work.xalg.im
```

### Verify Installation

Once connected, verify everything is working:

```bash
# Check hostname
hostname -f
# Expected: work.xalg.im

# Check NFS mount
df -h | grep /data
# Expected: 192.168.0.7:/data mounted on /data

# Check packages
dpkg -l | grep -E "nfs-common|hstr|openssh-server"
# Expected: All three packages should be listed

# Check qemu-guest-agent
systemctl status qemu-guest-agent
# Expected: active (running)

# Test NFS access
ls -la /data
touch /data/test-file
rm /data/test-file
```

### Configure hstr

For better bash history management with hstr:

```bash
# Add to ~/.bashrc
echo 'export HSTR_CONFIG=hicolor' >> ~/.bashrc
echo 'export HISTFILE=~/.bash_history' >> ~/.bashrc
echo 'export HISTSIZE=10000' >> ~/.bashrc
echo 'export HISTFILESIZE=10000' >> ~/.bashrc
echo 'bind '"'"'"\C-r": "\C-a hstr -- \C-j"'"'"'' >> ~/.bashrc
source ~/.bashrc
```

Now you can press `Ctrl+R` to use hstr for history search.

## Troubleshooting

### VM Won't Start

Check Proxmox logs:

```bash
ssh root@192.168.0.7
qm status 110
journalctl -u pve-firewall
```

### Can't SSH

1. Check VM is running:
   ```bash
   ssh root@192.168.0.7 "qm status 110"
   ```

2. Check cloud-init status from Proxmox console:
   ```bash
   # Open Proxmox web UI → VM 110 → Console
   # Login as xalg (if prompted for password, cloud-init may have failed)
   sudo cloud-init status --long
   ```

3. Verify network connectivity:
   ```bash
   ping 192.168.0.50
   ```

### NFS Mount Fails

1. Check NFS server is accessible:
   ```bash
   showmount -e 192.168.0.7
   ```

2. Manually mount from the VM:
   ```bash
   ssh xalg@192.168.0.50
   sudo mount -t nfs 192.168.0.7:/data /data
   sudo mount -a
   ```

3. Check mount in fstab:
   ```bash
   cat /etc/fstab | grep data
   ```

### Cloud-Init Issues

View cloud-init logs on the VM:

```bash
ssh xalg@192.168.0.50
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log
```

## VM Management

### Stop the VM

```bash
terraform destroy -target=proxmox_virtual_environment_vm.work
```

Or via Proxmox:

```bash
ssh root@192.168.0.7 "qm stop 110"
```

### Delete the VM

```bash
# First destroy with Terraform
terraform destroy -target=proxmox_virtual_environment_vm.work

# Or manually via Proxmox
ssh root@192.168.0.7 "qm destroy 110"
```

### Clone the VM

```bash
ssh root@192.168.0.7 "qm clone 110 111 --name work-clone"
```

## Configuration Files

### Terraform Configuration
- **Main file**: `infrastructure-work.tf`
- **Variables**: `variables.tf` (work_vm_ip, debian_template_id)
- **Values**: `terraform.tfvars` (work_vm_ip = "192.168.0.50")
- **Outputs**: `outputs.tf` (vm_info.work)

### Cloud-Init
The cloud-init configuration is stored as a snippet in Proxmox at:
- **Path**: `/var/lib/vz/snippets/cloud-init-work.yaml`
- **Resource**: `proxmox_virtual_environment_file.cloud_init_work`

## Security Notes

1. The xalg user has passwordless sudo - ensure SSH key security
2. NFS mount uses default options - consider adding `nosuid,nodev` for security
3. The VM is accessible on the local network (192.168.0.0/24)
4. Firewall rules may need to be configured based on your requirements

## Additional Configuration

### Install Additional Packages

```bash
ssh xalg@192.168.0.50
sudo apt update
sudo apt install -y <package-name>
```

### Configure Static Routes

If you need additional network routes:

```bash
# Add to /etc/network/interfaces or use netplan
sudo ip route add <network> via <gateway>
```

### Set Up Automatic Updates

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

## Resources

- [Debian Cloud Images](https://cloud.debian.org/images/cloud/)
- [Proxmox Cloud-Init](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
- [hstr GitHub](https://github.com/dvorka/hstr)

## Summary

The work.xalg.im VM provides a clean Debian 13 environment with:
- Pre-configured user account with SSH access
- NFS share automatically mounted
- Essential tools pre-installed
- Full sudo access for administrative tasks
- Integration with your existing infrastructure

For questions or issues, refer to the main project documentation or open an issue.

