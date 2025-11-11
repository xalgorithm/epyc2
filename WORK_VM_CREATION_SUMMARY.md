# Work VM Creation Summary

This document summarizes the Terraform configuration created for the `work.xalg.im` Debian 13 server VM.

## 📋 Overview

A new Debian 13 server VM has been configured with the following specifications:

| Property | Value |
|----------|-------|
| **Hostname** | work.xalg.im |
| **VM ID** | 110 |
| **IP Address** | 192.168.0.50/24 |
| **Gateway** | 192.168.0.1 |
| **OS** | Debian 13 (Trixie) |
| **CPU** | 2 cores |
| **Memory** | 4GB |
| **Disk** | 64GB |
| **User** | xalg (with sudo access) |
| **NFS Mount** | 192.168.0.7:/data → /data |

## 📁 Files Created

### 1. Terraform Configuration
**`infrastructure-work.tf`** - Main VM configuration file
- Cloud-init snippet configuration
- VM resource definition with specified parameters
- Automatic NFS mount setup

### 2. Variable Definitions
**`variables.tf`** - Added variables:
- `debian_template_id` - Debian 13 template ID (default: 9001)
- `work_vm_ip` - IP address for work VM (default: 192.168.0.50)

### 3. Variable Values
**`terraform.tfvars`** - Updated with:
- `work_vm_ip = "192.168.0.50"`
- `debian_template_id = 9001`

### 4. Outputs
**`outputs.tf`** - Added work VM to output:
```hcl
work = {
  vm_id     = 110
  name      = "work"
  ip        = "192.168.0.50"
  role      = "standalone"
  disk      = "64GB"
  fqdn      = "work.xalg.im"
  nfs_mount = "192.168.0.7:/data -> /data"
}
```

### 5. Documentation
**`docs/deployment/WORK_VM_SETUP.md`** - Comprehensive setup guide including:
- Prerequisites and template creation
- Deployment instructions
- Post-deployment verification
- Troubleshooting guide
- Security notes

### 6. Helper Scripts

**`scripts/deployment/create-debian-template.sh`** - Automated Debian 13 template creation
- Downloads Debian 13 cloud image
- Creates VM template (ID 9001)
- Configures cloud-init support
- Enables QEMU guest agent

**`scripts/deployment/deploy-work-vm.sh`** - One-command VM deployment
- Checks prerequisites
- Verifies Debian template exists
- Deploys VM with Terraform
- Waits for VM to be ready
- Verifies configuration

## 🔧 VM Configuration Details

### Cloud-Init Configuration

The VM is configured via cloud-init with:

```yaml
hostname: work
fqdn: work.xalg.im
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
  - ["192.168.0.7:/data", "/data", "nfs", "defaults,_netdev", "0", "0"]
```

### Installed Packages

1. **openssh-server** - SSH server for remote access
2. **nfs-common** - NFS client utilities
3. **hstr** - Better bash history management tool
4. **qemu-guest-agent** - Proxmox VM integration

### User Configuration

- **Username**: xalg
- **Authentication**: SSH key (ED25519)
- **Privileges**: Full passwordless sudo
- **Shell**: /bin/bash
- **Groups**: sudo

### NFS Configuration

- **Server**: 192.168.0.7
- **Export**: /data
- **Mount Point**: /data
- **Options**: defaults,_netdev (waits for network)
- **Auto-mount**: Yes (configured in cloud-init)

## 🚀 Deployment Instructions

### Method 1: Quick Deployment (Recommended)

Use the automated deployment script:

```bash
cd /Users/xalg/dev/terraform/epyc2
./scripts/deployment/deploy-work-vm.sh
```

This script will:
1. Check prerequisites
2. Create Debian template if needed
3. Initialize Terraform
4. Deploy the VM
5. Wait for initialization
6. Verify configuration

### Method 2: Manual Deployment

#### Step 1: Create Debian 13 Template

```bash
# Create the template (if not already exists)
./scripts/deployment/create-debian-template.sh
```

#### Step 2: Deploy with Terraform

```bash
# Initialize Terraform (if not already done)
terraform init

# Plan the deployment
terraform plan -target=proxmox_virtual_environment_vm.work

# Apply the configuration
terraform apply -target=proxmox_virtual_environment_vm.work
```

#### Step 3: Wait for Cloud-Init

Wait 2-3 minutes for cloud-init to complete initialization.

#### Step 4: Connect via SSH

```bash
ssh xalg@192.168.0.50
```

## ✅ Verification Steps

After deployment, verify the configuration:

```bash
# Connect to the VM
ssh xalg@192.168.0.50

# Check hostname
hostname -f
# Expected: work.xalg.im

# Check NFS mount
df -h | grep /data
# Expected: 192.168.0.7:/data mounted on /data

# Verify packages
dpkg -l | grep -E "nfs-common|hstr|openssh-server"
# Expected: All packages listed

# Check QEMU guest agent
systemctl status qemu-guest-agent
# Expected: active (running)

# Test NFS write access
touch /data/test-file && rm /data/test-file
# Expected: Success
```

## 📊 Terraform Outputs

After deployment, view the VM details:

```bash
terraform output vm_info
```

Expected output includes:
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

## 🔍 Monitoring in Proxmox

In the Proxmox web interface, you can:

1. **View VM Console**: Datacenter → Node → VM 110 → Console
2. **Check Resources**: See CPU, memory, and disk usage
3. **View Cloud-Init Log**: Console → Check /var/log/cloud-init.log
4. **Monitor Network**: See network traffic and IP assignment

## 🛠️ Common Operations

### Start VM
```bash
# Via Terraform (ensures running state)
terraform apply -target=proxmox_virtual_environment_vm.work

# Via Proxmox CLI
ssh root@192.168.0.7 "qm start 110"
```

### Stop VM
```bash
# Graceful shutdown via SSH
ssh xalg@192.168.0.50 "sudo shutdown -h now"

# Via Proxmox CLI
ssh root@192.168.0.7 "qm stop 110"
```

### Destroy VM
```bash
# Via Terraform (recommended)
terraform destroy -target=proxmox_virtual_environment_vm.work

# Via Proxmox CLI
ssh root@192.168.0.7 "qm destroy 110"
```

### Rebuild VM
```bash
# Destroy and recreate
terraform destroy -target=proxmox_virtual_environment_vm.work
terraform apply -target=proxmox_virtual_environment_vm.work
```

## 🔐 Security Considerations

1. **SSH Access**
   - Only SSH key authentication (no password)
   - Key: `~/.ssh/id_ed25519`
   - User has full sudo access

2. **Network Security**
   - VM accessible on 192.168.0.0/24 network
   - No firewall rules configured by default
   - Consider adding iptables rules if needed

3. **NFS Security**
   - NFS mount uses default options
   - Consider adding `nosuid,nodev` for additional security
   - Ensure NFS server has proper export restrictions

4. **Updates**
   - Cloud-init runs `package_update: true`
   - Consider setting up automatic security updates:
     ```bash
     sudo apt install -y unattended-upgrades
     sudo dpkg-reconfigure -plow unattended-upgrades
     ```

## 🐛 Troubleshooting

### VM Won't Start

Check Proxmox logs:
```bash
ssh root@192.168.0.7 "qm status 110"
```

### Can't SSH to VM

1. Check VM is running:
   ```bash
   ssh root@192.168.0.7 "qm status 110"
   ```

2. Check cloud-init status from Proxmox console:
   ```bash
   # Access via Proxmox web UI console
   sudo cloud-init status --long
   ```

3. Verify network:
   ```bash
   ping 192.168.0.50
   ```

### NFS Mount Fails

1. Check NFS server:
   ```bash
   showmount -e 192.168.0.7
   ```

2. Manual mount test:
   ```bash
   ssh xalg@192.168.0.50
   sudo mount -t nfs 192.168.0.7:/data /data
   ```

3. Check fstab:
   ```bash
   ssh xalg@192.168.0.50 "cat /etc/fstab | grep data"
   ```

### Cloud-Init Issues

View logs:
```bash
ssh xalg@192.168.0.50
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log
```

## 📚 Additional Resources

- **Setup Guide**: `docs/deployment/WORK_VM_SETUP.md`
- **Template Creation**: `scripts/deployment/create-debian-template.sh`
- **Deployment Script**: `scripts/deployment/deploy-work-vm.sh`
- **Terraform Config**: `infrastructure-work.tf`
- **Debian Cloud Images**: https://cloud.debian.org/images/cloud/
- **Cloud-Init Docs**: https://cloudinit.readthedocs.io/

## 🎯 Next Steps

1. **Deploy the VM**:
   ```bash
   ./scripts/deployment/deploy-work-vm.sh
   ```

2. **Connect and Verify**:
   ```bash
   ssh xalg@192.168.0.50
   ```

3. **Install Additional Software**:
   ```bash
   sudo apt update
   sudo apt install -y <your-packages>
   ```

4. **Configure as Needed**:
   - Set up additional services
   - Configure firewall rules
   - Install development tools
   - Set up monitoring

## 📝 Notes

- The Debian 13 template (VM ID 9001) must be created before deploying the work VM
- Cloud-init takes 2-3 minutes to complete initial setup
- The VM is configured to start automatically on Proxmox boot
- NFS mount is configured with `_netdev` to wait for network availability
- SSH key is embedded in cloud-init configuration
- The template creation script handles downloading the Debian cloud image automatically

## ✨ Features

✅ Automated deployment with single command  
✅ Cloud-init based configuration  
✅ Automatic NFS mount setup  
✅ SSH key authentication  
✅ Passwordless sudo access  
✅ Pre-installed essential tools (hstr, nfs-common)  
✅ QEMU guest agent integration  
✅ Comprehensive documentation  
✅ Helper scripts for template creation and deployment  
✅ Full Terraform state management  

---

**Created**: November 11, 2025  
**VM Name**: work.xalg.im  
**VM ID**: 110  
**IP Address**: 192.168.0.50  
**Template ID**: 9001 (Debian 13)

