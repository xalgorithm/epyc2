# Cloud-Init SSH Key Fix

## Issue

SSH authentication was failing when Terraform tried to connect to the VMs:

```
Error: SSH authentication failed (ubuntu@192.168.0.34:22): ssh: handshake failed: 
ssh: unable to authenticate, attempted methods [none publickey], no supported methods remain
```

## Root Cause

The cloud-init configuration had a conflict between two methods of adding SSH keys:

1. **user_account block** in the VM's `initialization` section
2. **user_data_file_id** pointing to a custom cloud-init file

When both are present, the `user_data_file_id` takes precedence and **overrides** the `user_account` settings. Since our custom cloud-init file didn't include SSH key configuration, the keys were never added to the VMs.

## Solution

Consolidated all cloud-init configuration into a single `user_data` file that includes:
- Package installations (qemu-guest-agent, nfs-common)
- User creation with SSH keys
- Service startup commands

### Updated Cloud-Init Configuration

The cloud-init user_data now includes:

```yaml
#cloud-config
package_update: true
package_upgrade: false
packages:
  - qemu-guest-agent
  - nfs-common
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDKEfeH... (your maint-rsa.pub key)
runcmd:
  - systemctl start qemu-guest-agent
  - systemctl enable qemu-guest-agent
```

### Changes Made

1. **proxmox-vms.tf** - Updated cloud-init user_data resource:
   - Added `users` section with SSH key configuration
   - Includes passwordless sudo for the `ubuntu` user
   - Sets proper shell and groups

2. **proxmox-vms.tf** - Removed redundant `user_account` blocks:
   - Removed from bumblebee VM
   - Removed from prime VM
   - Removed from wheeljack VM

## What This Fixes

✅ **SSH keys are now properly added** to all VMs during initial boot  
✅ **ubuntu user** is created with correct permissions  
✅ **Passwordless sudo** is configured (required for Kubernetes setup)  
✅ **No more authentication failures** when Terraform provisions VMs  

## Deployment

### If VMs Already Exist

If you already created VMs that don't have the SSH keys, you have two options:

#### Option 1: Destroy and Recreate (Recommended)

```bash
# Destroy existing VMs
terraform destroy \
  -target=proxmox_virtual_environment_vm.bumblebee \
  -target=proxmox_virtual_environment_vm.prime \
  -target=proxmox_virtual_environment_vm.wheeljack

# Or manually in Proxmox:
# qm destroy 100
# qm destroy 101
# qm destroy 103

# Then recreate with proper cloud-init
terraform apply -var="bootstrap_cluster=true"
```

#### Option 2: Manually Add Keys to Existing VMs

```bash
# For each VM, add the key manually:
# From Proxmox console or if you have console access:

# Control plane (bumblebee - 192.168.0.32)
cat ~/.ssh/maint-rsa.pub | ssh root@192.168.0.32 \
  "mkdir -p /home/ubuntu/.ssh && cat >> /home/ubuntu/.ssh/authorized_keys && chown -R ubuntu:ubuntu /home/ubuntu/.ssh && chmod 700 /home/ubuntu/.ssh && chmod 600 /home/ubuntu/.ssh/authorized_keys"

# Worker 1 (prime - 192.168.0.34)
cat ~/.ssh/maint-rsa.pub | ssh root@192.168.0.34 \
  "mkdir -p /home/ubuntu/.ssh && cat >> /home/ubuntu/.ssh/authorized_keys && chown -R ubuntu:ubuntu /home/ubuntu/.ssh && chmod 700 /home/ubuntu/.ssh && chmod 600 /home/ubuntu/.ssh/authorized_keys"

# Worker 2 (wheeljack - 192.168.0.33)
cat ~/.ssh/maint-rsa.pub | ssh root@192.168.0.33 \
  "mkdir -p /home/ubuntu/.ssh && cat >> /home/ubuntu/.ssh/authorized_keys && chown -R ubuntu:ubuntu /home/ubuntu/.ssh && chmod 700 /home/ubuntu/.ssh && chmod 600 /home/ubuntu/.ssh/authorized_keys"
```

### Fresh Deployment

For a fresh deployment, the fix is already applied. Just run:

```bash
# Stage 1: Create VMs and cluster
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

## Verification

After VMs are created, verify SSH access works:

```bash
# Test SSH to each VM
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.32  # bumblebee
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.34  # prime
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.33  # wheeljack

# Verify cloud-init ran successfully
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.32 "cloud-init status"
# Should show: status: done

# Verify guest agent is running
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.32 "systemctl status qemu-guest-agent"
# Should show: active (running)
```

## Key Points

1. **Single Source of Truth**: All cloud-init configuration is now in one place (the user_data file)

2. **No Conflicts**: Removed the `user_account` blocks that were being overridden

3. **Complete Configuration**: The cloud-init user_data now handles:
   - User creation
   - SSH key authorization
   - Sudo permissions
   - Package installation
   - Service startup

4. **Template Requirements**: Your VM template must have cloud-init installed for this to work

## Troubleshooting

### If SSH still fails after recreating VMs:

1. **Check cloud-init status**:
   ```bash
   # Via Proxmox console or web terminal
   cloud-init status --long
   cat /var/log/cloud-init-output.log
   ```

2. **Check if user was created**:
   ```bash
   id ubuntu
   cat /home/ubuntu/.ssh/authorized_keys
   ```

3. **Verify the template**:
   - Ensure VM template (ID 9000) has cloud-init installed
   - Verify template has cloud-init datasource configured

4. **Check the cloud-init file was uploaded**:
   ```bash
   ssh xalg@192.168.0.7 "ls -la /var/lib/vz/snippets/"
   # Should show: cloud-init-userdata.yaml
   ```

### If you see "cloud-init: disabled" or "not run":

The template may not have cloud-init properly configured. You'll need to:
1. Fix the template
2. Or manually add SSH keys to each VM
3. Or use a different provisioning method

## Related Documentation

- **PROXMOX_SNIPPETS_SETUP.md** - Setting up the snippets directory
- **SSH_CONFIG_SUMMARY.md** - Complete SSH configuration guide
- **VM_CONFIGURATION.md** - VM details and IDs

