#!/bin/sh

set -e

echo "🔄 Starting ETCD backup process..."

# Configuration
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/etcd/${BACKUP_DATE}"
ETCD_ENDPOINTS="https://127.0.0.1:2379"
ETCD_CACERT="/etc/kubernetes/pki/etcd/ca.crt"
ETCD_CERT="/etc/kubernetes/pki/etcd/server.crt"
ETCD_KEY="/etc/kubernetes/pki/etcd/server.key"

# Create backup directory
mkdir -p "${BACKUP_PATH}"
chmod 755 "${BACKUP_PATH}"

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

# Set permissions on snapshot
chmod 755 "${BACKUP_PATH}/etcd-snapshot.db"

# Verify snapshot
echo "✅ Verifying snapshot..."
etcdctl --write-out=table snapshot status "${BACKUP_PATH}/etcd-snapshot.db"

# Backup certificates
echo "🔐 Backing up certificates..."
cp -r /etc/kubernetes/pki "${BACKUP_PATH}/"
chmod -R 755 "${BACKUP_PATH}/pki"

# Create backup metadata
echo "📋 Creating backup metadata..."
cat > "${BACKUP_PATH}/backup-info.txt" << EOF
Backup Date: $(date)
Node Name: ${NODE_NAME}
ETCD Version: $(etcdctl version)
Backup Type: ETCD Snapshot
Backup Size: $(du -sh "${BACKUP_PATH}/etcd-snapshot.db" | cut -f1)
EOF

chmod 755 "${BACKUP_PATH}/backup-info.txt"

# Create success marker
touch "${BACKUP_PATH}/backup-success"
chmod 755 "${BACKUP_PATH}/backup-success"

# Set permissions on backup directory
chmod -R 755 "${BACKUP_PATH}"

echo "✅ ETCD backup completed at ${BACKUP_PATH}"

# Clean up old backups (keep last 7 days)
echo "🧹 Cleaning up old backups..."
find "${BACKUP_DIR}/etcd" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

echo "✅ ETCD backup process completed successfully!"

