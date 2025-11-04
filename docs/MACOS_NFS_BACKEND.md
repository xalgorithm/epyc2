# macOS NFS Backend Setup Guide

## Overview

This guide covers the macOS-specific setup for Terraform NFS backend. All scripts automatically detect your OS and configure accordingly.

## Quick Start

```bash
# 1. Check status
./scripts/maintenance/check-backend-status.sh

# 2. Setup NFS backend (auto-detects macOS)
sudo ./scripts/deployment/setup-nfs-backend.sh

# 3. Backup current state
cp terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)

# 4. Migrate to NFS backend
terraform init -migrate-state

# 5. Verify
terraform state list
ls -lh /Volumes/nfs-k8s/terraform-state/
```

## macOS vs Linux Differences

| Feature | macOS | Linux |
|---------|-------|-------|
| **Mount Point** | `/Volumes/nfs-k8s` | `/mnt/nfs-k8s` |
| **NFS Client** | Built-in | Requires `nfs-common` package |
| **Mount Command** | `mount -t nfs -o resvport` | `mount -t nfs` |
| **Persistence** | Mount script (`/usr/local/bin/mount-nfs-k8s.sh`) | `/etc/fstab` entry |
| **Unmount** | `umount -f` (forced) | `umount -l` (lazy) |
| **Mount Check** | `mount \| grep` | `mountpoint -q` |
| **Stat Command** | `stat -f` | `stat -c` |

## macOS Configuration Details

### Mount Point
- **Path**: `/Volumes/nfs-k8s`
- **Why**: macOS convention for external volumes
- **Created by**: Setup script

### NFS Mount Options
```bash
mount -t nfs -o resvport 192.168.0.7:/data/kubernetes /Volumes/nfs-k8s
```
- `-o resvport`: Uses reserved port (required for some NFS servers)

### Persistence (No Auto-Mount on Reboot)

Unlike Linux, macOS doesn't have a simple `/etc/fstab` equivalent for NFS mounts. The setup script creates a helper script:

**Location**: `/usr/local/bin/mount-nfs-k8s.sh`

**To remount after reboot**:
```bash
sudo /usr/local/bin/mount-nfs-k8s.sh
```

Or just run the setup script again:
```bash
sudo ./scripts/deployment/setup-nfs-backend.sh
```

## Daily Workflow on macOS

### After System Reboot
1. Check if NFS is mounted:
   ```bash
   mount | grep nfs-k8s
   ```

2. If not mounted:
   ```bash
   sudo /usr/local/bin/mount-nfs-k8s.sh
   # OR
   sudo ./scripts/deployment/setup-nfs-backend.sh
   ```

### Normal Terraform Operations
Once mounted, use Terraform normally:
```bash
terraform plan
terraform apply
terraform destroy
```

### Useful Commands
```bash
# Check backend status
./scripts/maintenance/check-backend-status.sh

# Check if mounted
mount | grep nfs-k8s

# View state file
cat /Volumes/nfs-k8s/terraform-state/terraform.tfstate | jq .

# List resources
terraform state list

# Backup state
cp /Volumes/nfs-k8s/terraform-state/terraform.tfstate \
   /Volumes/nfs-k8s/terraform-state/terraform.tfstate.backup.$(date +%Y%m%d)

# Unmount when needed
sudo ./scripts/maintenance/unmount-nfs-backend.sh
```

## Troubleshooting

### NFS Server Not Reachable
```bash
# Test connectivity
ping 192.168.0.7

# Check NFS exports
showmount -e 192.168.0.7
```

### Mount Fails - Firewall Issues
macOS Firewall may block NFS:

1. **System Preferences** → **Security & Privacy** → **Firewall**
2. Click **Firewall Options**
3. Allow: `nfsd`, `rpc.lockd`, `rpc.statd`

Or temporarily disable firewall:
```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off
```

### Permission Denied
```bash
# Fix ownership
sudo chown -R $USER:$USER /Volumes/nfs-k8s/terraform-state
```

### Mount Point Busy
```bash
# Check what's using it
lsof +D /Volumes/nfs-k8s

# Force unmount
sudo umount -f /Volumes/nfs-k8s
```

### State File Not Found
If Terraform can't find state after mount:
```bash
# Verify mount
mount | grep nfs-k8s

# Check file exists
ls -lh /Volumes/nfs-k8s/terraform-state/terraform.tfstate

# Verify backend config
grep -A 2 "backend" backend.tf
```

## Files Modified for macOS Compatibility

### 1. `backend.tf`
```hcl
terraform {
  backend "local" {
    # macOS path
    path = "/Volumes/nfs-k8s/terraform-state/terraform.tfstate"
  }
}
```

### 2. `scripts/deployment/setup-nfs-backend.sh`
- Auto-detects OS: `OS_TYPE=$(uname -s)`
- Sets mount point: `/Volumes/nfs-k8s` on macOS
- Uses correct mount options: `-o resvport`
- Creates mount script instead of fstab entry

### 3. `scripts/maintenance/unmount-nfs-backend.sh`
- Auto-detects OS
- Uses `umount -f` on macOS
- Uses `mount | grep` for mount checks

### 4. `scripts/check-backend-status.sh`
- Auto-detects OS
- Checks for mount script on macOS
- Uses macOS-specific stat command

### 5. `.gitignore`
```
/Volumes/nfs-k8s/
```

## Backend Configuration

The `backend.tf` file is configured for macOS by default. If you need to use this on Linux, comment out the macOS path and uncomment the Linux path:

```hcl
terraform {
  backend "local" {
    # macOS path (default)
    # path = "/Volumes/nfs-k8s/terraform-state/terraform.tfstate"
    
    # Linux path (uncomment for Linux)
    path = "/mnt/nfs-k8s/terraform-state/terraform.tfstate"
  }
}
```

## Security Notes

- State files contain **sensitive data** (credentials, IPs, etc.)
- Never commit state files to git (already in `.gitignore`)
- NFS traffic is **unencrypted** - use on trusted networks only
- Consider VPN for remote access to NFS server
- Mount point is only accessible by your user (after setup)

## Automation (Optional)

### Launch Agent for Auto-Mount

Create: `~/Library/LaunchAgents/com.terraform.nfs-mount.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.terraform.nfs-mount</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/mount-nfs-k8s.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
```

Load it:
```bash
launchctl load ~/Library/LaunchAgents/com.terraform.nfs-mount.plist
```

**Note**: This requires the mount script to be in place (created by setup script).

## Benefits

✅ **Centralized State**: One source of truth  
✅ **Disaster Recovery**: Survives local machine failures  
✅ **Team Collaboration**: Ready for multi-user setup  
✅ **Automatic Backups**: State backed up with cluster data  
✅ **Cross-Platform**: Works on macOS and Linux  

## Related Documentation

- [Main Backend Guide](TERRAFORM_BACKEND.md) - Full documentation
- [Backup Guide](backup/BACKUP.md) - Backup and restore procedures
- [Deployment Guide](deployment/DEPLOYMENT-GUIDE.md) - Full stack deployment

## Quick Reference

```bash
# Essential Commands
./scripts/maintenance/check-backend-status.sh      # Check status
sudo ./scripts/deployment/setup-nfs-backend.sh    # Setup/remount
sudo ./scripts/maintenance/unmount-nfs-backend.sh  # Unmount

# After reboot
sudo /usr/local/bin/mount-nfs-k8s.sh   # Quick remount

# Verification
mount | grep nfs-k8s                   # Check mount
ls -lh /Volumes/nfs-k8s/terraform-state/  # Check files
terraform state list                   # Verify Terraform

# Common Operations
terraform init -migrate-state          # Migrate to NFS
terraform init -reconfigure            # Switch backends
```

## Support

If you encounter issues:
1. Run: `./scripts/maintenance/check-backend-status.sh`
2. Check NFS server: `ping 192.168.0.7`
3. Test NFS exports: `showmount -e 192.168.0.7`
4. Review logs in: `/var/log/system.log` (for mount errors)

---

**Last Updated**: November 4, 2025  
**Platform**: macOS (Darwin) 25.1.0

