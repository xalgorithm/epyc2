#!/bin/sh

set -e

echo "🔄 Starting Immich upload backup process..."

# Install rsync (alpine base image doesn't include it)
echo "📦 Installing rsync..."
apk add --no-cache rsync

# Configuration
SOURCE_DIR="/source/upload"
DEST_DIR="/backup/uploads"

echo "📁 Source: ${SOURCE_DIR}"
echo "📁 Destination: ${DEST_DIR}"

# Create destination directory if it doesn't exist
mkdir -p "${DEST_DIR}"

# Verify source directory exists
if [ ! -d "${SOURCE_DIR}" ]; then
    echo "❌ Source directory does not exist: ${SOURCE_DIR}"
    exit 1
fi

# Run incremental sync with rsync
echo "📦 Starting rsync incremental sync..."
rsync -av --delete "${SOURCE_DIR}/" "${DEST_DIR}/"

echo "✅ Immich upload backup completed successfully."
