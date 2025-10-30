# Backup Monitoring Dashboard Guide

This guide explains the comprehensive Grafana dashboard for monitoring the Kubernetes backup system, including all scheduled backups for NetAlertX, Grafana, Prometheus, Loki, and Mimir.

## Dashboard Overview

The **Kubernetes Backup Monitoring** dashboard provides real-time visibility into:
- Backup success/failure status
- Backup file counts and trends
- Backup duration tracking
- Storage usage monitoring
- Failed backup identification

## Dashboard Panels

### 1. Backup Status Overview
**Type**: Stat Panel  
**Metrics**: `k8s_data_backup_last_success_timestamp`  
**Purpose**: Shows when the last successful backup occurred  
**Thresholds**:
- Green: Recent backup (< 24 hours)
- Yellow: Backup aging (24-48 hours)
- Red: Backup overdue (> 48 hours)

### 2. Total Backup Size
**Type**: Stat Panel  
**Metrics**: `k8s_data_backup_size_bytes`  
**Purpose**: Displays the total size of the most recent backup  
**Thresholds**:
- Green: Normal size (< 1GB)
- Yellow: Large backup (1-5GB)
- Red: Very large backup (> 5GB)

### 3. Resource Files Count
**Type**: Stat Panel  
**Metrics**: `k8s_data_backup_resources_count`  
**Purpose**: Shows the number of Kubernetes resource files backed up

### 4. Application Backup Success Status
**Type**: Stat Panel  
**Metrics**: 
- `netalertx_backup_success`
- `grafana_backup_success`
- `prometheus_backup_success`
- `loki_backup_success`
- `mimir_backup_success`

**Purpose**: Visual status indicators for each application backup  
**Display**: 
- Green "Success" for successful backups (value = 1)
- Red "Failed" for failed backups (value = 0)

### 5. Application Backup Sizes
**Type**: Stat Panel  
**Metrics**:
- `netalertx_backup_database_size_bytes`
- `grafana_backup_database_size_bytes`
- `prometheus_backup_size_bytes`
- `loki_backup_size_bytes`
- `mimir_backup_size_bytes`

**Purpose**: Shows individual backup sizes for each application

### 6. Backup Job Success Rate (24h)
**Type**: Time Series  
**Metrics**: 
- `increase(kube_job_status_succeeded{job_name=~".*backup.*"}[1h])`
- `increase(kube_job_status_failed{job_name=~".*backup.*"}[1h])`

**Purpose**: Tracks successful vs failed backup jobs over time

### 7. Backup Job Duration
**Type**: Time Series  
**Metrics**: `kube_job_status_completion_time - kube_job_status_start_time`  
**Purpose**: Shows how long each backup job takes to complete  
**Unit**: Seconds

### 8. Backup File Count Trend
**Type**: Time Series  
**Metrics**: 
- `backup_files_total` - Total backup files by type
- `backup_directories_total` - Total backup directories by type

**Purpose**: Tracks the growth of backup files over time

### 9. Backup Storage Usage Trend
**Type**: Time Series  
**Metrics**: 
- `backup_storage_bytes` - Storage used by backups
- `node_filesystem_avail_bytes{mountpoint="/host/backup"}` - Available storage

**Purpose**: Monitors backup storage consumption and available space

### 10. Failed Backup Jobs (Last 7 Days)
**Type**: Table  
**Metrics**: `kube_job_status_failed{job_name=~".*backup.*"} > 0`  
**Purpose**: Lists any backup jobs that have failed recently

### 11. Backup Schedule Status
**Type**: Table  
**Metrics**: `kube_cronjob_next_schedule_time{cronjob=~".*backup.*"}`  
**Purpose**: Shows when the next backup jobs are scheduled to run

### 12. Backup Duration Trend
**Type**: Time Series  
**Metrics**: `k8s_data_backup_duration_seconds`  
**Purpose**: Tracks how backup duration changes over time  
**Unit**: Seconds

### 13. Application Backup File Counts
**Type**: Stat Panel  
**Metrics**: `backup_application_files`  
**Purpose**: Shows the count of backup files for each application

## Available Metrics

### Core Backup Metrics
- `k8s_data_backup_last_success_timestamp` - Last successful backup timestamp
- `k8s_data_backup_size_bytes` - Total backup size in bytes
- `k8s_data_backup_resources_count` - Number of Kubernetes resources backed up
- `k8s_data_backup_duration_seconds` - Backup duration in seconds

### Application-Specific Metrics
- `netalertx_backup_success` - NetAlertX backup success (1/0)
- `netalertx_backup_database_size_bytes` - NetAlertX database backup size
- `grafana_backup_success` - Grafana backup success (1/0)
- `grafana_backup_database_size_bytes` - Grafana database backup size
- `prometheus_backup_success` - Prometheus backup success (1/0)
- `prometheus_backup_size_bytes` - Prometheus backup size
- `loki_backup_success` - Loki backup success (1/0)
- `loki_backup_size_bytes` - Loki backup size
- `mimir_backup_success` - Mimir backup success (1/0)
- `mimir_backup_size_bytes` - Mimir backup size

### File System Metrics
- `backup_directories_total{type}` - Number of backup directories by type
- `backup_files_total{type}` - Number of backup files by type
- `backup_storage_bytes{type}` - Storage usage by backup type
- `backup_application_files{application}` - File count per application

### Kubernetes Job Metrics
- `kube_job_status_succeeded` - Successful job count
- `kube_job_status_failed` - Failed job count
- `kube_job_status_start_time` - Job start timestamp
- `kube_job_status_completion_time` - Job completion timestamp
- `kube_cronjob_next_schedule_time` - Next scheduled job time

## Backup Schedule

| Job Type | Schedule | Description |
|----------|----------|-------------|
| ETCD Backup | Daily at 2:00 AM | Kubernetes cluster state backup |
| Data Backup | Daily at 3:00 AM | Application data and resources backup |
| File Metrics | Every 5 minutes | Backup file count and size metrics |
| Cleanup | Weekly on Sunday at 4:00 AM | Old backup cleanup |

## Monitoring and Alerting

### Key Metrics to Monitor
1. **Backup Success Rate**: Should be 100% for critical applications
2. **Backup Duration**: Watch for increasing trends that might indicate issues
3. **Storage Usage**: Ensure adequate space for future backups
4. **File Counts**: Monitor growth patterns for capacity planning

### Recommended Alerts
```yaml
# Backup failure alert
- alert: BackupJobFailed
  expr: kube_job_status_failed{job_name=~".*backup.*"} > 0
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Backup job {{ $labels.job_name }} failed"

# Backup duration alert
- alert: BackupDurationHigh
  expr: k8s_data_backup_duration_seconds > 3600
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Backup taking longer than 1 hour"

# Storage space alert
- alert: BackupStorageLow
  expr: node_filesystem_avail_bytes{mountpoint="/host/backup"} / node_filesystem_size_bytes{mountpoint="/host/backup"} < 0.1
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "Backup storage less than 10% available"

# Application backup failure alerts
- alert: ApplicationBackupFailed
  expr: |
    netalertx_backup_success == 0 or
    grafana_backup_success == 0 or
    prometheus_backup_success == 0 or
    loki_backup_success == 0 or
    mimir_backup_success == 0
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Application backup failed"
```

## Troubleshooting

### Common Issues

1. **Missing Metrics**
   - Check if backup jobs are running: `kubectl get cronjobs -n backup`
   - Verify backup metrics pod: `kubectl get pods -n backup -l app=backup-metrics`
   - Check Prometheus scraping: Look for backup-metrics service in Prometheus targets

2. **Backup Failures**
   - Check job logs: `kubectl logs -n backup -l app=data-backup`
   - Verify storage access: `kubectl exec -n backup <pod> -- ls -la /backup`
   - Check application pod status: `kubectl get pods -n monitoring`

3. **Storage Issues**
   - Monitor available space: Check "Backup Storage Usage Trend" panel
   - Verify NFS connectivity: `kubectl exec -n backup <pod> -- df -h /backup`
   - Check cleanup job: `kubectl get cronjobs backup-cleanup -n backup`

4. **Duration Issues**
   - Large backup sizes may increase duration
   - Network issues can slow down backup transfers
   - Check resource limits on backup jobs

### Dashboard Refresh
- **Default Refresh**: 5 minutes
- **Time Range**: Last 24 hours
- **Manual Refresh**: Click refresh button in Grafana

## Access Information

- **Dashboard URL**: `http://grafana.local/d/backup-monitoring`
- **Prometheus Metrics**: Available at `http://backup-metrics.backup:8080/metrics`
- **Backup Storage**: NFS mount at configured backup path
- **Logs**: Available via `kubectl logs` for backup jobs

This dashboard provides comprehensive visibility into your backup operations, helping ensure data protection and system reliability.