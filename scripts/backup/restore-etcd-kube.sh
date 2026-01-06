#!/bin/sh

set -e

echo "🔄 ETCD Restore Script (Kubernetes Cluster)"
echo "==========================================="
echo ""

# Configuration
BACKUP_BASE_DIR="/backup/etcd"
ETCD_DATA_DIR="/var/lib/etcd"

# Check if backup directory exists
if [ ! -d "${BACKUP_BASE_DIR}" ]; then
    echo "❌ Error: Backup directory not found: ${BACKUP_BASE_DIR}"
    exit 1
fi

# List available backups
echo "📁 Available ETCD backups:"
echo ""
BACKUPS=$(find "${BACKUP_BASE_DIR}" -maxdepth 1 -type d -name "202*" | sort -r)

if [ -z "$BACKUPS" ]; then
    echo "❌ No backups found in ${BACKUP_BASE_DIR}"
    exit 1
fi

# Display backups with numbers
i=1
for backup_dir in $BACKUPS; do
    backup_name=$(basename "$backup_dir")
    backup_file="${backup_dir}/etcd-snapshot.db"
    
    if [ -f "$backup_file" ]; then
        backup_size=$(du -sh "$backup_file" | cut -f1)
        if [ -f "${backup_dir}/backup-info.txt" ]; then
            backup_date=$(grep "Backup Date:" "${backup_dir}/backup-info.txt" | cut -d: -f2- | xargs)
            node_name=$(grep "Node Name:" "${backup_dir}/backup-info.txt" | cut -d: -f2- | xargs)
        else
            backup_date="Unknown"
            node_name="Unknown"
        fi
        
        echo "  [$i] ${backup_name}"
        echo "      Size: ${backup_size}"
        echo "      Date: ${backup_date}"
        echo "      Node: ${node_name}"
        
        if [ -f "${backup_dir}/backup-success" ]; then
            echo "      Status: ✅ Complete"
        else
            echo "      Status: ⚠️  Incomplete"
        fi
        echo ""
    fi
    i=$((i + 1))
done

# Prompt for selection
echo "Enter the number of the backup to restore (or 'q' to quit):"
if [ -t 0 ]; then
    read -r selection
else
    echo "❌ Error: This script requires interactive input"
    exit 1
fi

if [ "$selection" = "q" ] || [ "$selection" = "Q" ]; then
    echo "❌ Restore cancelled"
    exit 0
fi

# Validate selection
if ! echo "$selection" | grep -qE '^[0-9]+$'; then
    echo "❌ Error: Invalid selection"
    exit 1
fi

# Get the selected backup
selected_backup=$(echo "$BACKUPS" | sed -n "${selection}p")

if [ -z "$selected_backup" ]; then
    echo "❌ Error: Invalid backup number"
    exit 1
fi

SNAPSHOT_FILE="${selected_backup}/etcd-snapshot.db"
BACKUP_NAME=$(basename "$selected_backup")

if [ ! -f "$SNAPSHOT_FILE" ]; then
    echo "❌ Error: Snapshot file not found: ${SNAPSHOT_FILE}"
    exit 1
fi

echo ""
echo "⚠️  WARNING: This will restore ETCD from backup: ${BACKUP_NAME}"
echo "⚠️  ALL CURRENT CLUSTER STATE WILL BE LOST!"
echo "⚠️  This should only be done in case of disaster recovery!"
echo ""
echo "Backup information:"
cat "${selected_backup}/backup-info.txt" 2>/dev/null || echo "No backup info available"
echo ""
echo "⚠️  CRITICAL: Make sure all Kubernetes services are stopped before proceeding!"
echo "⚠️  You must run: systemctl stop kubelet && systemctl stop containerd"
echo ""
echo "Type 'RESTORE' in all caps to proceed, or anything else to cancel:"
read -r confirm

if [ "$confirm" != "RESTORE" ]; then
    echo "❌ Restore cancelled"
    exit 0
fi

# Verify snapshot
echo "🔍 Verifying snapshot..."
etcdctl snapshot status "${SNAPSHOT_FILE}" --write-out=table

if [ $? -ne 0 ]; then
    echo "❌ Error: Invalid or corrupted snapshot"
    exit 1
fi

# Check if Kubernetes services are running
if systemctl is-active --quiet kubelet; then
    echo "❌ Error: kubelet is still running!"
    echo "   Please stop Kubernetes services first:"
    echo "   systemctl stop kubelet"
    echo "   systemctl stop containerd"
    exit 1
fi

# Backup current etcd data
echo "💾 Backing up current ETCD data..."
if [ -d "${ETCD_DATA_DIR}" ]; then
    CURRENT_BACKUP="${ETCD_DATA_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    mv "${ETCD_DATA_DIR}" "${CURRENT_BACKUP}"
    echo "✅ Current ETCD data backed up to: ${CURRENT_BACKUP}"
fi

# Get node information
HOSTNAME=$(hostname)
HOST_IP=$(hostname -I | awk '{print $1}')

# Restore ETCD snapshot
echo "📦 Restoring ETCD snapshot from ${BACKUP_NAME}..."
etcdctl snapshot restore "${SNAPSHOT_FILE}" \
    --data-dir="${ETCD_DATA_DIR}" \
    --name="${HOSTNAME}" \
    --initial-cluster="${HOSTNAME}=https://${HOST_IP}:2380" \
    --initial-cluster-token="etcd-cluster-1" \
    --initial-advertise-peer-urls="https://${HOST_IP}:2380"

if [ $? -ne 0 ]; then
    echo "❌ Error: ETCD restore failed!"
    if [ -n "$CURRENT_BACKUP" ] && [ -d "$CURRENT_BACKUP" ]; then
        echo "⚠️  Restoring previous ETCD data..."
        mv "$CURRENT_BACKUP" "${ETCD_DATA_DIR}"
        echo "✅ Previous ETCD data restored"
    fi
    exit 1
fi

# Set proper ownership
echo "🔐 Setting proper ownership..."
chown -R etcd:etcd "${ETCD_DATA_DIR}" 2>/dev/null || echo "⚠️  Warning: Could not set etcd ownership"

# Restore certificates if they exist in backup
if [ -d "${selected_backup}/pki" ]; then
    echo "🔐 Restoring certificates..."
    cp -r "${selected_backup}/pki" /etc/kubernetes/ || echo "⚠️  Warning: Could not restore certificates"
fi

echo ""
echo "✅ ETCD restore completed successfully!"
echo ""
echo "📋 Restore Summary:"
echo "   Backup: ${BACKUP_NAME}"
echo "   Snapshot: ${SNAPSHOT_FILE}"
echo "   Data Directory: ${ETCD_DATA_DIR}"
if [ -n "$CURRENT_BACKUP" ]; then
    echo "   Previous backup: ${CURRENT_BACKUP}"
fi
echo ""
echo "⚠️  Next steps:"
echo "   1. Start containerd: systemctl start containerd"
echo "   2. Start kubelet: systemctl start kubelet"
echo "   3. Verify cluster: kubectl get nodes"
echo "   4. Check pods: kubectl get pods -A"
echo ""
echo "⚠️  If the cluster fails to start, you may need to:"
echo "   - Restore from ${CURRENT_BACKUP}"
echo "   - Rejoin worker nodes to the cluster"

