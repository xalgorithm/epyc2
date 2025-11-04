# Proxmox Permission Issues - Troubleshooting Guide

## Common Error: VM.Clone Permission Denied

### Error Message
```
Error: error waiting for VM clone: All attempts fail:
#1: error cloning VM: received an HTTP 403 response - Reason: Permission check failed (/vms/9000, VM.Clone)
```

### Root Cause
Your Proxmox API token user (`terraform@pam`) doesn't have sufficient permissions to clone VMs from the template.

## Quick Fix

### Option 1: Via SSH (Fastest)

SSH to your Proxmox server and run:

```bash
# Grant full VM admin permissions
pveum acl modify / -user terraform@pam -role PVEVMAdmin -propagate 1

# Verify permissions were set
pveum user permissions terraform@pam
```

### Option 2: Via Proxmox Web UI

1. **Login to Proxmox**
   - Navigate to: `https://192.168.0.7:8006`
   - Login as root or admin user

2. **Navigate to Permissions**
   - Click: `Datacenter` → `Permissions`

3. **Add User Permission**
   - Click: `Add` → `User Permission`
   - Fill in:
     - **Path**: `/` (root level)
     - **User**: `terraform@pam`
     - **Role**: `PVEVMAdmin`
     - **Propagate**: ✓ Checked
   - Click: `Add`

4. **Verify**
   - Go to: `Datacenter` → `Permissions` → `User Permissions`
   - Confirm entry exists for `terraform@pam` with `PVEVMAdmin` role

## Required Permissions

For Terraform to manage VMs, the API token user needs these permissions:

### Minimum Required
- `VM.Allocate` - Create new VMs
- `VM.Clone` - Clone from templates
- `VM.Config.*` - Configure VM settings
- `VM.Monitor` - View VM status
- `Datastore.Allocate` - Allocate storage
- `Datastore.AllocateSpace` - Use disk space

### Recommended Role: PVEVMAdmin
The `PVEVMAdmin` role includes all necessary permissions:
- `VM.*` - All VM operations
- `Datastore.*` - Storage operations
- `Pool.Allocate` - Resource pool management

### Additional Permissions (if needed)
- `Sys.Modify` - System modifications
- `SDN.Use` - Software-defined networking
- `Sys.Audit` - View system information

## Verify Setup

### Check API Token
```bash
# List all API tokens
pveum token list

# Should show: terraform@pam!terraform
```

### Check User Permissions
```bash
# View permissions for terraform user
pveum user permissions terraform@pam

# Should show:
# /       terraform@pam  PVEVMAdmin  1
```

### Check Template Exists
```bash
# List all VMs and templates
qm list

# Look for VM ID 9000 (should be marked as template)
```

### Test API Access
```bash
# Test authentication (replace with your token)
curl -k -H "Authorization: PVEAPIToken=terraform@pam!terraform=YOUR-TOKEN-HERE" \
  https://192.168.0.7:8006/api2/json/version
```

## Common Permission Issues

### Issue 1: Permission on Specific VM Only

**Problem**: Permission granted only on `/vms/9000` instead of root `/`

**Solution**: Grant at root level with propagate:
```bash
pveum acl modify / -user terraform@pam -role PVEVMAdmin -propagate 1
```

### Issue 2: Propagate Not Enabled

**Problem**: Permission exists but doesn't propagate to child resources

**Solution**: Add `-propagate 1` flag:
```bash
pveum acl modify / -user terraform@pam -role PVEVMAdmin -propagate 1
```

### Issue 3: Wrong User Name

**Problem**: Token uses different user than permission grants

**Solution**: Match token user exactly:
```bash
# Check token user
pveum token list

# Grant permission to exact user
pveum acl modify / -user terraform@pam -role PVEVMAdmin -propagate 1
```

### Issue 4: Insufficient Role

**Problem**: Using PVEVMUser instead of PVEVMAdmin

**Solution**: Upgrade to PVEVMAdmin role:
```bash
# Remove old permission
pveum acl delete / -user terraform@pam

# Add with correct role
pveum acl modify / -user terraform@pam -role PVEVMAdmin -propagate 1
```

### Issue 5: Template Doesn't Exist

**Problem**: Template VM 9000 doesn't exist or isn't marked as template

**Solution**: 
```bash
# Check if VM exists
qm list | grep 9000

# If it exists but isn't a template, convert it
qm template 9000

# Or create/import a new template
```

## Alternative: Use Root Credentials (Not Recommended)

For testing purposes only, you can use root credentials instead of API tokens:

### In terraform.tfvars:
```hcl
# Comment out API token
# proxmox_api_token_id     = "terraform@pam!terraform"
# proxmox_api_token_secret = "..."

# Use password instead
proxmox_password = "your-root-password"
```

### In provider configuration (providers.tf):
```hcl
provider "proxmox" {
  endpoint = var.proxmox_api_url
  username = "root@pam"  # Changed from terraform@pam
  password = var.proxmox_password
  insecure = true
}
```

**⚠️ Warning**: Using root credentials is less secure. API tokens are recommended for production.

## Creating API Token from Scratch

If you need to create a new API token:

### Via Proxmox UI
1. `Datacenter` → `Permissions` → `API Tokens`
2. Click `Add`
3. Fill in:
   - **User**: `terraform@pam`
   - **Token ID**: `terraform`
   - **Privilege Separation**: ✓ Unchecked (or grant permissions separately)
4. Click `Add`
5. **Save the token secret** (shown only once!)

### Via SSH
```bash
# Create API token
pveum user token add terraform@pam terraform --privsep 0

# This will output the token secret - save it!
```

### Grant Permissions
```bash
pveum acl modify / -user terraform@pam -role PVEVMAdmin -propagate 1
```

## Verify Terraform Configuration

### Check provider.tf
```hcl
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true
  ssh {
    agent    = true
    username = var.ssh_user
  }
}
```

### Check terraform.tfvars
```hcl
proxmox_api_url          = "https://192.168.0.7:8006/api2/json"
proxmox_api_token_id     = "terraform@pam!terraform"
proxmox_api_token_secret = "your-actual-token-secret"
```

## Testing After Fix

### Test 1: Verify Permissions
```bash
pveum user permissions terraform@pam
```

Expected output:
```
/       terraform@pam  PVEVMAdmin  1
```

### Test 2: Test API Call
```bash
# Replace with your actual values
TOKEN_ID="terraform@pam!terraform"
TOKEN_SECRET="your-token-secret"

curl -k -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
  "https://192.168.0.7:8006/api2/json/nodes/pve/qemu"
```

### Test 3: Run Terraform Plan
```bash
terraform plan
```

Should no longer show permission errors.

### Test 4: Try Terraform Apply
```bash
terraform apply -target=proxmox_virtual_environment_vm.bumblebee
```

## Role Comparison

| Role | VM.Clone | VM.Allocate | VM.Config | Full VM Control |
|------|----------|-------------|-----------|-----------------|
| **PVEVMAdmin** | ✓ | ✓ | ✓ | ✓ |
| **PVEVMUser** | ✗ | ✗ | Limited | ✗ |
| **Administrator** | ✓ | ✓ | ✓ | ✓ |

**Recommendation**: Use `PVEVMAdmin` for Terraform.

## Security Best Practices

1. **Use API Tokens** instead of passwords
2. **Dedicated User** - Create `terraform@pam` specifically for automation
3. **Minimum Permissions** - Start with `PVEVMAdmin` on specific paths
4. **Privilege Separation** - Enable if you need fine-grained control
5. **Rotate Tokens** - Periodically regenerate API tokens
6. **Audit Logs** - Monitor Proxmox audit logs for unauthorized access

## Related Documentation

- [Proxmox User Management](https://pve.proxmox.com/wiki/User_Management)
- [Proxmox API Tokens](https://pve.proxmox.com/wiki/Proxmox_VE_API#API_Tokens)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)

## Quick Reference Commands

```bash
# Grant permissions
pveum acl modify / -user terraform@pam -role PVEVMAdmin -propagate 1

# View permissions
pveum user permissions terraform@pam

# List tokens
pveum token list

# Create new token
pveum user token add terraform@pam terraform --privsep 0

# Remove permission
pveum acl delete / -user terraform@pam

# List all VMs
qm list

# Check if VM is template
qm config 9000 | grep template
```

## Still Having Issues?

If permissions are correct but you still get errors:

1. **Check Proxmox logs**: `/var/log/pve/tasks/`
2. **Verify network**: Can Terraform reach Proxmox API?
3. **Check SSL**: Try with `insecure = true` in provider
4. **Validate template**: Ensure VM 9000 exists and is a template
5. **Test with root**: Temporarily use root credentials to isolate issue

---

**Last Updated**: November 4, 2025

