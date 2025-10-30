# Kubernetes Cluster Backup and Restore Guide

This guide covers the automated backup system for the Kubernetes cluster, including NetAlertX network monitoring data.

## Backup Overview

The backup system consists of three main components:

1. **ETCD Backup** - Kubernetes cluster state and configuration
2. **Data Backup** - Application data, configurations, and persistent volumes
3. **Backup Cleanup** - Automated retention management

## Backup Schedule

| Backup Type | Schedule | Retention |
|-------------|----------|-----------|
| ETCD Backup | Daily at 2:00 AM | 3 successful jobs |
| Data Backup | Daily at 3:00 AM | 3 successful jobs |
| Cleanup | Weekly on Sunday at 4:00 AM | Configurable days |

## What Gets Backed Up

### Kubernetes Resources
- All namespaces and their resources
- Deployments, Services, ConfigMaps, Secrets
- Persistent Volume Claims
- DaemonSets, StatefulSets, CronJobs
- Cluster-wide resources (ClusterRoles, PVs, StorageClasses)

### Application Data
- **NetAlertX**: Database (`app.db`), configuration (`app.conf`), and logs
- **Grafana**: Database (`grafana.db`), dashboards, plugins, and data directory
- **Prometheus**: TSDB snapshots and metrics data
- **Loki**: Log data and indexes
- **Mimir**: Metrics data and indexes
- **Media Services**: Kubernetes resource definitions
- **MetalLB**: Load balancer configurations

### NetAlertX Specific Backups
- **Database**: `/db/app.db` - Contains all network device data and scan results
- **Configuration**: `/config/app.conf` - NetAlertX settings and preferences
- **Logs**: `/app/front/log/*` - Application logs and scan history

### Observability Stack Backups
- **Grafana**: 
  - Database: `/var/lib/grafana/grafana.db` - User accounts, dashboards, data sources
  - Data Directory: `/var/lib/grafana/*` - Plugins, sessions, and other data
- **Prometheus**: 
  - TSDB Snapshots: Created via API for consistent backups
  - Data Directory: `/prometheus/*` - Time series database files
- **Loki**: 
  - Data Directory: `/loki/*` - Log chunks and indexes
- **Mimir**: 
  - Data Directory: `/data/*` - Metrics data and indexes

## Backup Storage

Backups are stored on NFS storage at the configured backup path:
- **NFS Server**: 192.168.1.7
- **NFS Path**: /data/kubernetes/backups
- **Location**: `${var.nfs_backup_path}` on `${var.nfs_server_ip}`
- **Structure**:
  ```
  /backup/
  ├── etcd/
  │   └── YYYYMMDD_HHMMSS/
  └── data/
      └── YYYYMMDD_HHMMSS/
          ├── resources/
          │   ├── namespaces.yaml
          │   ├── monitoring/
          │   ├── netalertx/
          │   └── cluster/
          └── persistent-data/
              ├── netalertx/
              │   ├── app.db
              │   ├── app.conf
              │   ├── logs.tar.gz
              │   └── backup-info.txt
              ├── grafana/
              │   ├── grafana.db
              │   ├── grafana-data.tar.gz
              │   └── backup-info.txt
              ├── prometheus/
              │   ├── prometheus-snapshot.tar.gz
              │   ├── prometheus-data.tar.gz
              │   └── backup-info.txt
              ├── loki/
              │   ├── loki-data.tar.gz
              │   └── backup-info.txt
              └── mimir/
                  ├── mimir-data.tar.gz
                  └── backup-info.txt
  ```

## Monitoring Backup Status

### Prometheus Metrics

The backup system exposes metrics for monitoring:

```prometheus
# Last successful backup timestamp
k8s_data_backup_last_success_timestamp

# Backup size in bytes
k8s_data_backup_size_bytes

# Number of resource files backed up
k8s_data_backup_resources_count

# NetAlertX specific metrics
netalertx_backup_database_size_bytes
netalertx_backup_success

# Observability stack metrics
grafana_backup_database_size_bytes
grafana_backup_success
prometheus_backup_size_bytes
prometheus_backup_success
loki_backup_size_bytes
loki_backup_success
mimir_backup_size_bytes
mimir_backup_success
```

### Checking Backup Status

```bash
# Check backup jobs
kubectl get cronjobs -n backup

# Check recent backup job runs
kubectl get jobs -n backup

# View backup logs
kubectl logs -n backup -l app=data-backup

# Check backup storage
kubectl exec -n backup deployment/backup-metrics -- ls -la /host/backup/data
```

## Manual Backup Operations

### Available Manual Backup Scripts

1. **`scripts/trigger-manual-backup.sh`** - Main script for triggering manual backups
2. **`scripts/manual-backup-comprehensive.sh`** - Comprehensive backup script (runs inside cluster)
3. **`scripts/manual-backup.sh`** - Legacy manual backup script (basic functionality)

### Manual Backup Types

| Type | Description | What's Included |
|------|-------------|-----------------|
| `all` | Complete backup | ETCD, Kubernetes resources, all application data |
| `etcd` | ETCD only | Cluster state and PKI certificates |
| `resources` | Kubernetes resources | Deployments, services, configs, secrets, etc. |
| `apps` | Application data | NetAlertX, Grafana, Prometheus, Loki, Mimir data |
| `netalertx` | NetAlertX only | Database, configuration, logs |
| `grafana` | Grafana only | Database, dashboards, plugins |
| `prometheus` | Prometheus only | TSDB snapshots or data |
| `loki` | Loki only | Log data and indexes |
| `mimir` | Mimir only | Metrics data and indexes |

## Manual Backup Operations

### Trigger Manual Backup

#### Using the Manual Backup Trigger Script (Recommended)

```bash
# Full comprehensive backup (everything)
./scripts/trigger-manual-backup.sh

# Backup specific components
./scripts/trigger-manual-backup.sh apps                    # Only application data
./scripts/trigger-manual-backup.sh grafana                 # Only Grafana
./scripts/trigger-manual-backup.sh prometheus              # Only Prometheus
./scripts/trigger-manual-backup.sh resources               # Only Kubernetes resources

# Custom backup location
./scripts/trigger-manual-backup.sh all /custom/backup/path

# Get help
./scripts/trigger-manual-backup.sh help
```

#### Using Kubernetes Jobs Directly

```bash
# Create a manual data backup job
kubectl create job --from=cronjob/data-backup manual-backup-$(date +%s) -n backup

# Create a manual ETCD backup job
kubectl create job --from=cronjob/etcd-backup manual-etcd-backup-$(date +%s) -n backup
```

#### Manual Backup Script Features

The comprehensive manual backup script provides:
- **Selective Backup Types**: Choose what to backup (all, apps, individual services)
- **Custom Locations**: Specify where to store backups
- **Real-time Progress**: Live log following during backup
- **Comprehensive Coverage**: Same backup methods as scheduled system
- **Status Reporting**: Detailed backup summary and statistics
- **Error Handling**: Graceful handling of missing services or failures

### Check Backup Contents

```bash
# List available backups
kubectl exec -n backup deployment/backup-metrics -- ls -la /host/backup/data/

# Check specific backup contents
BACKUP_DATE="20241030_120000"
kubectl exec -n backup deployment/backup-metrics -- find /host/backup/data/$BACKUP_DATE -type f
```

## Restore Operations

### Application Data Restore

To restore application data from backups:

```bash
# Get backup pod
BACKUP_POD=$(kubectl get pods -n backup -l app=backup-metrics -o jsonpath='{.items[0].metadata.name}')

# List available backups
kubectl exec -n backup $BACKUP_POD -- ls -la /host/backup/data/

# Set backup date (replace with actual backup date)
BACKUP_DATE="20241030_120000"
BACKUP_PATH="/host/backup/data/$BACKUP_DATE"

# Restore NetAlertX data
kubectl exec -n backup $BACKUP_POD -- /scripts/restore-netalertx.sh $BACKUP_PATH

# Restore Grafana data
kubectl exec -n backup $BACKUP_POD -- /scripts/restore-grafana.sh $BACKUP_PATH

# Restore Prometheus data
kubectl exec -n backup $BACKUP_POD -- /scripts/restore-prometheus.sh $BACKUP_PATH

# Restore Loki data
kubectl exec -n backup $BACKUP_POD -- /scripts/restore-loki.sh $BACKUP_PATH

# Restore Mimir data
kubectl exec -n backup $BACKUP_POD -- /scripts/restore-mimir.sh $BACKUP_PATH
```

### Full Cluster Restore

For complete cluster restoration:

1. **Restore ETCD** (on control plane nodes):
   ```bash
   # Stop Kubernetes services
   sudo systemctl stop k3s
   
   # Restore ETCD snapshot
   sudo k3s server --cluster-reset --cluster-reset-restore-path=/backup/etcd/YYYYMMDD_HHMMSS/snapshot.db
   
   # Start Kubernetes services
   sudo systemctl start k3s
   ```

2. **Restore Application Data**:
   ```bash
   # Apply Kubernetes resources
   kubectl apply -f /backup/data/YYYYMMDD_HHMMSS/resources/
   
   # Restore application data
   BACKUP_PATH="/backup/data/YYYYMMDD_HHMMSS"
   /scripts/restore-netalertx.sh $BACKUP_PATH
   /scripts/restore-grafana.sh $BACKUP_PATH
   /scripts/restore-prometheus.sh $BACKUP_PATH
   /scripts/restore-loki.sh $BACKUP_PATH
   /scripts/restore-mimir.sh $BACKUP_PATH
   ```

## Backup Verification

### Automated Verification

The backup system includes automatic verification:
- File integrity checks
- Size validation
- Backup completion markers
- Prometheus metrics updates

### Manual Verification

```bash
# Check NetAlertX backup integrity
BACKUP_DATE="20241030_120000"
BACKUP_POD=$(kubectl get pods -n backup -l app=backup-metrics -o jsonpath='{.items[0].metadata.name}')

# Verify database backup
kubectl exec -n backup $BACKUP_POD -- file /host/backup/data/$BACKUP_DATE/persistent-data/netalertx/app.db

# Check backup info
kubectl exec -n backup $BACKUP_POD -- cat /host/backup/data/$BACKUP_DATE/persistent-data/netalertx/backup-info.txt

# Verify backup completeness
kubectl exec -n backup $BACKUP_POD -- test -f /host/backup/data/$BACKUP_DATE/backup-success && echo "Backup completed successfully"
```

## Troubleshooting

### Common Issues

1. **NetAlertX Pod Not Found**
   ```bash
   # Check NetAlertX deployment
   kubectl get pods -n netalertx
   kubectl describe deployment netalertx -n netalertx
   ```

2. **Backup Storage Issues**
   ```bash
   # Check NFS connectivity
   kubectl exec -n backup deployment/backup-metrics -- df -h /host/backup
   
   # Test NFS write access
   kubectl exec -n backup deployment/backup-metrics -- touch /host/backup/test-write
   ```

3. **Database Backup Failures**
   ```bash
   # Check NetAlertX database status
   NETALERTX_POD=$(kubectl get pods -n netalertx -l app=netalertx -o jsonpath='{.items[0].metadata.name}')
   kubectl exec -n netalertx $NETALERTX_POD -- ls -la /db/
   kubectl exec -n netalertx $NETALERTX_POD -- file /db/app.db
   ```

4. **Permission Issues**
   ```bash
   # Fix NetAlertX file permissions
   kubectl exec -n netalertx $NETALERTX_POD -- chown -R 1000:1000 /db /config
   kubectl exec -n netalertx $NETALERTX_POD -- chmod 755 /db /config
   
   # Fix Grafana file permissions
   GRAFANA_POD=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}')
   kubectl exec -n monitoring $GRAFANA_POD -- chown -R 472:472 /var/lib/grafana
   kubectl exec -n monitoring $GRAFANA_POD -- chmod 755 /var/lib/grafana
   
   # Fix Prometheus file permissions
   PROMETHEUS_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}')
   kubectl exec -n monitoring $PROMETHEUS_POD -- chown -R 65534:65534 /prometheus
   kubectl exec -n monitoring $PROMETHEUS_POD -- chmod 755 /prometheus
   ```

5. **Observability Stack Issues**
   ```bash
   # Check Grafana status
   kubectl get pods -n monitoring -l app=grafana
   kubectl logs -n monitoring -l app=grafana
   
   # Check Prometheus status
   kubectl get pods -n monitoring -l app=prometheus
   kubectl logs -n monitoring -l app=prometheus
   
   # Check Loki status
   kubectl get pods -n monitoring -l app=loki
   kubectl logs -n monitoring -l app=loki
   
   # Check Mimir status
   kubectl get pods -n monitoring -l app=mimir
   kubectl logs -n monitoring -l app=mimir
   ```

### Recovery Scenarios

1. **NetAlertX Database Corruption**
   - Stop NetAlertX deployment
   - Restore from latest backup
   - Restart NetAlertX deployment

2. **Configuration Loss**
   - Restore configuration from backup
   - Restart NetAlertX to apply changes

3. **Complete Data Loss**
   - Restore both database and configuration
   - Verify data integrity
   - Restart services

4. **Grafana Dashboard Loss**
   - Restore Grafana database and data directory
   - Restart Grafana deployment
   - Verify dashboards are accessible

5. **Prometheus Data Loss**
   - Restore from TSDB snapshot or data backup
   - Restart Prometheus deployment
   - Verify metrics collection is working

6. **Loki Log Data Loss**
   - Restore Loki data directory
   - Restart Loki deployment
   - Verify log ingestion is working

7. **Mimir Metrics Loss**
   - Restore Mimir data directory
   - Restart Mimir deployment
   - Verify metrics storage is working

## Backup Retention

The cleanup job automatically removes old backups based on the retention policy:
- **Default Retention**: 30 days (configurable via `backup_retention_days`)
- **Cleanup Schedule**: Weekly on Sundays at 4:00 AM
- **Protected Backups**: Most recent 3 successful backups are always kept

## Security Considerations

- Backup storage should be secured and access-controlled
- Database backups may contain sensitive network information
- Restore operations require cluster admin privileges
- NFS storage should be properly secured and encrypted if possible

## Monitoring and Alerting

Set up alerts for:
- Backup job failures
- Storage space issues
- NetAlertX backup failures
- Backup age exceeding thresholds

Example Prometheus alert rules:
```yaml
- alert: BackupJobFailed
  expr: kube_job_status_failed{job_name=~".*backup.*"} > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Backup job {{ $labels.job_name }} failed"

- alert: NetAlertXBackupFailed
  expr: netalertx_backup_success == 0
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "NetAlertX backup failed"

- alert: GrafanaBackupFailed
  expr: grafana_backup_success == 0
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Grafana backup failed"

- alert: PrometheusBackupFailed
  expr: prometheus_backup_success == 0
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Prometheus backup failed"

- alert: LokiBackupFailed
  expr: loki_backup_success == 0
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Loki backup failed"

- alert: MimirBackupFailed
  expr: mimir_backup_success == 0
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Mimir backup failed"
```