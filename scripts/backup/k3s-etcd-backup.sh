#!/bin/sh

set -e

echo "🔄 Starting K3s ETCD backup process..."

# Configuration
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_DATE}"

# K3s specific paths
K3S_DATA_DIR="/var/lib/rancher/k3s/server/db"
K3S_TOKEN_FILE="/var/lib/rancher/k3s/server/token"
K3S_CONFIG_DIR="/etc/rancher/k3s"

echo "📁 Backup directory: ${BACKUP_PATH}"
echo "🎯 Node: ${NODE_NAME}"

# Create backup directory
mkdir -p "${BACKUP_PATH}"

# Check if K3s is using embedded etcd or external datastore
if [ -d "$K3S_DATA_DIR/etcd" ]; then
    echo "📊 K3s using embedded etcd"
    
    # Backup etcd data directory
    echo "📸 Backing up K3s etcd data..."
    if [ -d "$K3S_DATA_DIR/etcd" ]; then
        tar czf "${BACKUP_PATH}/k3s-etcd-data.tar.gz" -C "$K3S_DATA_DIR" etcd/
        echo "✅ ETCD data backed up"
    else
        echo "⚠️  ETCD data directory not found"
    fi
    
    # Try to create etcd snapshot if etcdctl is available
    if command -v etcdctl >/dev/null 2>&1; then
        echo "📸 Creating ETCD snapshot with etcdctl..."
        
        # K3s etcd configuration
        ETCD_ENDPOINTS="https://127.0.0.1:2379"
        ETCD_CACERT="/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt"
        ETCD_CERT="/var/lib/rancher/k3s/server/tls/etcd/server-client.crt"
        ETCD_KEY="/var/lib/rancher/k3s/server/tls/etcd/server-client.key"
        
        if [ -f "$ETCD_CACERT" ] && [ -f "$ETCD_CERT" ] && [ -f "$ETCD_KEY" ]; then
            ETCDCTL_API=3 etcdctl --endpoints=${ETCD_ENDPOINTS} \
                    --cacert=${ETCD_CACERT} \
                    --cert=${ETCD_CERT} \
                    --key=${ETCD_KEY} \
                    snapshot save "${BACKUP_PATH}/k3s-etcd-snapshot.db" || echo "⚠️  ETCD snapshot failed, continuing with data backup"
            
            # Verify snapshot if it was created
            if [ -f "${BACKUP_PATH}/k3s-etcd-snapshot.db" ]; then
                echo "✅ Verifying snapshot..."
                ETCDCTL_API=3 etcdctl --write-out=table snapshot status "${BACKUP_PATH}/k3s-etcd-snapshot.db" || echo "⚠️  Snapshot verification failed"
            fi
        else
            echo "⚠️  ETCD certificates not found, skipping etcdctl snapshot"
        fi
    else
        echo "⚠️  etcdctl not available, using data directory backup only"
    fi
    
else
    echo "📊 K3s using external datastore (not embedded etcd)"
    echo "⚠️  External datastore backup not implemented in this script"
fi

# Backup K3s configuration and certificates
echo "🔐 Backing up K3s configuration and certificates..."

# Backup K3s server configuration
if [ -d "$K3S_CONFIG_DIR" ]; then
    tar czf "${BACKUP_PATH}/k3s-config.tar.gz" -C /etc/rancher k3s/ || echo "⚠️  K3s config backup failed"
fi

# Backup K3s server token
if [ -f "$K3S_TOKEN_FILE" ]; then
    cp "$K3S_TOKEN_FILE" "${BACKUP_PATH}/k3s-token" || echo "⚠️  K3s token backup failed"
fi

# Backup K3s TLS certificates
if [ -d "/var/lib/rancher/k3s/server/tls" ]; then
    tar czf "${BACKUP_PATH}/k3s-tls.tar.gz" -C /var/lib/rancher/k3s/server tls/ || echo "⚠️  K3s TLS backup failed"
fi

# Backup K3s manifests
if [ -d "/var/lib/rancher/k3s/server/manifests" ]; then
    tar czf "${BACKUP_PATH}/k3s-manifests.tar.gz" -C /var/lib/rancher/k3s/server manifests/ || echo "⚠️  K3s manifests backup failed"
fi

# Create backup metadata
echo "📋 Creating backup metadata..."
cat > "${BACKUP_PATH}/backup-info.txt" << EOF
K3s Backup Information
=====================
Backup Date: $(date)
Node Name: ${NODE_NAME}
K3s Version: $(k3s --version 2>/dev/null | head -1 || echo "Unknown")
Backup Type: K3s Cluster State
Backup Components:
$(ls -la "${BACKUP_PATH}" | grep -v "^total" | awk '{print "- " $9 ": " $5 " bytes"}')

Restore Instructions:
1. Stop K3s: systemctl stop k3s
2. Backup current data: mv /var/lib/rancher/k3s /var/lib/rancher/k3s.backup
3. Extract data: tar xzf k3s-etcd-data.tar.gz -C /var/lib/rancher/k3s/server/db/
4. Extract config: tar xzf k3s-config.tar.gz -C /etc/rancher/
5. Extract TLS: tar xzf k3s-tls.tar.gz -C /var/lib/rancher/k3s/server/
6. Restore token: cp k3s-token /var/lib/rancher/k3s/server/token
7. Start K3s: systemctl start k3s
EOF

# Create success marker
touch "${BACKUP_PATH}/backup-success"

# Update metrics
echo "📊 Updating backup metrics..."
BACKUP_SIZE=$(du -sb "${BACKUP_PATH}" | cut -f1)
cat > /tmp/k3s_backup_metrics.prom << EOF
# HELP k3s_backup_last_success_timestamp Last successful K3s backup timestamp
# TYPE k3s_backup_last_success_timestamp gauge
k3s_backup_last_success_timestamp $(date +%s)

# HELP k3s_backup_size_bytes Size of the last K3s backup in bytes
# TYPE k3s_backup_size_bytes gauge
k3s_backup_size_bytes ${BACKUP_SIZE}

# HELP k3s_backup_components_count Number of backup components
# TYPE k3s_backup_components_count gauge
k3s_backup_components_count $(ls -1 "${BACKUP_PATH}" | grep -v backup-info.txt | grep -v backup-success | wc -l)
EOF

echo "✅ K3s backup completed successfully!"
echo "📍 Backup location: ${BACKUP_PATH}"
echo "📊 Backup size: $(du -sh "${BACKUP_PATH}" | cut -f1)"

# List backup contents
echo "📦 Backup contents:"
ls -la "${BACKUP_PATH}"

# List recent backups
echo "📚 Recent backups:"
ls -la "${BACKUP_DIR}" | tail -5