#!/bin/bash
set -e

echo "=== Import Critical Resources ==="
echo "This script imports the most essential resources to get Terraform state working"
echo ""

# VM IDs - YOU MUST UPDATE THESE
echo "STEP 1: Update VM IDs in this script"
echo "Edit this script and set the correct VM IDs from Proxmox:"
echo ""
BUMBLEBEE_ID="CHANGE_ME"  # Replace with actual VM ID from Proxmox
PRIME_ID="CHANGE_ME"      # Replace with actual VM ID from Proxmox  
WHEELJACK_ID="CHANGE_ME"  # Replace with actual VM ID from Proxmox

if [[ "$BUMBLEBEE_ID" == "CHANGE_ME" ]]; then
    echo "ERROR: Please edit this script and update the VM IDs first!"
    echo "1. Login to Proxmox UI: https://192.168.0.7:8006"
    echo "2. Note the VM IDs for bumblebee, prime, and wheeljack"
    echo "3. Edit this script and replace CHANGE_ME with actual VM IDs"
    exit 1
fi

echo "STEP 2: Import Proxmox VMs"
echo "Importing VMs with IDs: bumblebee=$BUMBLEBEE_ID, prime=$PRIME_ID, wheeljack=$WHEELJACK_ID"

terraform import proxmox_virtual_environment_vm.bumblebee pve/$BUMBLEBEE_ID
terraform import proxmox_virtual_environment_vm.prime pve/$PRIME_ID  
terraform import proxmox_virtual_environment_vm.wheeljack pve/$WHEELJACK_ID

echo ""
echo "STEP 3: Import Key Kubernetes Resources"

# Import namespaces (these are usually the first to exist)
echo "Importing namespaces..."
kubectl get namespace monitoring &> /dev/null && terraform import kubernetes_namespace.monitoring monitoring || echo "Skipping monitoring namespace"
kubectl get namespace media &> /dev/null && terraform import kubernetes_namespace.mylar media || echo "Skipping media namespace"


# Import storage class if it exists
echo "Importing storage class..."
kubectl get storageclass nfs-storage &> /dev/null && terraform import kubernetes_storage_class.nfs_storage_class nfs-storage || echo "Skipping nfs-storage storageclass"

echo ""
echo "STEP 4: Verify Import"
echo "Running terraform plan to see remaining resources..."
terraform plan

echo ""
echo "=== Import Complete ==="
echo "Review the plan output above. You may need to:"
echo "1. Import additional resources shown in the plan"
echo "2. Run 'terraform apply' to create missing resources"
echo "3. Use the full import guide (IMPORT_GUIDE.md) for complete import"