# Backup and Restore Guide

This guide covers the backup and restore procedures for Mylar, Radarr, and ETCD in the Kubernetes cluster.

## Table of Contents

- [Backup Schedule](#backup-schedule)
- [Backup Locations](#backup-locations)
- [Restore Procedures](#restore-procedures)
  - [Mylar Restore](#mylar-restore)
  - [Radarr Restore](#radarr-restore)
  - [ETCD Restore](#etcd-restore)
- [Manual Backup](#manual-backup)
- [Troubleshooting](#troubleshooting)

## Backup Schedule

All backups run automatically via Kubernetes CronJobs:

| Service | Schedule | Retention | Backup Size (Approx) |
|---------|----------|-----------|----------------------|
| **Mylar** | Daily at 1:00 AM | 7 days | 277 MB |
| **Radarr** | Daily at 1:00 AM | 7 days | 721 MB |
| **ETCD** | Daily at 2:00 AM | 7 days | Varies |

## Backup Locations

All backups are stored on NFS:

- **Server**: `192.168.0.2`
- **Base Path**: `/volume1/Apps/kube-backups`
- **Permissions**: `755`

Directory structure:
```
/volume1/Apps/kube-backups/
├── mylar/
│   └── YYYYMMDD_HHMMSS/
│       ├── mylar-config.tar.gz
│       ├── backup-info.txt
│       └── backup-success
├── radarr/
│   └── YYYYMMDD_HHMMSS/
│       ├── radarr-config.tar.gz
│       ├── backup-info.txt
│       └── backup-success
└── etcd/
    └── YYYYMMDD_HHMMSS/
        ├── etcd-snapshot.db
        ├── pki/ (certificates)
        ├── backup-info.txt
        └── backup-success
```

## Restore Procedures

### Mylar Restore

**Method 1: Using the Helper Script (Recommended)**

```bash
cd /Users/xalg/dev/terraform/epyc2
./scripts/backup/run-restore-mylar.sh
```

This will:
1. Create an interactive pod with access to backups and Mylar config
2. Display available backups with dates and sizes
3. Allow you to select which backup to restore
4. Backup current configuration before restoring
5. Restore the selected backup
6. Clean up the restore pod

**Method 2: Manual Restore**

```bash
# Create restore pod
kubectl run -it restore-mylar --rm --restart=Never \
  --image=alpine:3.18 \
  --namespace=backup \
  --overrides='
{
  "spec": {
    "securityContext": {"fsGroup": 1000},
    "containers": [{
      "name": "restore",
      "image": "alpine:3.18",
      "stdin": true,
      "tty": true,
      "command": ["/bin/sh"],
      "args": ["/scripts/restore-mylar.sh"],
      "volumeMounts": [
        {"name": "scripts", "mountPath": "/scripts"},
        {"name": "backup", "mountPath": "/backup"},
        {"name": "config", "mountPath": "/config"}
      ]
    }],
    "volumes": [
      {"name": "scripts", "configMap": {"name": "backup-scripts", "defaultMode": 493}},
      {"name": "backup", "nfs": {"server": "192.168.0.2", "path": "/volume1/Apps/kube-backups"}},
      {"name": "config", "nfs": {"server": "192.168.0.2", "path": "/volume1/Apps/mylar"}}
    ]
  }
}'
```

**After Restore:**

```bash
# Restart Mylar to apply changes
kubectl rollout restart deployment/mylar -n media

# Verify Mylar is running
kubectl get pods -n media -l app=mylar
```

### Radarr Restore

**Method 1: Using the Helper Script (Recommended)**

```bash
cd /Users/xalg/dev/terraform/epyc2
./scripts/backup/run-restore-radarr.sh
```

This follows the same interactive process as Mylar restore.

**After Restore:**

```bash
# Restart Radarr to apply changes
kubectl rollout restart deployment/radarr -n media

# Verify Radarr is running
kubectl get pods -n media -l app=radarr
```

### ETCD Restore

⚠️ **WARNING**: ETCD restore is a critical operation that will restore the entire Kubernetes cluster state. Only perform this in disaster recovery scenarios.

**Prerequisites:**

1. Ensure you have a valid ETCD backup
2. Have SSH access to the control plane node
3. Understand that ALL current cluster state will be lost

**Procedure:**

```bash
cd /Users/xalg/dev/terraform/epyc2
./scripts/backup/run-restore-etcd.sh
```

**Critical Steps:**

1. The script will create an interactive pod on the control plane
2. **Before confirming the restore**, SSH to the control plane node:
   ```bash
   ssh xalg@192.168.0.32  # or your control plane IP
   sudo systemctl stop kubelet
   sudo systemctl stop containerd
   ```
3. Return to the restore script and select the backup to restore
4. Type `RESTORE` (all caps) to confirm
5. After restore completes, start services on the control plane:
   ```bash
   sudo systemctl start containerd
   sudo systemctl start kubelet
   ```
6. Verify cluster health:
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

**Recovery from Failed ETCD Restore:**

If the restore fails, the script automatically backs up the current ETCD data to:
```
/var/lib/etcd.backup.YYYYMMDD_HHMMSS
```

To recover:
```bash
ssh xalg@192.168.0.32
sudo systemctl stop kubelet
sudo systemctl stop containerd
sudo mv /var/lib/etcd.backup.YYYYMMDD_HHMMSS /var/lib/etcd
sudo systemctl start containerd
sudo systemctl start kubelet
```

## Manual Backup

To trigger a manual backup outside the scheduled times:

**Mylar:**
```bash
kubectl create job --from=cronjob/mylar-backup mylar-manual-backup -n backup
kubectl logs -f job/mylar-manual-backup -n backup
```

**Radarr:**
```bash
kubectl create job --from=cronjob/radarr-backup radarr-manual-backup -n backup
kubectl logs -f job/radarr-manual-backup -n backup
```

**ETCD:**
```bash
kubectl create job --from=cronjob/etcd-backup-kube etcd-manual-backup -n backup
kubectl logs -f job/etcd-manual-backup -n backup
```

## Viewing Backup Status

**Check CronJob schedules:**
```bash
kubectl get cronjobs -n backup
```

**View recent backup jobs:**
```bash
kubectl get jobs -n backup --sort-by=.status.startTime
```

**Check backup logs:**
```bash
# Mylar
kubectl logs -n backup -l app=mylar-backup --tail=50

# Radarr
kubectl logs -n backup -l app=radarr-backup --tail=50

# ETCD
kubectl logs -n backup -l app=etcd-backup-kube --tail=50
```

**List available backups:**
```bash
# Create a temporary pod to list backups
kubectl run -it --rm list-backups \
  --image=alpine:3.18 \
  --restart=Never \
  --namespace=backup \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "list",
      "image": "alpine:3.18",
      "command": ["sh", "-c", "ls -lRh /backup/"],
      "volumeMounts": [{
        "name": "backup",
        "mountPath": "/backup"
      }]
    }],
    "volumes": [{
      "name": "backup",
      "nfs": {
        "server": "192.168.0.2",
        "path": "/volume1/Apps/kube-backups"
      }
    }]
  }
}'
```

## Troubleshooting

### Backup Job Fails

**Check pod logs:**
```bash
kubectl get pods -n backup
kubectl logs <pod-name> -n backup
```

**Common issues:**

1. **NFS mount failure:**
   - Verify NFS server is accessible: `showmount -e 192.168.0.2`
   - Check network connectivity: `ping 192.168.0.2`

2. **Permission denied:**
   - Verify NFS export permissions
   - Check fsGroup in pod spec (should be 1000)

3. **Out of space:**
   - Check NFS storage: `df -h` on NFS server
   - Clean up old backups manually if needed

### Restore Fails

**Mylar/Radarr restore issues:**

1. **Cannot extract backup:**
   - Verify backup file integrity: `tar -tzf backup.tar.gz`
   - Check if backup-success marker exists

2. **Application won't start after restore:**
   - Check pod logs: `kubectl logs -n media <pod-name>`
   - Verify file permissions in config directory
   - Try restoring from a different backup

**ETCD restore issues:**

1. **Cluster won't start:**
   - Check kubelet logs: `journalctl -u kubelet -f`
   - Verify ETCD data directory ownership: `chown -R etcd:etcd /var/lib/etcd`
   - Check ETCD logs: `journalctl -u etcd -f`

2. **Worker nodes disconnected:**
   - May need to rejoin worker nodes to the cluster
   - Generate new join token on control plane
   - Run kubeadm join on worker nodes

### Emergency Recovery

If all else fails and you need to access backups directly:

```bash
# Mount NFS share locally
sudo mkdir -p /mnt/backups
sudo mount -t nfs 192.168.0.2:/volume1/Apps/kube-backups /mnt/backups

# List backups
ls -lh /mnt/backups/

# Extract backup manually
cd /mnt/backups/mylar/YYYYMMDD_HHMMSS
tar -xzf mylar-config.tar.gz -C /destination/path/

# Unmount
sudo umount /mnt/backups
```

## Best Practices

1. **Test restores regularly** - Verify backups are working by performing test restores
2. **Monitor backup jobs** - Set up alerts for failed backup jobs
3. **Keep multiple backup copies** - Consider copying critical backups to a secondary location
4. **Document changes** - Note any configuration changes that might affect restores
5. **Verify after restore** - Always verify application functionality after a restore

## Support

For issues or questions:
- Check pod logs: `kubectl logs -n backup <pod-name>`
- Review CronJob status: `kubectl describe cronjob <cronjob-name> -n backup`
- Verify NFS connectivity: `showmount -e 192.168.0.2`

