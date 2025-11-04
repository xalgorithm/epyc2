# Kubernetes Cluster Backup System

This document describes the comprehensive backup system implemented for the Kubernetes homelab cluster.

## 🎯 Overview

The backup system provides automated, scheduled backups of:
- **ETCD cluster state** (daily snapshots)
- **Kubernetes resources** (deployments, services, configmaps, etc.)
- **Application data** (Grafana dashboards, configurations)
- **Certificates and cluster configuration**

## 🏗️ Architecture

### Backup Components

1. **ETCD Backup CronJob**: Daily snapshots of the ETCD database
2. **Data Backup CronJob**: Daily backup of Kubernetes resources and application data
3. **Cleanup CronJob**: Weekly cleanup of old backups based on retention policy
4. **Backup Monitoring**: Metrics and dashboards for backup status

### Storage

- **Local Storage**: `/tmp/k8s-backup` for manual backups
- **NFS Storage**: `<nfs-server-ip>:<nfs-path>` for automated backups (configured in terraform.tfvars)
- **Retention**: 30 days (configurable)

## 📅 Backup Schedule

| Backup Type | Schedule | Description |
|-------------|----------|-------------|
| ETCD | Daily 2:00 AM | Cluster state snapshot |
| Data | Daily 3:00 AM | Resources and application data |
| Cleanup | Weekly Sunday 4:00 AM | Remove old backups |

## 🚀 Quick Start

### Deploy Backup System

The backup system is automatically deployed with the main Terraform configuration:

```bash
terraform apply
```

### Manual Backup

Run an immediate backup of all components:

```bash
# Comprehensive backup (recommended)
./scripts/backup/manual-backup-comprehensive.sh

# Or trigger backup via Kubernetes
./scripts/backup/trigger-manual-backup.sh
```

Available backup components:
- ETCD snapshots
- Kubernetes resources
- Application data (Prometheus, Grafana, Loki, Mimir)

### Test Backup Restoration

Test backup restoration without affecting production:

```bash
# Dry run (no actual restoration)
./scripts/backup/test-backup-restoration.sh dry-run

# Test individual component restoration
./scripts/backup/test-individual-restore.sh <component>
```

Available components: `grafana`, `prometheus`, `loki`, `mimir`

## 📊 Monitoring

### Grafana Dashboard

Access the backup monitoring dashboard in Grafana:
- Dashboard: "Kubernetes Backup Monitoring"
- Metrics: Backup success, size, duration, counts

### Key Metrics

- `etcd_backup_last_success_timestamp` - Last successful ETCD backup
- `k8s_data_backup_last_success_timestamp` - Last successful data backup
- `backup_total_size_bytes` - Total backup storage usage
- `backup_etcd_count` - Number of ETCD backups
- `backup_data_count` - Number of data backups

## 🔧 Configuration

### Variables (terraform.tfvars)

```hcl
# Backup Configuration
backup_retention_days = 30
nfs_server_ip        = "192.168.1.100"  # Your NFS server IP
nfs_backup_path      = "/data/kubernetes/backups"  # Your NFS export path
```

### Backup Scripts Location

All backup scripts are stored in ConfigMaps and mounted to backup pods:
- `scripts/etcd-backup.sh` - ETCD snapshot creation
- `scripts/data-backup.sh` - Resource and data backup
- `scripts/restore-etcd.sh` - ETCD restore procedure
- `scripts/backup-cleanup.sh` - Cleanup old backups

## 🔄 Restore Procedures

### ETCD Restore

⚠️ **WARNING**: This will restore the entire cluster state and restart all services.

1. **Stop the cluster** (on control plane):
   ```bash
   sudo systemctl stop kubelet
   sudo systemctl stop containerd
   ```

2. **Run restore script**:
   ```bash
   # On control plane node
   sudo /scripts/restore-etcd.sh /backup/etcd/20231025_020000
   ```

3. **Verify cluster**:
   ```bash
   kubectl get nodes
   kubectl get pods --all-namespaces
   ```

### Resource Restore

Restore specific Kubernetes resources:

```bash
# Restore all resources
kubectl apply -f /backup/data/20231025_030000/resources/

# Restore specific namespace
kubectl apply -f /backup/data/20231025_030000/resources/monitoring/
```

### Application Data Restore

```bash
# Restore Grafana dashboards
kubectl exec -n monitoring deployment/grafana -- tar xzf - -C / < /backup/data/20231025_030000/app-data/grafana-dashboards.tar.gz
```

## 📁 Backup Structure

```
/backup/
├── etcd/
│   └── 20231025_020000/
│       ├── etcd-snapshot.db
│       ├── pki/
│       ├── backup-info.txt
│       └── backup-success
└── data/
    └── 20231025_030000/
        ├── resources/
        │   ├── monitoring/
        │   ├── media/
        │   └── cluster/
        ├── app-data/
        ├── backup-summary.txt
        └── backup-success
```

## 🛠️ Troubleshooting

### Common Issues

1. **Backup Job Fails**
   ```bash
   kubectl logs -n backup job/etcd-backup-xxxxx
   kubectl describe cronjob -n backup etcd-backup
   ```

2. **NFS Mount Issues**
   ```bash
   kubectl get pods -n backup
   kubectl describe pod -n backup <backup-pod>
   ```

3. **ETCD Snapshot Validation**
   ```bash
   etcdctl snapshot status /backup/etcd/20231025_020000/etcd-snapshot.db --write-out=table
   ```

### Manual Cleanup

Remove old backups manually:

```bash
# Remove backups older than 30 days
find /backup -type d -name "20*" -mtime +30 -exec rm -rf {} \;
```

## 🔒 Security Considerations

1. **Access Control**: Backup jobs run with dedicated service accounts
2. **Network Security**: NFS access restricted to cluster nodes
3. **Data Encryption**: Consider encrypting backup storage
4. **Secrets**: Kubernetes secrets are backed up (excluding service account tokens)

## 📈 Best Practices

1. **Regular Testing**: Test restore procedures monthly
2. **Monitoring**: Set up alerts for backup failures
3. **Storage Management**: Monitor backup storage usage
4. **Documentation**: Keep restore procedures updated
5. **Validation**: Regularly validate backup integrity

## 🚨 Disaster Recovery

### Complete Cluster Recovery

1. **Prepare new cluster nodes**
2. **Restore ETCD from latest snapshot**
3. **Apply Kubernetes resources**
4. **Restore application data**
5. **Verify all services**

### Recovery Time Objectives

- **RTO (Recovery Time Objective)**: 2-4 hours
- **RPO (Recovery Point Objective)**: 24 hours (daily backups)

## 📞 Support Commands

```bash
# Check backup status
kubectl get cronjobs -n backup
kubectl get jobs -n backup --sort-by=.metadata.creationTimestamp

# View backup logs
kubectl logs -n backup -l app=etcd-backup --tail=100
kubectl logs -n backup -l app=data-backup --tail=100

# Manual backup execution
kubectl create job --from=cronjob/etcd-backup manual-etcd-backup -n backup
kubectl create job --from=cronjob/data-backup manual-data-backup -n backup

# Backup metrics
kubectl port-forward -n backup svc/backup-metrics 8080:8080
curl http://localhost:8080/metrics | grep backup
```

## 📚 Additional Resources

- [ETCD Backup and Restore](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#backing-up-an-etcd-cluster)
- [Kubernetes Backup Strategies](https://kubernetes.io/docs/concepts/cluster-administration/backup/)
- [Disaster Recovery Best Practices](https://kubernetes.io/docs/setup/best-practices/cluster-large/)

---

For questions or issues, check the troubleshooting section or review the backup monitoring dashboard in Grafana.