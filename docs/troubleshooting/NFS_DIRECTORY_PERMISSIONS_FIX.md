# NFS Directory Creation Permissions Fix

## Problem
Manual backup jobs are failing with directory creation errors like:
```
unable to create directories: path is - backup/manual-backup-xxxxx
```

## Root Cause
The NFS mount doesn't have proper write permissions for the Kubernetes pods to create backup directories. This typically happens when:

1. **NFS exports don't include pod networks**
2. **NFS directory permissions are too restrictive**
3. **Missing `no_root_squash` option in NFS exports**
4. **NFS server doesn't allow directory creation**

## Diagnostic Steps

### 1. Test NFS Permissions
```bash
# Test directory creation permissions
./scripts/test-nfs-permissions.sh

# Comprehensive NFS diagnosis
./scripts/diagnose-nfs-access.sh

# Test kubectl access (separate issue)
./scripts/test-manual-backup-kubectl.sh
```

### 2. Check Current NFS Configuration
```bash
# From backup pod
kubectl exec -n backup deployment/backup-metrics -- ls -la /host/backup
kubectl exec -n backup deployment/backup-metrics -- mount | grep nfs
kubectl exec -n backup deployment/backup-metrics -- df -h /host/backup
```

### 3. Check NFS Server Status
```bash
# On NFS server (192.168.1.7)
sudo exportfs -v
showmount -e localhost
ls -la /data/kubernetes/backups
```

## Complete Fix

### Step 1: Configure NFS Server (192.168.1.7)

```bash
# Create backup directory with proper permissions
sudo mkdir -p /data/kubernetes/backups
sudo chown nobody:nogroup /data/kubernetes/backups
sudo chmod 755 /data/kubernetes/backups

# Check current exports
sudo exportfs -v

# Edit /etc/exports (add these lines if not present)
sudo nano /etc/exports

# Add these lines:
/data/kubernetes/backups 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
/data/kubernetes/backups 10.42.0.0/16(rw,sync,no_subtree_check,no_root_squash)

# Reload NFS exports
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server

# Verify exports
sudo exportfs -v
showmount -e localhost
```

### Step 2: Test NFS Access
```bash
# Test directory creation
./scripts/test-nfs-permissions.sh

# Should show successful directory and file creation
```

### Step 3: Fix Kubeconfig (if needed)
```bash
# Apply Terraform changes to fix kubeconfig encoding
terraform apply

# Or fix existing secret
./scripts/fix-kubeconfig-secret.sh
```

### Step 4: Test Manual Backup
```bash
# Test application backup
./scripts/trigger-manual-backup.sh apps

# Should now work without directory creation errors
```

## Automated Fix Options

### Option 1: Complete Automated Fix
```bash
# Try to fix everything automatically
./scripts/complete-nfs-fix.sh
```

### Option 2: NFS-Specific Fix
```bash
# Fix NFS server configuration remotely
./scripts/fix-nfs-permissions.sh --remote-fix

# Test the fix
./scripts/test-nfs-permissions.sh
```

### Option 3: Manual Step-by-Step
```bash
# 1. Show what needs to be configured
./scripts/fix-nfs-permissions.sh --show-config

# 2. Apply the configuration on NFS server
# (follow the displayed commands)

# 3. Test permissions
./scripts/test-nfs-permissions.sh

# 4. Test backup
./scripts/trigger-manual-backup.sh apps
```

## Key NFS Export Options

| Option | Purpose | Why Needed |
|--------|---------|------------|
| `rw` | Read-write access | Backup jobs need to write files |
| `sync` | Synchronous writes | Data integrity |
| `no_subtree_check` | Performance | Safe for dedicated backup directory |
| `no_root_squash` | Root access | Kubernetes pods may run as root |

## Network Requirements

The NFS server must allow access from:

1. **Node Network**: `192.168.1.0/24` (where Kubernetes nodes are)
2. **Pod Network**: `10.42.0.0/16` (where backup pods get IPs)

## Verification Commands

### Test from Kubernetes Node
```bash
# Test NFS mount from a Kubernetes node
sudo mkdir -p /tmp/nfs-test
sudo mount -t nfs 192.168.1.7:/data/kubernetes/backups /tmp/nfs-test
sudo mkdir -p /tmp/nfs-test/test-dir
sudo touch /tmp/nfs-test/test-dir/test-file
sudo ls -la /tmp/nfs-test/test-dir/
sudo umount /tmp/nfs-test
```

### Test from NFS Server
```bash
# On NFS server (192.168.1.7)
ls -la /data/kubernetes/backups
touch /data/kubernetes/backups/server-test-file
ls -la /data/kubernetes/backups/server-test-file
rm /data/kubernetes/backups/server-test-file
```

## Common Error Messages and Fixes

### "Permission denied"
- **Cause**: NFS exports don't include pod network or missing `no_root_squash`
- **Fix**: Add pod network to exports with `no_root_squash`

### "Operation not permitted"
- **Cause**: Directory ownership or permissions issue
- **Fix**: `sudo chown nobody:nogroup /data/kubernetes/backups`

### "No space left on device"
- **Cause**: NFS server storage full
- **Fix**: Clean up old backups or expand storage

### "Stale file handle"
- **Cause**: NFS server restarted or exports changed
- **Fix**: Restart backup pods or remount NFS

## Success Indicators

After fixing, you should see:

1. **NFS Permissions Test**: ✅ Success
2. **Directory Creation**: ✅ Success  
3. **File Creation**: ✅ Success
4. **Manual Backup**: ✅ Success
5. **Backup Files**: Visible on NFS server at `/data/kubernetes/backups`

## Files Created for This Fix

1. **`scripts/test-nfs-permissions.sh`** - Test directory creation permissions
2. **`scripts/fix-kubeconfig-secret.sh`** - Fix kubeconfig encoding
3. **Enhanced `scripts/manual-backup-comprehensive.sh`** - Better error handling
4. **`NFS_DIRECTORY_PERMISSIONS_FIX.md`** - This troubleshooting guide

The backup system should work correctly once the NFS server allows directory creation from Kubernetes pods with proper permissions.