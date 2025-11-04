#!/bin/bash

# Script to safely unmount the NFS backend
# Use this before maintenance or troubleshooting
# Compatible with macOS (Darwin) and Linux

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Detect OS
OS_TYPE=$(uname -s)

# Set mount point based on OS
if [ "$OS_TYPE" = "Darwin" ]; then
    MOUNT_POINT="/Volumes/nfs-k8s"
else
    MOUNT_POINT="/mnt/nfs-k8s"
fi

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         Unmount Terraform NFS Backend                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then 
    print_error "This script must be run with sudo"
    echo ""
    echo "Usage: sudo $0"
    exit 1
fi

# Check if mounted
if [ "$OS_TYPE" = "Darwin" ]; then
    if ! mount | grep -q "${MOUNT_POINT}"; then
        print_warning "NFS is not mounted at ${MOUNT_POINT}"
        exit 0
    fi
else
    if ! mountpoint -q "${MOUNT_POINT}"; then
        print_warning "NFS is not mounted at ${MOUNT_POINT}"
        exit 0
    fi
fi

# Check for active terraform processes
print_status "Checking for active Terraform processes..."
if pgrep -x "terraform" > /dev/null; then
    print_error "Terraform is currently running!"
    print_status "Please stop all Terraform operations before unmounting"
    exit 1
fi

# Unmount
print_status "Unmounting ${MOUNT_POINT}..."
if umount "${MOUNT_POINT}"; then
    print_success "NFS unmounted successfully"
else
    print_error "Failed to unmount. There may be open files."
    if [ "$OS_TYPE" = "Darwin" ]; then
        print_status "Trying forced unmount..."
        if umount -f "${MOUNT_POINT}"; then
            print_warning "Forced unmount successful"
        else
            print_error "Unable to unmount. Check for processes using the mount:"
            echo ""
            lsof +D "${MOUNT_POINT}" 2>/dev/null || true
            exit 1
        fi
    else
        print_status "Trying lazy unmount..."
        if umount -l "${MOUNT_POINT}"; then
            print_warning "Lazy unmount successful (will complete when files are closed)"
        else
            print_error "Unable to unmount. Check for processes using the mount:"
            echo ""
            lsof +D "${MOUNT_POINT}" 2>/dev/null || fuser -vm "${MOUNT_POINT}" 2>/dev/null
            exit 1
        fi
    fi
fi

echo ""
print_success "Unmount complete"
print_status "To remount, run: sudo ./scripts/setup-nfs-backend.sh"
echo ""

