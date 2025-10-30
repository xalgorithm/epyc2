# Manual Backup Quick Reference Guide

This guide provides quick reference for performing manual backups of your Kubernetes cluster and applications.

## Quick Start

### Full Backup (Everything)

```bash
./scripts/trigger-manual-backup.sh
```

### Application Data Only

```bash
./scripts/trigger-manual-backup.sh apps
```

### Specific Application

```bash
./scripts/trigger-manual-backup.sh grafana
./scripts/trigger-manual-backup.sh prometheus
./scripts/trigger-manual-backup.sh netalertx
```

## Available Scripts

### 1. `trigger-manual-backup.sh` (Recommended)

**Purpose**: Triggers manual backups by creating Kubernetes jobs  
**Location**: Run from your local machine with kubectl access  
**Features**:

- Creates Kubernetes job for backup execution
- Follows backup progress in real-time
- Handles job cleanup automatically
- Provides detailed status reporting

**Usage**:

```bash
./scripts/trigger-manual-backup.sh [TYPE] [LOCATION]

# Examples
./scripts/trigger-manual-backup.sh                    # Full backup
./scripts/trigger-manual-backup.sh apps              # Apps only
./scripts/trigger-manual-backup.sh all /backup       # Custom location
```

### 2. `manual-backup-comprehensive.sh`

**Purpose**: Comprehensive backup script that runs inside cluster  
**Location**: Runs inside Kubernetes pods via the trigger script  
**Features**:

- Same backup methods as scheduled system
- Supports all application types
- Creates detailed backup summaries
- Handles missing services gracefully

**Direct Usage** (if running inside cluster):

```bash
/scripts/manual-backup-comprehensive.sh [TYPE] [LOCATION]
```

### 3. `manual-backup.sh` (Legacy)

**Purpose**: Basic manual backup script  
**Location**: Run from control plane or with SSH access  
**Features**:

- Basic ETCD and resource backup
- Requires SSH access to control plane
- Limited application data support

## Backup Types

| Type | What's Backed Up | Use Case |
|------|------------------|----------|
| `all` | Everything | Complete system backup |
| `etcd` | ETCD snapshots + PKI | Cluster state backup |
| `resources` | K8s manifests | Configuration backup |
| `apps` | All application data | Application data backup |
| `netalertx` | NetAlertX DB + config | Network monitoring backup |
| `grafana` | Grafana DB + dashboards | Monitoring dashboards backup |
| `prometheus` | Prometheus TSDB | Metrics data backup |
| `loki` | Loki log data | Log data backup |
| `mimir` | Mimir metrics data | Long-term metrics backup |

## Backup Locations

### Default Location

- **Path**: `/tmp/k8s-backup/YYYYMMDD_HHMMSS/`
- **Access**: Via backup pods or NFS mount
- **Retention**: Manual cleanup required

### Custom Location

```bash
./scripts/trigger-manual-backup.sh all /custom/path
```

### NFS Storage

Backups are stored on the configured NFS server and accessible via:

- **NFS Server**: `<configured-nfs-server-ip>` (from terraform.tfvars)
- **NFS Path**: `<configured-nfs-path>` (from terraform.tfvars)
- **Backup pods mount**: `/backup/`
- **Backup metrics pod mount**: `/host/backup/`
- **Direct NFS access**: Mount `<nfs-server-ip>:<nfs-path>`

## Monitoring Manual Backups

### Check Job Status

```bash
# List manual backup jobs
kubectl get jobs -n backup -l app=manual-backup

# Check specific job
kubectl get job manual-backup-TIMESTAMP -n backup

# View job details
kubectl describe job manual-backup-TIMESTAMP -n backup
```

### View Logs

```bash
# Get pod name
POD_NAME=$(kubectl get pods -n backup -l job-name=manual-backup-TIMESTAMP -o jsonpath='{.items[0].metadata.name}')

# View logs
kubectl logs $POD_NAME -n backup

# Follow logs (if still running)
kubectl logs -f $POD_NAME -n backup
```

### Cleanup Jobs

```bash
# Delete specific job
kubectl delete job manual-backup-TIMESTAMP -n backup

# Delete all completed manual backup jobs
kubectl delete jobs -n backup -l app=manual-backup --field-selector status.successful=1
```

## Backup Output Structure

```
/backup/location/YYYYMMDD_HHMMSS/
├── etcd/
│   ├── etcd-snapshot-YYYYMMDD_HHMMSS.db
│   └── pki/
├── resources/
│   ├── namespaces.yaml
│   ├── monitoring/
│   ├── netalertx/
│   └── cluster/
├── persistent-data/
│   ├── netalertx/
│   │   ├── app.db
│   │   ├── app.conf
│   │   ├── logs.tar.gz
│   │   └── backup-info.txt
│   ├── grafana/
│   │   ├── grafana.db
│   │   ├── grafana-data.tar.gz
│   │   └── backup-info.txt
│   ├── prometheus/
│   │   ├── prometheus-snapshot.tar.gz
│   │   └── backup-info.txt
│   ├── loki/
│   │   ├── loki-data.tar.gz
│   │   └── backup-info.txt
│   └── mimir/
│       ├── mimir-data.tar.gz
│       └── backup-info.txt
└── backup-summary.txt
```

## Common Use Cases

### 1. Pre-Maintenance Backup

```bash
# Full backup before maintenance
./scripts/trigger-manual-backup.sh all /backup/pre-maintenance-$(date +%Y%m%d)
```

### 2. Application-Specific Backup

```bash
# Before Grafana updates
./scripts/trigger-manual-backup.sh grafana

# Before Prometheus configuration changes
./scripts/trigger-manual-backup.sh prometheus
```

### 3. Configuration Backup

```bash
# Backup only Kubernetes resources
./scripts/trigger-manual-backup.sh resources
```

### 4. Emergency Backup

```bash
# Quick application data backup
./scripts/trigger-manual-backup.sh apps /emergency-backup
```

## Troubleshooting

### Test Backup System

```bash
# Run connectivity test
./scripts/test-backup-connectivity.sh

# Diagnose NFS access issues
./scripts/diagnose-nfs-access.sh

# Test NFS access specifically
./scripts/fix-nfs-permissions.sh --test-access

# Test NFS access via backup pod
kubectl exec -n backup deployment/backup-metrics -- ls -la /host/backup
kubectl exec -n backup deployment/backup-metrics -- df -h /host/backup
```

### Fix NFS Access Issues

```bash
# Show required NFS configuration
./scripts/fix-nfs-permissions.sh --show-config

# Try to fix NFS remotely (if SSH access available)
./scripts/fix-nfs-permissions.sh --remote-fix

# Manual NFS server configuration (run on 192.168.1.7)
sudo mkdir -p /data/kubernetes/backups
sudo chown nobody:nogroup /data/kubernetes/backups
sudo chmod 755 /data/kubernetes/backups

# Add to /etc/exports
echo '/data/kubernetes/backups 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)' | sudo tee -a /etc/exports
echo '/data/kubernetes/backups 10.42.0.0/16(rw,sync,no_subtree_check,no_root_squash)' | sudo tee -a /etc/exports

# Reload NFS
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

### Job Fails to Start

```bash
# Check backup namespace
kubectl get namespace backup

# Check service account
kubectl get serviceaccount backup -n backup

# Check configmap
kubectl get configmap backup-scripts -n backup
```

### Backup Fails

```bash
# Check pod logs
kubectl logs -l app=manual-backup -n backup

# Check application pod status
kubectl get pods -n monitoring
kubectl get pods -n netalertx

# Check storage access
kubectl exec -n backup deployment/backup-metrics -- ls -la /backup
```

### Storage Issues

```bash
# Check NFS connectivity
kubectl exec -n backup deployment/backup-metrics -- df -h /backup

# Check available space
kubectl exec -n backup deployment/backup-metrics -- du -sh /backup/*
```

### Permission Issues

```bash
# Check service account permissions
kubectl auth can-i --list --as=system:serviceaccount:backup:backup

# Check pod security context
kubectl get pod POD_NAME -n backup -o yaml | grep -A 10 securityContext
```

## Best Practices

### 1. Regular Testing

- Test manual backups regularly
- Verify backup completeness
- Practice restore procedures

### 2. Backup Before Changes

- Always backup before major changes
- Use descriptive backup locations
- Document backup reasons

### 3. Storage Management

- Monitor backup storage usage
- Clean up old manual backups
- Use compression for large backups

### 4. Verification

- Check backup-summary.txt for completeness
- Verify critical application data
- Test restore procedures periodically

## Integration with Scheduled Backups

Manual backups complement the scheduled backup system:

- **Scheduled**: Daily automated backups for regular protection
- **Manual**: On-demand backups for specific events or changes
- **Both**: Use same backup methods and storage locations
- **Monitoring**: Both visible in Grafana backup dashboard

## Quick Commands Reference

```bash
# Full backup
./scripts/trigger-manual-backup.sh

# Apps only
./scripts/trigger-manual-backup.sh apps

# Custom location
./scripts/trigger-manual-backup.sh all /custom/path

# Check status
kubectl get jobs -n backup -l app=manual-backup

# View logs
kubectl logs -l app=manual-backup -n backup

# Cleanup
kubectl delete jobs -n backup -l app=manual-backup

# Help
./scripts/trigger-manual-backup.sh help
```
