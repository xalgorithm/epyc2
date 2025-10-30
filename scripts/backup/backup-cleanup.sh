#!/bin/sh

set -e

echo "🧹 Starting backup cleanup process..."

# Configuration
RETENTION_DAYS=${RETENTION_DAYS:-30}
BACKUP_DIR=${BACKUP_DIR:-/backup}

echo "📁 Backup directory: ${BACKUP_DIR}"
echo "🗓️  Retention period: ${RETENTION_DAYS} days"

# Function to clean up old backups
cleanup_old_backups() {
    local backup_type="$1"
    local backup_path="${BACKUP_DIR}/${backup_type}"
    
    if [ ! -d "${backup_path}" ]; then
        echo "⚠️  Directory ${backup_path} does not exist, skipping..."
        return
    fi
    
    echo "🔍 Cleaning up ${backup_type} backups older than ${RETENTION_DAYS} days..."
    
    # Find and list old backups
    old_backups=$(find "${backup_path}" -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -name "20*" 2>/dev/null || true)
    
    if [ -z "$old_backups" ]; then
        echo "✅ No old ${backup_type} backups to clean up"
        return
    fi
    
    echo "📋 Found old ${backup_type} backups:"
    echo "$old_backups"
    
    # Calculate space to be freed
    space_to_free=$(echo "$old_backups" | xargs du -sh 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
    
    # Remove old backups
    echo "$old_backups" | while read -r backup_dir; do
        if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
            backup_size=$(du -sh "$backup_dir" | cut -f1)
            echo "🗑️  Removing: $(basename "$backup_dir") (${backup_size})"
            rm -rf "$backup_dir"
        fi
    done
    
    echo "✅ Cleaned up old ${backup_type} backups"
}

# Clean up ETCD backups
cleanup_old_backups "etcd"

# Clean up data backups
cleanup_old_backups "data"

# Clean up any orphaned files
echo "🔍 Cleaning up orphaned files..."
find "${BACKUP_DIR}" -type f -mtime +${RETENTION_DAYS} -name "*.tmp" -delete 2>/dev/null || true
find "${BACKUP_DIR}" -type f -mtime +${RETENTION_DAYS} -name "*.log" -delete 2>/dev/null || true

# Generate cleanup report
echo "📊 Generating cleanup report..."

# Count remaining backups
etcd_backups=$(find "${BACKUP_DIR}/etcd" -maxdepth 1 -type d -name "20*" 2>/dev/null | wc -l || echo "0")
data_backups=$(find "${BACKUP_DIR}/data" -maxdepth 1 -type d -name "20*" 2>/dev/null | wc -l || echo "0")

# Calculate total backup size
total_size=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1 || echo "0")

# Create cleanup report
cat > "${BACKUP_DIR}/cleanup-report.txt" << EOF
Backup Cleanup Report
====================
Cleanup Date: $(date)
Retention Period: ${RETENTION_DAYS} days

Current Backup Status:
- ETCD Backups: ${etcd_backups}
- Data Backups: ${data_backups}
- Total Size: ${total_size}

Recent ETCD Backups:
$(find "${BACKUP_DIR}/etcd" -maxdepth 1 -type d -name "20*" 2>/dev/null | sort -r | head -5 | xargs -I {} basename {} || echo "None")

Recent Data Backups:
$(find "${BACKUP_DIR}/data" -maxdepth 1 -type d -name "20*" 2>/dev/null | sort -r | head -5 | xargs -I {} basename {} || echo "None")

Disk Usage:
$(df -h "${BACKUP_DIR}" 2>/dev/null || echo "Unable to get disk usage")
EOF

# Update metrics
echo "📊 Updating cleanup metrics..."
cat > /tmp/backup_cleanup_metrics.prom << EOF
# HELP backup_cleanup_last_run_timestamp Last backup cleanup run timestamp
# TYPE backup_cleanup_last_run_timestamp gauge
backup_cleanup_last_run_timestamp $(date +%s)

# HELP backup_etcd_count Number of ETCD backups
# TYPE backup_etcd_count gauge
backup_etcd_count ${etcd_backups}

# HELP backup_data_count Number of data backups
# TYPE backup_data_count gauge
backup_data_count ${data_backups}

# HELP backup_total_size_bytes Total backup size in bytes
# TYPE backup_total_size_bytes gauge
backup_total_size_bytes $(du -sb "${BACKUP_DIR}" 2>/dev/null | cut -f1 || echo "0")
EOF

echo "✅ Backup cleanup completed successfully!"
echo "📊 Current status:"
echo "   - ETCD backups: ${etcd_backups}"
echo "   - Data backups: ${data_backups}"
echo "   - Total size: ${total_size}"
echo ""
echo "📋 Cleanup report saved to: ${BACKUP_DIR}/cleanup-report.txt"

# Show disk usage
echo "💾 Disk usage:"
df -h "${BACKUP_DIR}" 2>/dev/null || echo "Unable to show disk usage"