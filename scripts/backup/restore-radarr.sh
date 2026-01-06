#!/bin/sh

set -e

echo "🔄 Radarr Restore Script"
echo "======================="
echo ""

# Configuration
BACKUP_BASE_DIR="/backup/radarr"
RESTORE_TARGET="/config"

# Check if backup directory exists
if [ ! -d "${BACKUP_BASE_DIR}" ]; then
    echo "❌ Error: Backup directory not found: ${BACKUP_BASE_DIR}"
    exit 1
fi

# List available backups
echo "📁 Available Radarr backups:"
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
    backup_file="${backup_dir}/radarr-config.tar.gz"
    
    if [ -f "$backup_file" ]; then
        backup_size=$(du -sh "$backup_file" | cut -f1)
        if [ -f "${backup_dir}/backup-info.txt" ]; then
            backup_date=$(grep "Backup Date:" "${backup_dir}/backup-info.txt" | cut -d: -f2- | xargs)
        else
            backup_date="Unknown"
        fi
        
        echo "  [$i] ${backup_name}"
        echo "      Size: ${backup_size}"
        echo "      Date: ${backup_date}"
        
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

BACKUP_FILE="${selected_backup}/radarr-config.tar.gz"
BACKUP_NAME=$(basename "$selected_backup")

if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Error: Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

echo ""
echo "⚠️  WARNING: This will restore Radarr configuration from backup: ${BACKUP_NAME}"
echo "⚠️  Current configuration will be backed up first"
echo ""
echo "Are you sure you want to proceed? (yes/no):"
read -r confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Restore cancelled"
    exit 0
fi

# Create backup of current config
echo "💾 Backing up current configuration..."
CURRENT_BACKUP_DIR="/tmp/radarr-current-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$CURRENT_BACKUP_DIR"
if [ "$(ls -A $RESTORE_TARGET 2>/dev/null)" ]; then
    tar -czf "${CURRENT_BACKUP_DIR}/radarr-config-current.tar.gz" -C "$RESTORE_TARGET" . || true
    echo "✅ Current config backed up to: ${CURRENT_BACKUP_DIR}"
fi

# Clear existing config
echo "🗑️  Clearing existing configuration..."
rm -rf "${RESTORE_TARGET:?}"/*

# Restore from backup
echo "📦 Restoring Radarr configuration from ${BACKUP_NAME}..."
tar -xzf "$BACKUP_FILE" -C "$RESTORE_TARGET"

# Verify restoration
if [ $? -eq 0 ]; then
    echo "✅ Radarr configuration restored successfully!"
    echo ""
    echo "📋 Restore Summary:"
    echo "   Backup: ${BACKUP_NAME}"
    echo "   Source: ${BACKUP_FILE}"
    echo "   Target: ${RESTORE_TARGET}"
    echo "   Current backup saved to: ${CURRENT_BACKUP_DIR}"
    echo ""
    echo "⚠️  Please restart the Radarr pod for changes to take effect:"
    echo "   kubectl rollout restart deployment/radarr -n media"
else
    echo "❌ Error: Restore failed!"
    echo "⚠️  Attempting to restore previous configuration..."
    if [ -f "${CURRENT_BACKUP_DIR}/radarr-config-current.tar.gz" ]; then
        tar -xzf "${CURRENT_BACKUP_DIR}/radarr-config-current.tar.gz" -C "$RESTORE_TARGET"
        echo "✅ Previous configuration restored"
    fi
    exit 1
fi

