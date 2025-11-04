#!/bin/bash

# Script to check Terraform NFS backend status
# Quick health check for the backend configuration
# Compatible with macOS (Darwin) and Linux

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
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Detect OS
OS_TYPE=$(uname -s)

# Set mount point based on OS
if [ "$OS_TYPE" = "Darwin" ]; then
    MOUNT_POINT="/Volumes/nfs-k8s"
else
    MOUNT_POINT="/mnt/nfs-k8s"
fi

STATE_DIR="${MOUNT_POINT}/terraform-state"
STATE_FILE="${STATE_DIR}/terraform.tfstate"
NFS_SERVER="192.168.0.7"

echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║         Terraform NFS Backend Status Check                            ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""

# Check NFS server connectivity
print_status "Checking NFS server connectivity..."
if ping -c 1 -W 2 "${NFS_SERVER}" >/dev/null 2>&1; then
    print_success "NFS server (${NFS_SERVER}) is reachable"
else
    print_error "Cannot reach NFS server (${NFS_SERVER})"
fi

# Check if NFS client is installed
print_status "Checking NFS client..."
if [ "$OS_TYPE" = "Darwin" ]; then
    print_success "NFS client built into macOS"
elif command -v mount.nfs >/dev/null 2>&1; then
    print_success "NFS client is installed"
else
    print_error "NFS client is not installed"
    echo "         Run: sudo apt-get install nfs-common"
fi

# Check mount point
print_status "Checking mount point..."
if [ -d "${MOUNT_POINT}" ]; then
    print_success "Mount point exists: ${MOUNT_POINT}"
else
    print_error "Mount point does not exist: ${MOUNT_POINT}"
    echo "         Run: sudo mkdir -p ${MOUNT_POINT}"
fi

# Check if mounted
print_status "Checking if NFS is mounted..."
if [ "$OS_TYPE" = "Darwin" ]; then
    if mount | grep -q "${MOUNT_POINT}"; then
        print_success "NFS is mounted at ${MOUNT_POINT}"
        echo ""
        df -h "${MOUNT_POINT}" | grep -v "^Filesystem"
    else
        print_error "NFS is not mounted"
        echo "         Run: sudo ./scripts/setup-nfs-backend.sh"
    fi
else
    if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        print_success "NFS is mounted at ${MOUNT_POINT}"
        echo ""
        df -h "${MOUNT_POINT}" | grep -v "^Filesystem"
    else
        print_error "NFS is not mounted"
        echo "         Run: sudo ./scripts/setup-nfs-backend.sh"
    fi
fi

# Check state directory
print_status "Checking state directory..."
if [ -d "${STATE_DIR}" ]; then
    print_success "State directory exists: ${STATE_DIR}"
else
    print_error "State directory does not exist: ${STATE_DIR}"
fi

# Check state file
print_status "Checking state file..."
if [ -f "${STATE_FILE}" ]; then
    print_success "State file exists: ${STATE_FILE}"
    FILE_SIZE=$(du -h "${STATE_FILE}" | cut -f1)
    if [ "$OS_TYPE" = "Darwin" ]; then
        FILE_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "${STATE_FILE}" 2>/dev/null || echo "unknown")
    else
        FILE_DATE=$(stat -c "%y" "${STATE_FILE}" 2>/dev/null || echo "unknown")
    fi
    echo "         Size: ${FILE_SIZE}"
    echo "         Modified: ${FILE_DATE}"
else
    print_warning "State file does not exist yet"
    echo "         Will be created after: terraform init -migrate-state"
fi

# Check write permissions
print_status "Checking write permissions..."
if [ -w "${STATE_DIR}" ]; then
    print_success "Write access confirmed"
else
    print_error "No write access to ${STATE_DIR}"
    echo "         Run: sudo chown -R \$USER:\$USER ${STATE_DIR}"
fi

# Check persistent mount configuration
if [ "$OS_TYPE" = "Darwin" ]; then
    print_status "Checking mount script..."
    if [ -f "/usr/local/bin/mount-nfs-k8s.sh" ]; then
        print_success "Mount script exists: /usr/local/bin/mount-nfs-k8s.sh"
    else
        print_warning "Mount script not found (mount won't persist across reboots)"
    fi
else
    print_status "Checking /etc/fstab for persistent mount..."
    if grep -q "${MOUNT_POINT}" /etc/fstab 2>/dev/null; then
        print_success "Persistent mount configured in /etc/fstab"
    else
        print_warning "Not configured in /etc/fstab (mount won't persist across reboots)"
    fi
fi

# Check backend configuration
print_status "Checking backend configuration..."
if [ -f "backend.tf" ]; then
    print_success "backend.tf exists"
    if grep -q "local" backend.tf && grep -q "${STATE_FILE}" backend.tf; then
        print_success "Backend configured for NFS path"
    else
        print_warning "Backend configuration may need review"
    fi
else
    print_error "backend.tf not found"
fi

# Check for Terraform initialization
print_status "Checking Terraform initialization..."
if [ -d ".terraform" ]; then
    print_success "Terraform is initialized"
else
    print_warning "Terraform not initialized yet"
    echo "         Run: terraform init"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║         Status Check Complete                                          ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""

# Summary
ERRORS=0
if [ "$OS_TYPE" = "Darwin" ]; then
    if ! mount | grep -q "${MOUNT_POINT}"; then
        ((ERRORS++))
    fi
else
    if ! mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        ((ERRORS++))
    fi
fi
if [ ! -w "${STATE_DIR}" ]; then
    ((ERRORS++))
fi

if [ $ERRORS -eq 0 ]; then
    print_success "Backend is ready for use!"
    echo ""
    echo "Next steps:"
    echo "  1. Backup state: cp terraform.tfstate terraform.tfstate.backup"
    echo "  2. Migrate state: terraform init -migrate-state"
else
    print_error "Backend has issues that need to be resolved"
    echo ""
    echo "Fix issues:"
    echo "  sudo ./scripts/setup-nfs-backend.sh"
fi

echo ""

