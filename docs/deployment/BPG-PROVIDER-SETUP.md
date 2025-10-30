# BPG Proxmox Provider Setup Guide

This guide explains the new BPG Proxmox provider configuration and how to use it.

## 🔄 What Changed

We've switched from the unstable `telmate/proxmox` provider to the more reliable `bpg/proxmox` provider:

### Old Provider (telmate/proxmox)
- ❌ Frequent crashes and plugin errors
- ❌ Poor error handling
- ❌ Limited cloud-init support
- ❌ Inconsistent resource management

### New Provider (bpg/proxmox)
- ✅ Stable and actively maintained
- ✅ Better error messages and debugging
- ✅ Excellent cloud-init integration
- ✅ Modern Terraform practices
- ✅ No plugin crashes

## 📋 Configuration Changes

### Resource Names
- **Old**: `proxmox_vm_qemu`
- **New**: `proxmox_virtual_environment_vm`

### Provider Configuration
```hcl
# Old (telmate)
provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_user         = var.proxmox_user
  pm_password     = var.proxmox_password
  pm_tls_insecure = var.proxmox_tls_insecure
}

# New (bpg)
provider "proxmox" {
  endpoint = var.proxmox_api_url
  username = var.proxmox_user
  password = var.proxmox_password
  insecure = var.proxmox_tls_insecure
}
```

### VM Configuration
```hcl
# New BPG syntax
resource "proxmox_virtual_environment_vm" "bumblebee" {
  name      = "bumblebee"
  node_name = var.proxmox_node
  
  clone {
    vm_id = var.vm_template_id  # Template ID (e.g., 9000)
    full  = true
  }
  
  cpu {
    cores = 8
    type  = "host"
  }
  
  memory {
    dedicated = 16384  # 16GB
  }
  
  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }
  
  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.33/24"
        gateway = "192.168.1.1"
      }
    }
    
    user_account {
      username = var.ssh_user
      keys     = [trimspace(file("${var.ssh_private_key_path}.pub"))]
    }
  }
  
  agent {
    enabled = true
  }
  
  started = true
}
```

## 🚀 Deployment Steps

### 1. Prerequisites
Ensure you have:
- Ubuntu template created in Proxmox (ID: 9000)
- Correct Proxmox IP in terraform.tfvars
- Valid SSH keys

### 2. Initialize New Provider
```bash
# Clean up old provider
rm -rf .terraform/providers/registry.terraform.io/telmate/
rm -f .terraform.lock.hcl

# Initialize with BPG provider
terraform init
```

### 3. Validate Configuration
```bash
terraform validate
```

### 4. Create VMs
```bash
# Create all VMs
terraform apply -target=proxmox_virtual_environment_vm.prime -target=proxmox_virtual_environment_vm.bumblebee -target=proxmox_virtual_environment_vm.wheeljack

# Or use the script
./scripts/create-vms-only.sh
```

### 5. Deploy Kubernetes
```bash
# Deploy full cluster
terraform apply
```

## 🔧 Configuration Variables

### Required in terraform.tfvars
```hcl
# Proxmox Configuration
proxmox_api_url           = "https://YOUR_PROXMOX_IP:8006/api2/json"
proxmox_user              = "root@pam"  # fallback user
proxmox_password          = "your_password"  # fallback password
proxmox_api_token_id      = "user@pam!tokenname"  # API token (recommended)
proxmox_api_token_secret  = "your-token-secret"   # API token secret
proxmox_node              = "pve"       # your node name
vm_template               = "ubuntu-22.04-template"  # template name
vm_template_id            = 9000        # template VM ID
vm_storage                = "local-lvm"  # storage pool
vm_network_bridge         = "vmbr0"     # network bridge
```

## 🎯 VM Specifications

Each VM will be created with:
- **CPU**: 8 cores (host type for best performance)
- **Memory**: 16GB RAM
- **Disk**: 256GB (SCSI interface with iothread)
- **Network**: Virtio with static IP
- **Agent**: QEMU guest agent enabled
- **Cloud-init**: Automatic SSH key setup

### VM Specifications
- **Prime**: 192.168.1.32 (Worker) - 8 cores, 16GB RAM, 256GB disk
- **Bumblebee**: 192.168.1.33 (Control Plane) - 8 cores, 16GB RAM, 256GB disk
- **Wheeljack**: 192.168.1.34 (Worker) - 8 cores, 16GB RAM, 256GB disk

## 🛠️ Troubleshooting

### Common Issues

1. **Template ID Error**
   ```
   Error: expected file_id to be a valid file identifier
   ```
   **Solution**: Ensure `vm_template_id = 9000` matches your actual template ID

2. **Authentication Failed**
   ```
   Error: authentication failed
   ```
   **Solution**: Check Proxmox credentials in terraform.tfvars

3. **Template Not Found**
   ```
   Error: template with ID 9000 not found
   ```
   **Solution**: Create Ubuntu template or update template ID

### Verification Commands

```bash
# Check template exists
ssh root@YOUR_PROXMOX_IP 'qm list | grep template'

# Test Terraform connection
terraform plan -target=proxmox_virtual_environment_vm.bumblebee

# Verify VMs after creation
ping 192.168.1.32  # Prime
ping 192.168.1.33  # Bumblebee
ping 192.168.1.34  # Wheeljack
```

## 📚 Benefits of BPG Provider

1. **Stability**: No more plugin crashes
2. **Better Errors**: Clear error messages for debugging
3. **Modern Syntax**: Clean, readable configuration
4. **Cloud-init**: Excellent support for automated setup
5. **Active Development**: Regular updates and bug fixes
6. **Documentation**: Comprehensive provider documentation

## 🔗 Resources

- [BPG Proxmox Provider Documentation](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Provider GitHub Repository](https://github.com/bpg/terraform-provider-proxmox)
- [Proxmox VE API Documentation](https://pve.proxmox.com/pve-docs/api-viewer/)

---

The BPG provider should provide a much more stable and reliable experience for VM creation! 🚀