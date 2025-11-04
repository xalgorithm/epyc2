# SSH Configuration Summary

## Overview

The Terraform configuration now supports **separate SSH credentials** for different infrastructure components.

## SSH Configuration

### For Proxmox Host (File Uploads)
Used to connect to: 192.168.0.7 (Proxmox host for uploading cloud-init snippets)

**Configuration:**
- Uses SSH agent authentication
- Username: `xalg` (from `nfs_ssh_user` variable)
- Keys loaded in ssh-agent (verified with `ssh-add -L`)

**Provider Configuration:**
```hcl
provider "proxmox" {
  # ... API config ...
  ssh {
    agent    = true
    username = "xalg"
  }
}
```

**Required for:**
- Uploading cloud-init snippets to Proxmox
- Creating files in Proxmox datastores

### For Proxmox VMs (Kubernetes Nodes)
Used to connect to: bumblebee, prime, wheeljack

**Configuration in `terraform.tfvars`:**
```hcl
ssh_user             = "ubuntu"
ssh_private_key_path = "~/.ssh/maint-rsa"
```

**Files:**
- Private key: `~/.ssh/maint-rsa`
- Public key: `~/.ssh/maint-rsa.pub` (auto-detected)

**Usage:**
- VM provisioning via cloud-init
- Kubernetes cluster setup
- Copying kubeconfig
- Inter-node communication

### For NFS Server
Used to connect to: 192.168.0.7 (NFS/backup server)

**Configuration in `terraform.tfvars`:**
```hcl
nfs_ssh_user               = "xalg"
nfs_ssh_private_key_path   = "~/.ssh/id_ed25519"
```

**Files:**
- Private key: `~/.ssh/id_ed25519`
- Public key: `~/.ssh/id_ed25519.pub` (auto-detected)

**Usage:**
- Creating NFS directories
- Setting permissions
- Checking existing data

## How It Works

### Variable Fallback Logic

The NFS SSH variables are optional. If not specified, they fall back to the main SSH variables:

```bash
# In nfs-storage.tf
NFS_SSH_USER="${var.nfs_ssh_user != "" ? var.nfs_ssh_user : var.ssh_user}"
NFS_SSH_KEY="${var.nfs_ssh_private_key_path != "" ? var.nfs_ssh_private_key_path : var.ssh_private_key_path}"
```

This means:
- If `nfs_ssh_user` is set → use it
- If `nfs_ssh_user` is empty → use `ssh_user`

### Variables Defined

**In `main.tf`:**
```hcl
variable "nfs_ssh_user" {
  description = "SSH user for NFS server access"
  type        = string
  default     = ""  # If empty, uses ssh_user
}

variable "nfs_ssh_private_key_path" {
  description = "SSH private key path for NFS server access"
  type        = string
  default     = ""  # If empty, uses ssh_private_key_path
}
```

## Verification

### Check Your SSH Keys

```bash
# Proxmox VM keys
ls -la ~/.ssh/maint-rsa*

# NFS server keys
ls -la ~/.ssh/id_ed25519*
```

### Test SSH Connectivity

```bash
# Test Proxmox VMs (after they're created)
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.32
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.33
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.34

# Test NFS server
ssh -i ~/.ssh/id_ed25519 xalg@192.168.0.7
```

### Test NFS Server Access

```bash
# Verify you can access and create directories
ssh -i ~/.ssh/id_ed25519 xalg@192.168.0.7 "sudo ls -la /data/kubernetes"
```

## Deployment

With the correct SSH configuration, you can now deploy:

### Stage 1: Create VMs and Cluster
```bash
terraform apply \
  -target=proxmox_virtual_environment_file.cloud_init_user_data \
  -target=proxmox_virtual_environment_vm.bumblebee \
  -target=proxmox_virtual_environment_vm.prime \
  -target=proxmox_virtual_environment_vm.wheeljack \
  -target=null_resource.prepare_kubeconfig \
  -target=null_resource.wait_for_vms \
  -target=null_resource.control_plane_setup \
  -target=null_resource.worker_setup \
  -target=null_resource.copy_kubeconfig \
  -target=null_resource.kubeconfig_ready \
  -target=null_resource.cluster_api_ready \
  -var="bootstrap_cluster=true"
```

### Stage 2: Deploy Kubernetes Resources
```bash
terraform apply -var="bootstrap_cluster=true"
```

## Troubleshooting

### Error: Authentication failed to Proxmox VMs

**Symptom:**
```
Error: ssh: handshake failed... to "192.168.0.32:22"
```

**Solution:**
- Verify `ssh_user = "ubuntu"` in terraform.tfvars
- Verify `ssh_private_key_path = "~/.ssh/maint-rsa"` in terraform.tfvars
- Check public key exists: `ls -la ~/.ssh/maint-rsa.pub`
- Ensure public key is in VM template's authorized_keys or configured in cloud-init

### Error: Authentication failed to NFS server

**Symptom:**
```
Error: ssh: handshake failed... to "192.168.0.7:22"
```

**Solution:**
- Verify `nfs_ssh_user = "xalg"` in terraform.tfvars
- Verify `nfs_ssh_private_key_path = "~/.ssh/id_ed25519"` in terraform.tfvars
- Check public key exists: `ls -la ~/.ssh/id_ed25519.pub`
- Test connection: `ssh -i ~/.ssh/id_ed25519 xalg@192.168.0.7`
- Add key if needed: `ssh-copy-id -i ~/.ssh/id_ed25519.pub xalg@192.168.0.7`

### Error: Public key not found

**Symptom:**
```
Error: file("~/.ssh/maint-rsa.pub"): no such file or directory
```

**Solution:**
- Terraform automatically appends `.pub` to the private key path
- Ensure your public key uses the standard naming: `<private-key>.pub`
- If your key is named differently (e.g., `maint-rsa-pub`), rename it:
  ```bash
  mv ~/.ssh/maint-rsa-pub ~/.ssh/maint-rsa.pub
  ```

### Error: Permission denied

**Symptom:**
```
Error: Permission denied (publickey)
```

**Solution:**
- Check key permissions:
  ```bash
  chmod 600 ~/.ssh/maint-rsa
  chmod 644 ~/.ssh/maint-rsa.pub
  chmod 600 ~/.ssh/id_ed25519
  chmod 644 ~/.ssh/id_ed25519.pub
  ```
- Ensure public key is in authorized_keys on remote host
- Test manually: `ssh -i <key> <user>@<host>`

## Files Modified

| File | Changes |
|------|---------|
| `main.tf` | Added `nfs_ssh_user` and `nfs_ssh_private_key_path` variables |
| `nfs-storage.tf` | Updated SSH connection to use NFS-specific variables |
| `terraform.tfvars` | Configured separate SSH credentials for VMs and NFS |
| `terraform.tfvars.example` | Updated example with NFS SSH variables |

## Summary

✅ **Proxmox VMs**: Use `ubuntu` user with `~/.ssh/maint-rsa`  
✅ **NFS Server**: Use `xalg` user with `~/.ssh/id_ed25519`  
✅ **Automatic fallback**: NFS uses VM credentials if NFS credentials not specified  
✅ **Standard naming**: Public keys use `.pub` extension  
✅ **Ready for deployment**: All SSH configuration is correct  

