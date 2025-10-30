#!/bin/sh

set -e

echo "🔄 Starting ETCD restore process..."

# Check if backup path is provided
if [ -z "$1" ]; then
    echo "❌ Error: Backup path not provided"
    echo "Usage: $0 <backup-path>"
    echo "Example: $0 /backup/etcd/20231025_020000"
    exit 1
fi

BACKUP_PATH="$1"
SNAPSHOT_FILE="${BACKUP_PATH}/etcd-snapshot.db"

# Verify backup exists
if [ ! -f "${SNAPSHOT_FILE}" ]; then
    echo "❌ Error: Snapshot file not found: ${SNAPSHOT_FILE}"
    exit 1
fi

echo "📁 Restore from: ${BACKUP_PATH}"
echo "📸 Snapshot file: ${SNAPSHOT_FILE}"

# Configuration
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_ENDPOINTS="https://127.0.0.1:2379"
ETCD_CACERT="/etc/kubernetes/pki/etcd/ca.crt"
ETCD_CERT="/etc/kubernetes/pki/etcd/server.crt"
ETCD_KEY="/etc/kubernetes/pki/etcd/server.key"

echo "⚠️  WARNING: This will restore ETCD from backup and restart the cluster!"
echo "⚠️  All current cluster state will be lost!"
echo "⚠️  Make sure to stop all Kubernetes services before proceeding!"
echo ""
echo "Backup info:"
cat "${BACKUP_PATH}/backup-info.txt" 2>/dev/null || echo "No backup info available"
echo ""

read -p "Are you sure you want to proceed? (yes/no): " -r
if [ "$REPLY" != "yes" ]; then
    echo "❌ Restore cancelled"
    exit 0
fi

# Stop kubelet and containerd
echo "🛑 Stopping Kubernetes services..."
systemctl stop kubelet
systemctl stop containerd

# Backup current etcd data
echo "💾 Backing up current ETCD data..."
if [ -d "${ETCD_DATA_DIR}" ]; then
    mv "${ETCD_DATA_DIR}" "${ETCD_DATA_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Restore ETCD snapshot
echo "🔄 Restoring ETCD snapshot..."
etcdctl snapshot restore "${SNAPSHOT_FILE}" \
    --data-dir="${ETCD_DATA_DIR}" \
    --name="$(hostname)" \
    --initial-cluster="$(hostname)=https://$(hostname -I | awk '{print $1}'):2380" \
    --initial-cluster-token="etcd-cluster-1" \
    --initial-advertise-peer-urls="https://$(hostname -I | awk '{print $1}'):2380"

# Set proper ownership
chown -R etcd:etcd "${ETCD_DATA_DIR}"

# Restore certificates if they exist in backup
if [ -d "${BACKUP_PATH}/pki" ]; then
    echo "🔐 Restoring certificates..."
    cp -r "${BACKUP_PATH}/pki" /etc/kubernetes/
    chown -R root:root /etc/kubernetes/pki
fi

# Start services
echo "🚀 Starting Kubernetes services..."
systemctl start containerd
systemctl start kubelet

# Wait for services to start
echo "⏳ Waiting for services to start..."
sleep 30

# Check cluster health
echo "🔍 Checking cluster health..."
kubectl get nodes 2>/dev/null || echo "⚠️  Cluster may need more time to start"

echo "✅ ETCD restore completed!"
echo "📍 Restored from: ${BACKUP_PATH}"
echo "⚠️  Please verify cluster state and functionality"
echo ""
echo "Next steps:"
echo "1. Check node status: kubectl get nodes"
echo "2. Check pod status: kubectl get pods --all-namespaces"
echo "3. Verify services: kubectl get svc --all-namespaces"
echo "4. Check logs if issues: journalctl -u kubelet -f"