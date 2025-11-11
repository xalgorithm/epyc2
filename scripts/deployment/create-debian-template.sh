#!/usr/bin/env bash
# Create Debian 13 Template for Proxmox
# This script creates a Debian 13 cloud-init template (VM ID 9001) in Proxmox

set -euo pipefail

# Configuration
PROXMOX_HOST="${PROXMOX_HOST:-192.168.0.7}"
PROXMOX_USER="${PROXMOX_USER:-root}"
VM_ID=9001
VM_NAME="debian-13-template"
DEBIAN_VERSION="trixie"  # Debian 13 codename
MEMORY=2048
CORES=2
STORAGE="local-lvm"
NETWORK_BRIDGE="vmbr0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if VM already exists
check_vm_exists() {
    log_info "Checking if VM $VM_ID already exists..."
    if ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "qm status $VM_ID" 2>/dev/null; then
        log_warn "VM $VM_ID already exists!"
        read -p "Do you want to delete it and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Destroying existing VM $VM_ID..."
            ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "qm destroy $VM_ID"
        else
            log_error "Aborted. Please use a different VM ID or delete the existing VM manually."
            exit 1
        fi
    fi
}

# Create Debian template
create_template() {
    log_info "Creating Debian 13 template on Proxmox host $PROXMOX_HOST..."

    # Execute all commands on Proxmox host
    ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" bash <<EOF
set -euo pipefail

echo "Creating VM $VM_ID..."
qm create $VM_ID \
    --name "$VM_NAME" \
    --memory $MEMORY \
    --cores $CORES \
    --net0 virtio,bridge=$NETWORK_BRIDGE

echo "Downloading Debian 13 cloud image..."
cd /var/lib/vz/template/iso

# Download latest Debian 13 (Trixie) cloud image
DEBIAN_IMAGE="debian-13-generic-amd64.qcow2"

if [ ! -f "\$DEBIAN_IMAGE" ]; then
    echo "Downloading Debian 13 cloud image..."
    wget -q --show-progress \
        "https://cloud.debian.org/images/cloud/$DEBIAN_VERSION/latest/\$DEBIAN_IMAGE" \
        -O "\$DEBIAN_IMAGE" || {
            echo "Failed to download Debian image"
            echo "Trying alternative URL..."
            # Fallback: try daily builds
            wget -q --show-progress \
                "https://cloud.debian.org/images/cloud/$DEBIAN_VERSION/daily/latest/\$DEBIAN_IMAGE" \
                -O "\$DEBIAN_IMAGE"
        }
else
    echo "Debian cloud image already exists, skipping download."
fi

echo "Importing disk to VM $VM_ID..."
qm importdisk $VM_ID "\$DEBIAN_IMAGE" $STORAGE >/dev/null

echo "Configuring VM..."
# Set SCSI controller
qm set $VM_ID --scsihw virtio-scsi-single >/dev/null

# Attach the imported disk
qm set $VM_ID --scsi0 $STORAGE:vm-$VM_ID-disk-0 >/dev/null

# Set boot disk
qm set $VM_ID --boot order=scsi0 >/dev/null

# Add cloud-init drive
qm set $VM_ID --ide2 $STORAGE:cloudinit >/dev/null

# Set serial console (for cloud-init)
qm set $VM_ID --serial0 socket --vga serial0 >/dev/null

# Enable QEMU guest agent
qm set $VM_ID --agent enabled=1 >/dev/null

# Set OS type
qm set $VM_ID --ostype l26 >/dev/null

echo "Converting VM to template..."
qm template $VM_ID

echo "Template created successfully!"
qm list | grep $VM_ID
EOF

    if [ $? -eq 0 ]; then
        log_info "✓ Debian 13 template created successfully!"
        log_info "  VM ID: $VM_ID"
        log_info "  Name: $VM_NAME"
        log_info ""
        log_info "You can now deploy the work VM with:"
        log_info "  terraform apply -target=proxmox_virtual_environment_vm.work"
    else
        log_error "Failed to create template. Check the errors above."
        exit 1
    fi
}

# Verify template
verify_template() {
    log_info "Verifying template..."
    if ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "qm config $VM_ID | grep -q 'template: 1'"; then
        log_info "✓ Template verification successful"
    else
        log_error "Template verification failed"
        exit 1
    fi
}

# Main execution
main() {
    echo "======================================"
    echo "Debian 13 Template Creation Script"
    echo "======================================"
    echo ""
    echo "Configuration:"
    echo "  Proxmox Host: $PROXMOX_HOST"
    echo "  VM ID: $VM_ID"
    echo "  VM Name: $VM_NAME"
    echo "  Memory: ${MEMORY}MB"
    echo "  Cores: $CORES"
    echo "  Storage: $STORAGE"
    echo ""

    # Check if we can connect to Proxmox
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$PROXMOX_USER@$PROXMOX_HOST" "echo 'Connection successful'" >/dev/null 2>&1; then
        log_error "Cannot connect to Proxmox host $PROXMOX_HOST"
        log_error "Please check:"
        log_error "  1. SSH access is configured"
        log_error "  2. Host is reachable: ping $PROXMOX_HOST"
        log_error "  3. SSH key is in authorized_keys"
        exit 1
    fi

    check_vm_exists
    create_template
    verify_template

    echo ""
    log_info "=========================================="
    log_info "Debian 13 Template Setup Complete!"
    log_info "=========================================="
    echo ""
    log_info "Next steps:"
    echo "  1. Verify the template: ssh $PROXMOX_USER@$PROXMOX_HOST 'qm list | grep $VM_ID'"
    echo "  2. Deploy work VM: terraform apply -target=proxmox_virtual_environment_vm.work"
    echo ""
}

# Run main function
main "$@"

