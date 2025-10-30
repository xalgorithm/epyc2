# NFS Backup Configuration Fix Summary

## Issue
The backup system was failing because it didn't have the correct NFS server IP and path configuration.

## Solution Applied

### 1. Updated NFS Configuration in terraform.tfvars
```bash
# Before
nfs_backup_path = "/data/backups"

# After  
nfs_backup_path = "/data/kubernetes/backups"
```

**NFS Server IP was already correct**: `192.168.1.7`

### 2. Fixed Manual Backup Script NFS Configuration
Updated `scripts/trigger-manual-backup.sh` to use hardcoded NFS values instead of trying to read from a non-existent configmap:

```yaml
# Before (trying to read from configmap)
server: $(kubectl get configmap -n backup backup-config -o jsonpath='{.data.nfs_server}' 2>/dev/null || echo "nfs-server")
path: $(kubectl get configmap -n backup backup-config -o jsonpath='{.data.nfs_path}' 2>/dev/null || echo "/backup")

# After (hardcoded correct values)
server: "192.168.1.7"
path: "/data/kubernetes/backups"
```

### 3. Created NFS Connectivity Test Script
Added `scripts/test-backup-connectivity.sh` to help diagnose NFS and backup system issues:
- Tests kubectl connectivity
- Verifies backup namespace and resources
- Tests NFS mount accessibility and write permissions
- Checks application pods availability
- Provides troubleshooting information

### 4. Updated Documentation
- **MANUAL_BACKUP_GUIDE.md**: Added NFS configuration details and troubleshooting steps
- **BACKUP_GUIDE.md**: Added NFS server information

## Current NFS Configuration

| Setting | Value |
|---------|-------|
| NFS Server IP | 192.168.1.7 |
| NFS Share Path | /data/kubernetes/backups |
| Mount Point (backup jobs) | /backup |
| Mount Point (metrics pod) | /host/backup |

## Directory Structure on NFS

```
/data/kubernetes/backups/
├── etcd/
│   └── YYYYMMDD_HHMMSS/
│       └── etcd-snapshot.db
└── data/
    └── YYYYMMDD_HHMMSS/
        ├── resources/
        └── persistent-data/
```

## Verification Steps

### 1. Test NFS Connectivity
```bash
./scripts/test-backup-connectivity.sh
```

### 2. Verify NFS Mount in Backup Pod
```bash
kubectl exec -n backup deployment/backup-metrics -- df -h /host/backup
kubectl exec -n backup deployment/backup-metrics -- ls -la /host/backup
```

### 3. Test Manual Backup
```bash
./scripts/trigger-manual-backup.sh apps
```

### 4. Check Scheduled Backup Jobs
```bash
kubectl get cronjobs -n backup
kubectl get jobs -n backup
```

## Troubleshooting Commands

### Check NFS Server Accessibility
```bash
# From any node that can reach the NFS server
showmount -e 192.168.1.7
ping 192.168.1.7
```

### Check Backup Pod NFS Access
```bash
BACKUP_POD=$(kubectl get pods -n backup -l app=backup-metrics -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n backup $BACKUP_POD -- mount | grep nfs
kubectl exec -n backup $BACKUP_POD -- touch /host/backup/test-write
```

### Check Backup Job Logs
```bash
kubectl logs -n backup -l app=data-backup
kubectl logs -n backup -l app=etcd-backup
```

## Files Modified

1. **terraform.tfvars** - Updated `nfs_backup_path`
2. **scripts/trigger-manual-backup.sh** - Fixed NFS configuration
3. **scripts/test-backup-connectivity.sh** - New connectivity test script
4. **backup.tf** - Added test script to ConfigMap
5. **MANUAL_BACKUP_GUIDE.md** - Updated with NFS details
6. **BACKUP_GUIDE.md** - Added NFS configuration info

## Next Steps

1. Apply Terraform changes: `terraform apply`
2. Test connectivity: `./scripts/test-backup-connectivity.sh`
3. Run manual backup test: `./scripts/trigger-manual-backup.sh apps`
4. Monitor scheduled backups: `kubectl get jobs -n backup`
5. Check Grafana backup dashboard for metrics

The backup system should now work correctly with the proper NFS configuration pointing to 192.168.1.7:/data/kubernetes/backups.