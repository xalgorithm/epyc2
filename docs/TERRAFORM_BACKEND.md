# Terraform NFS Backend Configuration

This document explains how the Terraform state is stored on the NFS server for centralized state management.

## Overview

The Terraform state file is stored on the NFS server at:
- **NFS Server:** `192.168.0.7`
- **NFS Path:** `/data/kubernetes/terraform-state/terraform.tfstate`
- **Local Mount:** `/mnt/nfs-k8s`

## Benefits

✅ **Centralized State:** Single source of truth for infrastructure state
✅ **Backup:** State is stored on the same NFS server as cluster data
✅ **Team Collaboration:** Multiple users can work with the same state
✅ **Persistent:** Survives local machine failures or reinstalls

## Setup

### Initial Setup (First Time)

1. **Mount the NFS share:**
   ```bash
   sudo ./scripts/deployment/setup-nfs-backend.sh
   ```

   This script will:
   - Install NFS client if needed
   - Mount the NFS share to `/mnt/nfs-k8s`
   - Create the terraform state directory
   - Add entry to `/etc/fstab` for persistent mounting
   - Set proper permissions

2. **Backup your current state:**
   ```bash
   cp terraform.tfstate terraform.tfstate.backup
   ```

3. **Initialize the backend:**
   ```bash
   terraform init -migrate-state
   ```

   Terraform will ask if you want to migrate your existing state. Answer `yes`.

4. **Verify the migration:**
   ```bash
   terraform state list
   ls -lh /mnt/nfs-k8s/terraform-state/
   ```

### After System Reboot

The NFS mount is persistent (added to `/etc/fstab`), so it will automatically mount on boot. However, if needed:

```bash
# Check if mounted
mountpoint /mnt/nfs-k8s

# If not mounted, remount
sudo mount /mnt/nfs-k8s

# Or run setup script again
sudo ./scripts/deployment/setup-nfs-backend.sh
```

## Usage

### Normal Operations

Once configured, Terraform will automatically:
- ✅ Read state from NFS on `terraform plan`
- ✅ Write state to NFS on `terraform apply`
- ✅ Lock state during operations (via local file locking)

### Working from Multiple Machines

1. Setup NFS backend on each machine:
   ```bash
   sudo ./scripts/deployment/setup-nfs-backend.sh
   ```

2. Initialize Terraform (will use existing state):
   ```bash
   terraform init
   ```

3. Work normally with Terraform commands

**Important:** Always ensure the NFS mount is available before running Terraform commands.

## Backup and Recovery

### Manual Backup

```bash
# Backup current state
cp /mnt/nfs-k8s/terraform-state/terraform.tfstate \
   /mnt/nfs-k8s/terraform-state/terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)
```

### Restore from Backup

```bash
# List backups
ls -lh /mnt/nfs-k8s/terraform-state/terraform.tfstate.backup.*

# Restore specific backup
cp /mnt/nfs-k8s/terraform-state/terraform.tfstate.backup.TIMESTAMP \
   /mnt/nfs-k8s/terraform-state/terraform.tfstate
```

### State History

Terraform automatically creates backup files:
```bash
# View state backups
ls -lh /mnt/nfs-k8s/terraform-state/terraform.tfstate.backup
```

## Troubleshooting

### Mount Issues

**Problem:** NFS not mounting

**Solution:**
```bash
# Test NFS connectivity
showmount -e 192.168.0.7

# Check NFS server is accessible
ping 192.168.0.7

# Check NFS exports
ssh root@192.168.0.7 'exportfs -v'

# Try manual mount
sudo mount -t nfs 192.168.0.7:/data/kubernetes /mnt/nfs-k8s
```

### Permission Issues

**Problem:** Cannot write to state file

**Solution:**
```bash
# Check permissions
ls -ld /mnt/nfs-k8s/terraform-state/

# Fix permissions
sudo chown -R $USER:$USER /mnt/nfs-k8s/terraform-state/
sudo chmod 755 /mnt/nfs-k8s/terraform-state/
```

### State Lock Issues

**Problem:** State locked by another operation

**Solution:**
```bash
# Check for .tflock files
ls -la /mnt/nfs-k8s/terraform-state/

# Remove stale lock (ONLY if you're sure no one else is using it)
rm /mnt/nfs-k8s/terraform-state/.terraform.tfstate.lock.info

# Force unlock in Terraform
terraform force-unlock LOCK_ID
```

### Unmounting NFS

If you need to unmount the NFS share:

```bash
sudo ./scripts/maintenance/unmount-nfs-backend.sh
```

**Warning:** Do NOT unmount while Terraform operations are running!

## Migration Back to Local State

If you need to move back to local state:

1. **Comment out the backend configuration:**
   ```bash
   # Edit backend.tf and comment out the backend block
   ```

2. **Reinitialize:**
   ```bash
   terraform init -migrate-state
   ```

3. **Unmount NFS:**
   ```bash
   sudo ./scripts/maintenance/unmount-nfs-backend.sh
   ```

## Files

- `backend.tf` - Backend configuration
- `scripts/deployment/setup-nfs-backend.sh` - Setup script
- `scripts/maintenance/unmount-nfs-backend.sh` - Unmount script
- `docs/TERRAFORM_BACKEND.md` - This documentation

## Security Considerations

⚠️ **State files contain sensitive data!**

- Credentials
- Private keys
- Resource IDs
- IP addresses

**Best Practices:**
1. ✅ Restrict NFS access to trusted network only
2. ✅ Use firewall rules on NFS server
3. ✅ Regular backups
4. ✅ Don't commit state files to git
5. ✅ Limit access to NFS share

## Monitoring

Check state file location:
```bash
# Verify backend configuration
terraform providers

# Check state location
ls -lh /mnt/nfs-k8s/terraform-state/

# Verify NFS mount
df -h /mnt/nfs-k8s
```

## Support

For issues or questions:
1. Check this documentation
2. Review NFS server logs: `ssh root@192.168.0.7 'journalctl -u nfs-server -f'`
3. Check Terraform logs: `TF_LOG=DEBUG terraform plan`

