# NFS Access Fix for Kubernetes Backups

## Problem
The backup system is failing with "NFS write access failed" because the NFS server at 192.168.1.7 doesn't allow access from the Kubernetes pod networks.

## Root Cause
Kubernetes pods run on different network ranges than the host nodes, and the NFS server needs to be configured to allow access from both:
1. **Node Network**: 192.168.1.0/24 (where Kubernetes nodes are)
2. **Pod Network**: Usually 10.42.0.0/16 (where pods get their IPs)

## Quick Fix

### Option 1: Automated Fix (Recommended)
```bash
# Diagnose the issue and get exact network ranges
./scripts/diagnose-nfs-access.sh

# Try to fix automatically (requires SSH access to NFS server)
./scripts/fix-nfs-permissions.sh --remote-fix

# Test the fix
./scripts/fix-nfs-permissions.sh --test-access
```

### Option 2: Manual Fix
Run these commands on your NFS server (192.168.1.7):

```bash
# 1. Create the backup directory
sudo mkdir -p /data/kubernetes/backups
sudo chown nobody:nogroup /data/kubernetes/backups
sudo chmod 755 /data/kubernetes/backups

# 2. Add NFS exports (edit /etc/exports)
sudo nano /etc/exports

# Add these lines to /etc/exports:
/data/kubernetes/backups 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
/data/kubernetes/backups 10.42.0.0/16(rw,sync,no_subtree_check,no_root_squash)

# 3. Reload NFS configuration
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server

# 4. Verify exports
sudo exportfs -v
showmount -e localhost
```

## Verification Steps

### 1. Test NFS Access
```bash
# Test from Kubernetes
./scripts/test-backup-connectivity.sh

# Test NFS specifically
./scripts/fix-nfs-permissions.sh --test-access
```

### 2. Test Manual Backup
```bash
# Try a small backup test
./scripts/trigger-manual-backup.sh apps
```

### 3. Check from NFS Server
```bash
# On the NFS server (192.168.1.7)
showmount -e localhost
sudo exportfs -v
ls -la /data/kubernetes/backups
```

## Understanding the NFS Configuration

### Export Options Explained
- `rw`: Read-write access
- `sync`: Synchronous writes (safer but slower)
- `no_subtree_check`: Improves performance, safe for dedicated backup directory
- `no_root_squash`: Allows root access from clients (needed for Kubernetes pods)

### Network Ranges
- `192.168.1.0/24`: Your main network where Kubernetes nodes are located
- `10.42.0.0/16`: Default Kubernetes pod network (may vary in your setup)

### Security Considerations
- `no_root_squash` allows root access from the specified networks
- Ensure these networks are trusted
- Consider using `root_squash` if your pods don't need root access

## Troubleshooting

### If Automated Fix Fails
1. Check SSH access to NFS server
2. Verify sudo permissions on NFS server
3. Use manual fix method instead

### If Manual Fix Doesn't Work
1. Check firewall rules on NFS server
2. Verify NFS service is running: `sudo systemctl status nfs-kernel-server`
3. Check network connectivity: `ping 192.168.1.7` from Kubernetes nodes
4. Verify pod network range with: `./scripts/diagnose-nfs-access.sh`

### Common Issues
- **Permission denied**: Usually means NFS exports don't include pod network
- **Connection refused**: NFS service not running or firewall blocking
- **Stale file handle**: NFS server restarted, remount needed

## Testing Commands

```bash
# Comprehensive diagnosis
./scripts/diagnose-nfs-access.sh

# Show what needs to be configured
./scripts/fix-nfs-permissions.sh --show-config

# Test current access
./scripts/fix-nfs-permissions.sh --test-access

# Try automated fix
./scripts/fix-nfs-permissions.sh --remote-fix

# Test backup system
./scripts/test-backup-connectivity.sh

# Try actual backup
./scripts/trigger-manual-backup.sh apps
```

## After Fix is Applied

1. **Test Scheduled Backups**: Wait for next scheduled backup or trigger manually
2. **Monitor Grafana Dashboard**: Check backup metrics in Grafana
3. **Verify Backup Files**: Check `/data/kubernetes/backups` on NFS server
4. **Test Restore**: Try restoring from a backup to ensure completeness

The backup system should work correctly once the NFS server allows access from both the node network (192.168.1.0/24) and pod network (typically 10.42.0.0/16).