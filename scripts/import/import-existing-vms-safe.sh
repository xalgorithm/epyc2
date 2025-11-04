#!/bin/bash

# Safe VM Import Script
# This script imports existing Proxmox VMs into Terraform state
# Run this before terraform apply to prevent VM recreation

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

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         Safe VM Import to Terraform State                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if we're in the right directory
if [ ! -f "infrastructure-proxmox.tf" ]; then
    print_error "infrastructure-proxmox.tf not found. Please run from terraform directory."
    exit 1
fi

# Check for active terraform processes
print_status "Checking for active Terraform processes..."
if pgrep -x terraform > /dev/null; then
    print_error "Terraform is currently running!"
    print_warning "Please wait for it to complete or kill it with:"
    echo "    kill $(pgrep -x terraform)"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for state lock
print_status "Checking state lock..."
if terraform plan -lock=false > /dev/null 2>&1; then
    print_success "State is accessible"
else
    print_error "State is locked or inaccessible"
    print_warning "You may need to force-unlock:"
    echo "    terraform force-unlock <LOCK_ID>"
    exit 1
fi

# Source variables from terraform.tfvars if available
print_status "Reading configuration..."
PROXMOX_HOST="192.168.0.7"
PROXMOX_NODE="pve"

# Prompt for Proxmox credentials
echo ""
echo "Enter Proxmox credentials (or press Enter to skip SSH check):"
read -p "Proxmox user [root]: " PROXMOX_USER
PROXMOX_USER=${PROXMOX_USER:-root}

# Try to get VM list from Proxmox
print_status "Attempting to fetch VM list from Proxmox..."
if command -v ssh > /dev/null 2>&1; then
    if VM_LIST=$(ssh -o ConnectTimeout=5 ${PROXMOX_USER}@${PROXMOX_HOST} "qm list" 2>/dev/null); then
        echo ""
        print_success "Found VMs in Proxmox:"
        echo "$VM_LIST"
        echo ""
    else
        print_warning "Could not SSH to Proxmox. Will prompt for VM IDs manually."
    fi
else
    print_warning "SSH not available. Will prompt for VM IDs manually."
fi

# Check current state
print_status "Checking Terraform state for existing VMs..."
echo ""

VM_IN_STATE=false
if terraform state list 2>/dev/null | grep -q "proxmox_virtual_environment_vm"; then
    print_warning "VMs already in state:"
    terraform state list | grep "proxmox_virtual_environment_vm"
    VM_IN_STATE=true
    echo ""
    read -p "VMs already in state. Continue with import anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Skipping import. Run terraform plan to check configuration."
        exit 0
    fi
else
    print_status "No VMs found in state. Ready to import."
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         VM Import Configuration                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
print_status "We will import 3 VMs:"
echo "  1. bumblebee (control plane)"
echo "  2. prime (worker)"
echo "  3. wheeljack (worker)"
echo ""

# Function to import VM
import_vm() {
    local VM_NAME=$1
    local RESOURCE_NAME=$2
    
    echo ""
    print_status "Importing VM: $VM_NAME"
    
    # Check if already in state
    if terraform state list 2>/dev/null | grep -q "proxmox_virtual_environment_vm.${RESOURCE_NAME}"; then
        print_warning "VM already in state, removing first..."
        terraform state rm "proxmox_virtual_environment_vm.${RESOURCE_NAME}" > /dev/null 2>&1 || true
    fi
    
    # Prompt for VM ID
    read -p "Enter Proxmox VM ID for ${VM_NAME} (or 'skip'): " VM_ID
    
    if [ "$VM_ID" = "skip" ] || [ -z "$VM_ID" ]; then
        print_warning "Skipping $VM_NAME"
        return
    fi
    
    # Validate VM ID is numeric
    if ! [[ "$VM_ID" =~ ^[0-9]+$ ]]; then
        print_error "Invalid VM ID: $VM_ID (must be numeric)"
        return
    fi
    
    # Import the VM
    print_status "Importing ${PROXMOX_NODE}/${VM_ID} as proxmox_virtual_environment_vm.${RESOURCE_NAME}..."
    
    if terraform import "proxmox_virtual_environment_vm.${RESOURCE_NAME}" "${PROXMOX_NODE}/${VM_ID}"; then
        print_success "Successfully imported $VM_NAME (ID: $VM_ID)"
    else
        print_error "Failed to import $VM_NAME"
        print_warning "This might mean:"
        echo "  - VM ID doesn't exist in Proxmox"
        echo "  - Insufficient permissions"
        echo "  - VM is on a different node"
        echo ""
        read -p "Continue with other VMs? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Import each VM
import_vm "bumblebee" "bumblebee"
import_vm "prime" "prime"
import_vm "wheeljack" "wheeljack"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         Import Complete                                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Show what's now in state
print_status "VMs now in Terraform state:"
terraform state list | grep "proxmox_virtual_environment_vm" || print_warning "No VMs in state"

echo ""
print_status "Running terraform plan to check for changes..."
echo ""

# Run plan to show what will happen
if terraform plan -no-color 2>&1 | head -50; then
    echo ""
    print_success "Import successful!"
    echo ""
    print_status "Next steps:"
    echo "  1. Review the plan output above"
    echo "  2. If it shows 'No changes', you're good!"
    echo "  3. If it shows changes, review them carefully"
    echo "  4. Run: terraform apply"
else
    echo ""
    print_warning "Plan failed - but VMs are imported"
    print_status "Check configuration and try: terraform plan"
fi

echo ""

