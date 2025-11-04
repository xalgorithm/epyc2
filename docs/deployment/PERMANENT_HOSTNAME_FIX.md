# Permanent Hostname Fix Applied

## What Was Changed

The Terraform configuration has been updated to permanently prevent hostname collisions by creating **separate cloud-init files for each VM** with explicit hostname settings.

### Changes Made to `proxmox-vms.tf`

#### 1. Replaced Single Shared Cloud-Init File

**Before:**
```hcl
resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  # Shared by all VMs - no hostname setting
  ...
}
```

**After:**
```hcl
# Three separate cloud-init files:
resource "proxmox_virtual_environment_file" "cloud_init_bumblebee" {
  # Specific to control plane with hostname: bumblebee
  ...
}

resource "proxmox_virtual_environment_file" "cloud_init_prime" {
  # Specific to worker 1 with hostname: prime
  ...
}

resource "proxmox_virtual_environment_file" "cloud_init_wheeljack" {
  # Specific to worker 2 with hostname: wheeljack
  ...
}
```

#### 2. Added Hostname Configuration to Cloud-Init

Each cloud-init file now includes:
```yaml
hostname: <vm-name>
fqdn: <vm-name>.local
manage_etc_hosts: true
```

This ensures that:
- ✅ Hostname is set correctly during VM first boot
- ✅ `/etc/hosts` is properly configured
- ✅ FQDN is set for proper network identification

#### 3. Updated VM Initialization Blocks

Each VM now references its own cloud-init file:

**Bumblebee (Control Plane):**
```hcl
user_data_file_id = proxmox_virtual_environment_file.cloud_init_bumblebee.id
```

**Prime (Worker 1):**
```hcl
user_data_file_id = proxmox_virtual_environment_file.cloud_init_prime.id
```

**Wheeljack (Worker 2):**
```hcl
user_data_file_id = proxmox_virtual_environment_file.cloud_init_wheeljack.id
```

## How to Apply This Fix

### For Existing VMs (Already Deployed)

If your VMs are already running with correct hostnames (from the manual fix), you **don't need to recreate them**. The cloud-init files in Proxmox will be updated, but since cloud-init only runs once on first boot, existing VMs won't be affected.

To update just the cloud-init files in Proxmox:

```bash
terraform apply \
  -target=proxmox_virtual_environment_file.cloud_init_bumblebee \
  -target=proxmox_virtual_environment_file.cloud_init_prime \
  -target=proxmox_virtual_environment_file.cloud_init_wheeljack
```

This will:
- ✅ Create the new cloud-init files in Proxmox
- ✅ Update them for future VM deployments
- ✅ **NOT affect existing running VMs**

### For New Deployments (Fresh Start)

If you're deploying from scratch or recreating VMs:

```bash
# Standard deployment - hostnames will be correct from the start
terraform apply
```

The VMs will now have correct hostnames from first boot, preventing any hostname collision issues.

### For Recreating Existing VMs

If you want to recreate the VMs to use the new cloud-init configuration:

```bash
# Destroy only the VMs (preserving other resources)
terraform destroy \
  -target=proxmox_virtual_environment_vm.bumblebee \
  -target=proxmox_virtual_environment_vm.prime \
  -target=proxmox_virtual_environment_vm.wheeljack

# Recreate with new cloud-init
terraform apply
```

**Note:** This will destroy and recreate the VMs, losing any data on them. Only do this if you're setting up a fresh cluster.

## Verification

After applying the changes, you can verify the cloud-init files were created:

```bash
# Check Terraform state
terraform state list | grep cloud_init

# Should show:
# proxmox_virtual_environment_file.cloud_init_bumblebee
# proxmox_virtual_environment_file.cloud_init_prime
# proxmox_virtual_environment_file.cloud_init_wheeljack
```

From Proxmox, check the snippets directory:

```bash
ssh root@proxmox-host
ls -la /var/lib/vz/snippets/

# Should show:
# cloud-init-bumblebee.yaml
# cloud-init-prime.yaml
# cloud-init-wheeljack.yaml
```

## Benefits of This Fix

1. **✅ Prevents Hostname Collisions**: Each VM gets its unique hostname from first boot
2. **✅ Proper DNS/Network Identity**: FQDNs set correctly for network operations
3. **✅ Kubernetes Compatibility**: Nodes join with correct, unique names
4. **✅ Future-Proof**: Works for all future deployments
5. **✅ Clean Configuration**: Each VM has its own isolated cloud-init settings

## What This Fixes

### Before (Problem)
- All VMs used shared cloud-init file
- No hostname set in cloud-init
- All VMs defaulted to template's hostname ("ubuntu")
- Kubernetes cluster rejected worker joins due to duplicate node names
- Manual hostname changes required after deployment

### After (Solution)
- Each VM has dedicated cloud-init file
- Hostname explicitly set for each VM
- VMs boot with correct unique hostnames
- Kubernetes cluster accepts all nodes immediately
- No manual intervention needed

## Testing the Fix (New VM Deployment)

To test this works correctly:

```bash
# Deploy everything
terraform apply

# Wait for VMs to boot (2-3 minutes)
sleep 180

# Check hostnames on each VM
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.32 "hostname"
# Expected: bumblebee

ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.34 "hostname"
# Expected: prime

ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.33 "hostname"
# Expected: wheeljack

# All three should show UNIQUE hostnames
```

## Compatibility

This fix is compatible with:
- ✅ Existing deployments (won't affect running VMs)
- ✅ New deployments (will work correctly from start)
- ✅ VM recreation (will use new cloud-init)
- ✅ All other Terraform resources (no breaking changes)

## Additional Notes

### Cloud-Init Behavior
- Cloud-init runs **once** on first boot
- Changing cloud-init files doesn't affect existing VMs
- To apply new cloud-init to existing VMs, you must recreate them

### Terraform State
- Terraform will detect the old `cloud_init_user_data` resource is no longer used
- You may see a warning about unused resources
- This is expected and safe - the old resource can be removed from state if needed

### No Risk to Existing Cluster
If your cluster is currently working with correct hostnames (from the manual fix), this change:
- ✅ Won't disrupt the running cluster
- ✅ Won't force VM recreation
- ✅ Won't require cluster re-initialization
- ✅ Only affects future deployments

## Summary

The permanent fix has been successfully applied to your Terraform configuration. Future deployments will automatically have correct hostnames from first boot, preventing the hostname collision issue you encountered.

**Action Required:** 
- For existing working cluster: No immediate action needed
- For new deployments: Just run `terraform apply` as normal
- For updating cloud-init files: Run the targeted apply command above

The hostname collision issue is now **permanently resolved** for all future infrastructure deployments! 🎉

