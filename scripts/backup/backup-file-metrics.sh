#!/bin/sh

# Backup File Metrics Generator
# This script generates metrics about backup files for Prometheus scraping

set -e

BACKUP_DIR="/host/backup"
METRICS_FILE="/var/lib/node_exporter/textfile_collector/backup_files.prom"

# Ensure metrics directory exists
mkdir -p "$(dirname "$METRICS_FILE")"

# Generate backup file metrics
echo "# HELP backup_directories_total Total number of backup directories" > "$METRICS_FILE"
echo "# TYPE backup_directories_total gauge" >> "$METRICS_FILE"

# Count backup directories
if [ -d "$BACKUP_DIR/data" ]; then
    DATA_BACKUP_COUNT=$(ls -1 "$BACKUP_DIR/data" 2>/dev/null | wc -l)
else
    DATA_BACKUP_COUNT=0
fi

if [ -d "$BACKUP_DIR/etcd" ]; then
    ETCD_BACKUP_COUNT=$(ls -1 "$BACKUP_DIR/etcd" 2>/dev/null | wc -l)
else
    ETCD_BACKUP_COUNT=0
fi

echo "backup_directories_total{type=\"data\"} $DATA_BACKUP_COUNT" >> "$METRICS_FILE"
echo "backup_directories_total{type=\"etcd\"} $ETCD_BACKUP_COUNT" >> "$METRICS_FILE"

# Count total files in backup directories
echo "" >> "$METRICS_FILE"
echo "# HELP backup_files_total Total number of backup files" >> "$METRICS_FILE"
echo "# TYPE backup_files_total gauge" >> "$METRICS_FILE"

if [ -d "$BACKUP_DIR/data" ]; then
    DATA_FILES_COUNT=$(find "$BACKUP_DIR/data" -type f 2>/dev/null | wc -l)
else
    DATA_FILES_COUNT=0
fi

if [ -d "$BACKUP_DIR/etcd" ]; then
    ETCD_FILES_COUNT=$(find "$BACKUP_DIR/etcd" -type f 2>/dev/null | wc -l)
else
    ETCD_FILES_COUNT=0
fi

echo "backup_files_total{type=\"data\"} $DATA_FILES_COUNT" >> "$METRICS_FILE"
echo "backup_files_total{type=\"etcd\"} $ETCD_FILES_COUNT" >> "$METRICS_FILE"

# Calculate total backup storage usage
echo "" >> "$METRICS_FILE"
echo "# HELP backup_storage_bytes Total backup storage usage in bytes" >> "$METRICS_FILE"
echo "# TYPE backup_storage_bytes gauge" >> "$METRICS_FILE"

if [ -d "$BACKUP_DIR/data" ]; then
    DATA_SIZE=$(du -sb "$BACKUP_DIR/data" 2>/dev/null | cut -f1)
else
    DATA_SIZE=0
fi

if [ -d "$BACKUP_DIR/etcd" ]; then
    ETCD_SIZE=$(du -sb "$BACKUP_DIR/etcd" 2>/dev/null | cut -f1)
else
    ETCD_SIZE=0
fi

TOTAL_SIZE=$((DATA_SIZE + ETCD_SIZE))

echo "backup_storage_bytes{type=\"data\"} $DATA_SIZE" >> "$METRICS_FILE"
echo "backup_storage_bytes{type=\"etcd\"} $ETCD_SIZE" >> "$METRICS_FILE"
echo "backup_storage_bytes{type=\"total\"} $TOTAL_SIZE" >> "$METRICS_FILE"

# Get oldest and newest backup timestamps
echo "" >> "$METRICS_FILE"
echo "# HELP backup_oldest_timestamp Timestamp of the oldest backup" >> "$METRICS_FILE"
echo "# TYPE backup_oldest_timestamp gauge" >> "$METRICS_FILE"
echo "# HELP backup_newest_timestamp Timestamp of the newest backup" >> "$METRICS_FILE"
echo "# TYPE backup_newest_timestamp gauge" >> "$METRICS_FILE"

if [ -d "$BACKUP_DIR/data" ] && [ "$(ls -A "$BACKUP_DIR/data" 2>/dev/null)" ]; then
    OLDEST_DATA=$(ls -1t "$BACKUP_DIR/data" 2>/dev/null | tail -1)
    NEWEST_DATA=$(ls -1t "$BACKUP_DIR/data" 2>/dev/null | head -1)
    
    if [ -n "$OLDEST_DATA" ]; then
        OLDEST_TIMESTAMP=$(stat -c %Y "$BACKUP_DIR/data/$OLDEST_DATA" 2>/dev/null || echo "0")
        echo "backup_oldest_timestamp{type=\"data\"} $OLDEST_TIMESTAMP" >> "$METRICS_FILE"
    fi
    
    if [ -n "$NEWEST_DATA" ]; then
        NEWEST_TIMESTAMP=$(stat -c %Y "$BACKUP_DIR/data/$NEWEST_DATA" 2>/dev/null || echo "0")
        echo "backup_newest_timestamp{type=\"data\"} $NEWEST_TIMESTAMP" >> "$METRICS_FILE"
    fi
fi

if [ -d "$BACKUP_DIR/etcd" ] && [ "$(ls -A "$BACKUP_DIR/etcd" 2>/dev/null)" ]; then
    OLDEST_ETCD=$(ls -1t "$BACKUP_DIR/etcd" 2>/dev/null | tail -1)
    NEWEST_ETCD=$(ls -1t "$BACKUP_DIR/etcd" 2>/dev/null | head -1)
    
    if [ -n "$OLDEST_ETCD" ]; then
        OLDEST_TIMESTAMP=$(stat -c %Y "$BACKUP_DIR/etcd/$OLDEST_ETCD" 2>/dev/null || echo "0")
        echo "backup_oldest_timestamp{type=\"etcd\"} $OLDEST_TIMESTAMP" >> "$METRICS_FILE"
    fi
    
    if [ -n "$NEWEST_ETCD" ]; then
        NEWEST_TIMESTAMP=$(stat -c %Y "$BACKUP_DIR/etcd/$NEWEST_ETCD" 2>/dev/null || echo "0")
        echo "backup_newest_timestamp{type=\"etcd\"} $NEWEST_TIMESTAMP" >> "$METRICS_FILE"
    fi
fi

# Application-specific backup file counts
echo "" >> "$METRICS_FILE"
echo "# HELP backup_application_files Application-specific backup file counts" >> "$METRICS_FILE"
echo "# TYPE backup_application_files gauge" >> "$METRICS_FILE"



# Count Grafana backups
GRAFANA_COUNT=$(find "$BACKUP_DIR/data" -name "grafana.db" 2>/dev/null | wc -l)
echo "backup_application_files{application=\"grafana\"} $GRAFANA_COUNT" >> "$METRICS_FILE"

# Count Prometheus backups
PROMETHEUS_COUNT=$(find "$BACKUP_DIR/data" -name "prometheus-*.tar.gz" 2>/dev/null | wc -l)
echo "backup_application_files{application=\"prometheus\"} $PROMETHEUS_COUNT" >> "$METRICS_FILE"

# Count Loki backups
LOKI_COUNT=$(find "$BACKUP_DIR/data" -name "loki-data.tar.gz" 2>/dev/null | wc -l)
echo "backup_application_files{application=\"loki\"} $LOKI_COUNT" >> "$METRICS_FILE"

# Count Mimir backups
MIMIR_COUNT=$(find "$BACKUP_DIR/data" -name "mimir-data.tar.gz" 2>/dev/null | wc -l)
echo "backup_application_files{application=\"mimir\"} $MIMIR_COUNT" >> "$METRICS_FILE"

echo "Backup file metrics updated: $METRICS_FILE"