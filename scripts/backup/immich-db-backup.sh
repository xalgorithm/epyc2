#!/bin/sh

set -e

echo "🔄 Starting Immich database backup process..."

# Configuration
BACKUP_DIR="/backup/db"
DB_HOST="immich-postgres.immich.svc.cluster.local"
DB_PORT="5432"
DB_NAME="immich"
DB_USER="immich"
DATE_STAMP=$(date +%Y%m%d)
DAY_OF_WEEK=$(date +%u)

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

echo "📁 Backup directory: ${BACKUP_DIR}"
echo "🗄️  Database: ${DB_NAME}@${DB_HOST}:${DB_PORT}"
echo "📅 Date: ${DATE_STAMP}"

# --- Daily Backup ---
DAILY_FILE="${BACKUP_DIR}/immich-db-daily-${DATE_STAMP}.sql.gz"
echo "📦 Creating daily database dump: ${DAILY_FILE}"

pg_dump -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" | gzip > "${DAILY_FILE}"

if [ ! -s "${DAILY_FILE}" ]; then
    echo "❌ Daily backup file is empty, aborting."
    rm -f "${DAILY_FILE}"
    exit 1
fi

echo "✅ Daily backup created: $(du -sh "${DAILY_FILE}" | cut -f1)"

# --- Weekly Backup (Sundays, day_of_week=7) ---
if [ "${DAY_OF_WEEK}" = "7" ]; then
    WEEKLY_FILE="${BACKUP_DIR}/immich-db-weekly-${DATE_STAMP}.sql.gz"
    echo "📦 Creating weekly database dump: ${WEEKLY_FILE}"
    cp "${DAILY_FILE}" "${WEEKLY_FILE}"
    echo "✅ Weekly backup created: $(du -sh "${WEEKLY_FILE}" | cut -f1)"
fi

# --- Retention Cleanup ---
echo "🧹 Cleaning up old backups..."

# Keep only the 7 most recent daily backups
DAILY_COUNT=$(ls -1t "${BACKUP_DIR}"/immich-db-daily-*.sql.gz 2>/dev/null | wc -l)
if [ "${DAILY_COUNT}" -gt 7 ]; then
    ls -1t "${BACKUP_DIR}"/immich-db-daily-*.sql.gz | tail -n +8 | while read -r file; do
        echo "🗑️  Removing old daily backup: ${file}"
        rm -f "${file}"
    done
fi

# Keep only the 4 most recent weekly backups
WEEKLY_COUNT=$(ls -1t "${BACKUP_DIR}"/immich-db-weekly-*.sql.gz 2>/dev/null | wc -l)
if [ "${WEEKLY_COUNT}" -gt 4 ]; then
    ls -1t "${BACKUP_DIR}"/immich-db-weekly-*.sql.gz | tail -n +5 | while read -r file; do
        echo "🗑️  Removing old weekly backup: ${file}"
        rm -f "${file}"
    done
fi

echo "✅ Immich database backup completed successfully."
