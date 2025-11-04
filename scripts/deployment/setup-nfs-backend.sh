#!/bin/bash

# Script to setup NFS mount for Terraform backend state storage
# This mounts the NFS share and prepares it for Terraform state
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

# Configuration
NFS_SERVER="192.168.0.7"
NFS_EXPORT="/data/kubernetes"

# Set mount point based on OS
if [ "$OS_TYPE" = "Darwin" ]; then
    MOUNT_POINT="/Volumes/nfs-k8s"
else
    MOUNT_POINT="/mnt/nfs-k8s"
fi

STATE_DIR="${MOUNT_POINT}/terraform-state"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         Terraform NFS Backend Setup                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
print_status "Detected OS: ${OS_TYPE}"
print_status "NFS Server: ${NFS_SERVER}"
print_status "NFS Export: ${NFS_EXPORT}"
print_status "Mount Point: ${MOUNT_POINT}"
print_status "State Directory: ${STATE_DIR}"
echo ""

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then 
    print_error "This script must be run with sudo"
    echo ""
    echo "Usage: sudo $0"
    exit 1
fi

# Check NFS client based on OS
print_status "Checking for NFS client..."
if [ "$OS_TYPE" = "Darwin" ]; then
    # macOS has NFS built-in
    print_success "NFS client built into macOS"
elif [ "$OS_TYPE" = "Linux" ]; then
    if ! command -v mount.nfs &> /dev/null; then
        print_warning "NFS client not found, installing..."
        apt-get update
        apt-get install -y nfs-common
        print_success "NFS client installed"
    else
        print_success "NFS client already installed"
    fi
else
    print_warning "Unknown OS type: ${OS_TYPE}"
fi

# Create mount point
print_status "Creating mount point..."
mkdir -p "${MOUNT_POINT}"
print_success "Mount point created: ${MOUNT_POINT}"

# Check if already mounted
if [ "$OS_TYPE" = "Darwin" ]; then
    # macOS check
    if mount | grep -q "${MOUNT_POINT}"; then
        print_warning "NFS already mounted at ${MOUNT_POINT}"
    else
        # Mount NFS share on macOS
        print_status "Mounting NFS share..."
        if mount -t nfs -o resvport "${NFS_SERVER}:${NFS_EXPORT}" "${MOUNT_POINT}"; then
            print_success "NFS mounted successfully"
        else
            print_error "Failed to mount NFS share"
            exit 1
        fi
    fi
else
    # Linux check
    if mountpoint -q "${MOUNT_POINT}"; then
        print_warning "NFS already mounted at ${MOUNT_POINT}"
    else
        # Mount NFS share on Linux
        print_status "Mounting NFS share..."
        if mount -t nfs "${NFS_SERVER}:${NFS_EXPORT}" "${MOUNT_POINT}"; then
            print_success "NFS mounted successfully"
        else
            print_error "Failed to mount NFS share"
            exit 1
        fi
    fi
fi

# Create terraform state directory
print_status "Creating terraform state directory..."
mkdir -p "${STATE_DIR}"
chmod 755 "${STATE_DIR}"
print_success "State directory created: ${STATE_DIR}"

# Set proper permissions
print_status "Setting permissions..."
# Get the user who invoked sudo
ACTUAL_USER="${SUDO_USER:-$USER}"
if [ "$ACTUAL_USER" != "root" ]; then
    if [ "$OS_TYPE" = "Darwin" ]; then
        # macOS: Get the primary group of the user
        ACTUAL_GROUP=$(id -gn "$ACTUAL_USER")
        chown -R "${ACTUAL_USER}:${ACTUAL_GROUP}" "${STATE_DIR}"
    else
        # Linux: Typically user:user
        chown -R "${ACTUAL_USER}:${ACTUAL_USER}" "${STATE_DIR}"
    fi
fi
print_success "Permissions set"

# Add persistent mount configuration
if [ "$OS_TYPE" = "Darwin" ]; then
    # macOS: Create a script for auto-mount (use launchd or manual)
    print_status "Creating mount script for macOS..."
    
    MOUNT_SCRIPT="/usr/local/bin/mount-nfs-k8s.sh"
    cat > "${MOUNT_SCRIPT}" <<EOF
#!/bin/bash
# Auto-mount script for NFS backend
if ! mount | grep -q "${MOUNT_POINT}"; then
    mkdir -p "${MOUNT_POINT}"
    mount -t nfs -o resvport "${NFS_SERVER}:${NFS_EXPORT}" "${MOUNT_POINT}"
fi
EOF
    chmod +x "${MOUNT_SCRIPT}"
    
    print_success "Mount script created: ${MOUNT_SCRIPT}"
    print_warning "macOS note: NFS won't auto-mount on reboot by default"
    print_status "To mount manually: sudo ${MOUNT_SCRIPT}"
    print_status "Or add to Login Items in System Preferences"
else
    # Linux: Add to /etc/fstab
    print_status "Checking /etc/fstab..."
    FSTAB_ENTRY="${NFS_SERVER}:${NFS_EXPORT} ${MOUNT_POINT} nfs defaults,_netdev 0 0"
    if grep -q "${MOUNT_POINT}" /etc/fstab; then
        print_warning "Entry already exists in /etc/fstab"
    else
        print_status "Adding entry to /etc/fstab for persistent mount..."
        echo "${FSTAB_ENTRY}" >> /etc/fstab
        print_success "Entry added to /etc/fstab"
    fi
fi

# Verify mount
echo ""
print_status "Verifying mount..."
if df -h "${MOUNT_POINT}" | grep -q "${NFS_SERVER}"; then
    print_success "NFS mount verified successfully"
    echo ""
    df -h "${MOUNT_POINT}"
else
    print_error "Mount verification failed"
    exit 1
fi

# Test write access
echo ""
print_status "Testing write access..."
TEST_FILE="${STATE_DIR}/.test_write"
if echo "test" > "${TEST_FILE}" 2>/dev/null; then
    rm -f "${TEST_FILE}"
    print_success "Write access confirmed"
else
    print_error "Cannot write to ${STATE_DIR}"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         Setup Complete!                                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
print_success "NFS backend is ready for Terraform"
echo ""
print_status "Next steps:"
echo "  1. Backup your current state: cp terraform.tfstate terraform.tfstate.backup"
echo "  2. Initialize backend: terraform init -migrate-state"
echo "  3. Verify state: terraform state list"
echo ""
print_status "Mount point will persist across reboots (added to /etc/fstab)"
echo ""

