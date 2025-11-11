# Quick Deployment Guide for work.xalg.im

## 🚀 One-Command Deployment (Recommended)

The easiest way to deploy the work VM:

```bash
cd /Users/xalg/dev/terraform/epyc2
./scripts/deployment/deploy-work-vm.sh
```

This script will automatically:
- ✅ Check prerequisites
- ✅ Create Debian 13 template if needed
- ✅ Initialize Terraform
- ✅ Deploy the VM
- ✅ Wait for initialization
- ✅ Verify configuration

## 📋 What Gets Created

| Component | Value |
|-----------|-------|
| VM Name | work |
| FQDN | work.xalg.im |
| VM ID | 110 |
| IP Address | 192.168.0.50 |
| CPU | 2 cores |
| Memory | 4GB |
| Disk | 64GB |
| OS | Debian 13 (Trixie) |
| User | xalg (sudo access) |
| SSH Key | ~/.ssh/id_ed25519 |
| NFS Mount | 192.168.0.7:/data → /data |

## 🛠️ Manual Deployment Steps

If you prefer manual control:

### 1. Fix NFS Backend (if needed)

If you see NFS mount errors, you have two options:

**Option A: Mount NFS backend**
```bash
# Check if mounted
ls /Volumes/nfs-k8s/

# If not mounted, run the setup script
sudo ./scripts/deployment/setup-nfs-backend.sh
```

**Option B: Use local state temporarily**
```bash
# Edit backend.tf and comment out the NFS path
# Uncomment this line instead:
# path = "./terraform.tfstate"
```

### 2. Create Debian 13 Template

```bash
./scripts/deployment/create-debian-template.sh
```

This creates VM template 9001 with Debian 13 cloud image.

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Deploy the VM

```bash
# Preview changes
terraform plan -target=proxmox_virtual_environment_file.cloud_init_work -target=proxmox_virtual_environment_vm.work

# Apply configuration
terraform apply -target=proxmox_virtual_environment_file.cloud_init_work -target=proxmox_virtual_environment_vm.work
```

### 5. Wait for Cloud-Init

Wait 2-3 minutes for cloud-init to complete, then connect:

```bash
ssh xalg@192.168.0.50
```

## ✅ Verify Deployment

After connecting, run these checks:

```bash
# Check hostname
hostname -f
# Expected: work.xalg.im

# Check NFS mount
df -h | grep /data
# Expected: 192.168.0.7:/data mounted

# Test NFS write
touch /data/test && rm /data/test
# Expected: Success

# Check installed packages
dpkg -l | grep -E "nfs-common|hstr|openssh-server"
# Expected: All packages listed
```

## 📦 Installed Packages

The VM comes pre-installed with:
- **openssh-server** - SSH access
- **nfs-common** - NFS client
- **hstr** - Better bash history (Ctrl+R)
- **qemu-guest-agent** - Proxmox integration

## 🔐 SSH Access

Your SSH key is already configured:

```bash
# Connect via IP
ssh xalg@192.168.0.50

# Or via hostname (if DNS configured)
ssh xalg@work.xalg.im
```

The user `xalg` has full sudo access without password.

## 📁 NFS Storage

The NFS share is automatically mounted at boot:

```bash
# NFS share details
Server: 192.168.0.7
Export: /data
Mount: /data
Options: defaults,_netdev

# Check mount
df -h /data

# Access files
ls -la /data/
```

## 🛑 Stop/Remove VM

### Stop VM
```bash
terraform destroy -target=proxmox_virtual_environment_vm.work
```

### Or via Proxmox
```bash
ssh root@192.168.0.7 "qm stop 110"
```

## 🔄 Rebuild VM

To recreate the VM from scratch:

```bash
terraform destroy -target=proxmox_virtual_environment_vm.work
terraform apply -target=proxmox_virtual_environment_vm.work
```

## 📚 Documentation

For more details, see:
- **Comprehensive Guide**: [WORK_VM_CREATION_SUMMARY.md](WORK_VM_CREATION_SUMMARY.md)
- **Detailed Setup**: [docs/deployment/WORK_VM_SETUP.md](docs/deployment/WORK_VM_SETUP.md)

## 🆘 Troubleshooting

### "Permission denied" on /Volumes/nfs-k8s

NFS backend not mounted. Use local state or mount NFS:
```bash
sudo ./scripts/deployment/setup-nfs-backend.sh
```

### "Debian template not found"

Create the template first:
```bash
./scripts/deployment/create-debian-template.sh
```

### Can't SSH to VM

Wait 2-3 minutes for cloud-init to complete. Check status:
```bash
# Check if VM is running
ssh root@192.168.0.7 "qm status 110"

# Test connectivity
ping 192.168.0.50
```

### NFS mount failed

Check NFS server:
```bash
showmount -e 192.168.0.7
```

Manual mount:
```bash
ssh xalg@192.168.0.50
sudo mount -t nfs 192.168.0.7:/data /data
```

## 🎯 Quick Reference

```bash
# Deploy everything
./scripts/deployment/deploy-work-vm.sh

# Connect to VM
ssh xalg@192.168.0.50

# Check status in Proxmox
ssh root@192.168.0.7 "qm status 110"

# View Terraform outputs
terraform output vm_info

# View cloud-init logs
ssh xalg@192.168.0.50 "sudo cat /var/log/cloud-init-output.log"
```

---

**Ready to deploy?** Run: `./scripts/deployment/deploy-work-vm.sh`

