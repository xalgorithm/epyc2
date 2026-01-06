#!/bin/sh

set -e

echo "🔄 Starting Radarr backup process..."

# Configuration
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/radarr/${BACKUP_DATE}"
SOURCE_PATH="/config"

# Create backup directory
mkdir -p "${BACKUP_PATH}"
chmod 755 "${BACKUP_PATH}"

echo "📁 Backup directory: ${BACKUP_PATH}"
echo "📦 Source: ${SOURCE_PATH}"

# Create backup using tar with compression
echo "📦 Creating Radarr config backup..."
tar -czf "${BACKUP_PATH}/radarr-config.tar.gz" -C "${SOURCE_PATH}" .

# Set permissions on backup file
chmod 755 "${BACKUP_PATH}/radarr-config.tar.gz"

# Create backup metadata
echo "📋 Creating backup metadata..."
cat > "${BACKUP_PATH}/backup-info.txt" << EOF
Backup Date: $(date)
Application: Radarr
Backup Type: Config Directory
Source Path: ${SOURCE_PATH}
Backup Size: $(du -sh "${BACKUP_PATH}/radarr-config.tar.gz" | cut -f1)
EOF

chmod 755 "${BACKUP_PATH}/backup-info.txt"

# Create success marker
touch "${BACKUP_PATH}/backup-success"
chmod 755 "${BACKUP_PATH}/backup-success"

# List backup contents
echo "✅ Backup completed successfully!"
ls -lh "${BACKUP_PATH}/"

# Clean up old backups (keep last 7 days)
echo "🧹 Cleaning up old backups..."
find "${BACKUP_DIR}/radarr" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

echo "✅ Radarr backup completed at ${BACKUP_PATH}"

