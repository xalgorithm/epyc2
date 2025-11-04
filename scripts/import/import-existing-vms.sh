#!/bin/bash

# Script to import existing Proxmox VMs into Terraform state
# Run this when you have network connectivity to Proxmox

echo "Importing existing Proxmox VMs into Terraform state..."

# You'll need to find the actual VM IDs from Proxmox
# Replace these with the actual VM IDs from your Proxmox environment

echo "Step 1: Find VM IDs in Proxmox"
echo "Login to Proxmox web interface and note the VM IDs for:"
echo "- bumblebee (control plane)"
echo "- prime (worker 1)" 
echo "- wheeljack (worker 2)"
echo ""

echo "Step 2: Import VMs using correct format (node/vmid)"
echo "terraform import proxmox_virtual_environment_vm.bumblebee pve/102"
echo "terraform import proxmox_virtual_environment_vm.prime pve/101"
echo "terraform import proxmox_virtual_environment_vm.wheeljack pve/100"
echo ""

echo "Step 3: Verify import worked"
echo "terraform plan"
echo ""

echo "If you know the VM IDs, uncomment and modify these lines:"
echo "# terraform import proxmox_virtual_environment_vm.bumblebee pve/102"
echo "# terraform import proxmox_virtual_environment_vm.prime pve/103" 
echo "# terraform import proxmox_virtual_environment_vm.wheeljack pve/104"

# Based on your error, it looks like bumblebee is VM ID 102
# Uncomment these lines when you know all the VM IDs:
terraform import proxmox_virtual_environment_vm.bumblebee pve/102
terraform import proxmox_virtual_environment_vm.prime pve/101
terraform import proxmox_virtual_environment_vm.wheeljack pve/100
