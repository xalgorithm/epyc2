#!/bin/sh

set -e

echo "🔄 Starting ETCD backup process..."

# Configuration
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_DATE}"
ETCD_ENDPOINTS="https://127.0.0.1:2379"
ETCD_CACERT="/etc/kubernetes/pki/etcd/ca.crt"
ETCD_CERT="/etc/kubernetes/pki/etcd/server.crt"
ETCD_KEY="/etc/kubernetes/pki/etcd/server.key"

# Create backup directory
mkdir -p "${BACKUP_PATH}"

echo "📁 Backup directory: ${BACKUP_PATH}"
echo "🎯 Node: ${NODE_NAME}"

# Check ETCD health
echo "🔍 Checking ETCD health..."
etcdctl --endpoints=${ETCD_ENDPOINTS} \
        --cacert=${ETCD_CACERT} \
        --cert=${ETCD_CERT} \
        --key=${ETCD_KEY} \
        endpoint health

# Create ETCD snapshot
echo "📸 Creating ETCD snapshot..."
etcdctl --endpoints=${ETCD_ENDPOINTS} \
        --cacert=${ETCD_CACERT} \
        --cert=${ETCD_CERT} \
        --key=${ETCD_KEY} \
        snapshot save "${BACKUP_PATH}/etcd-snapshot.db"

# Verify snapshot
echo "✅ Verifying snapshot..."
etcdctl --write-out=table snapshot status "${BACKUP_PATH}/etcd-snapshot.db"

# Backup certificates
echo "🔐 Backing up certificates..."
cp -r /etc/kubernetes/pki "${BACKUP_PATH}/"

# Create backup metadata
echo "📋 Creating backup metadata..."
cat > "${BACKUP_PATH}/backup-info.txt" << EOF
Backup Date: $(date)
Node Name: ${NODE_NAME}
ETCD Version: $(etcdctl version)
Kubernetes Version: $(kubectl version --short --client 2>/dev/null || echo "N/A")
Backup Type: ETCD Snapshot
Backup Size: $(du -sh "${BACKUP_PATH}/etcd-snapshot.db" | cut -f1)
EOF

# Create success marker
touch "${BACKUP_PATH}/backup-success"

# Update metrics
echo "📊 Updating backup metrics..."
cat > /tmp/backup_metrics.prom << EOF
# HELP etcd_backup_last_success_timestamp Last successful ETCD backup timestamp
# TYPE etcd_backup_last_success_timestamp gauge
etcd_backup_last_success_timestamp $(date +%s)

# HELP etcd_backup_size_bytes Size of the last ETCD backup in bytes
# TYPE etcd_backup_size_bytes gauge
etcd_backup_size_bytes $(stat -c%s "${BACKUP_PATH}/etcd-snapshot.db")

# HELP etcd_backup_duration_seconds Duration of the last ETCD backup
# TYPE etcd_backup_duration_seconds gauge
etcd_backup_duration_seconds $(($(date +%s) - $(date -d "${BACKUP_DATE}" +%s)))
EOF

echo "✅ ETCD backup completed successfully!"
echo "📍 Backup location: ${BACKUP_PATH}"
echo "📊 Backup size: $(du -sh "${BACKUP_PATH}" | cut -f1)"

# List recent backups
echo "📚 Recent backups:"
ls -la "${BACKUP_DIR}" | tail -5