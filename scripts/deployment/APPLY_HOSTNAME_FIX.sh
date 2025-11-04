#!/bin/bash
# Apply Permanent Hostname Fix
# This script updates the cloud-init files in Proxmox to prevent hostname collisions

set -e

echo "==================================================================="
echo "Applying Permanent Hostname Fix for Kubernetes Cluster VMs"
echo "==================================================================="
echo ""
echo "This will create/update three cloud-init files in Proxmox:"
echo "  - cloud-init-bumblebee.yaml (control plane)"
echo "  - cloud-init-prime.yaml (worker 1)"
echo "  - cloud-init-wheeljack.yaml (worker 2)"
echo ""
echo "Each file sets a unique hostname for its respective VM."
echo ""
echo "IMPORTANT: This will NOT affect existing running VMs."
echo "           Cloud-init only runs on first boot."
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

echo ""
echo "Running terraform apply..."
echo ""

terraform apply \
  -target=proxmox_virtual_environment_file.cloud_init_bumblebee \
  -target=proxmox_virtual_environment_file.cloud_init_prime \
  -target=proxmox_virtual_environment_file.cloud_init_wheeljack

echo ""
echo "==================================================================="
echo "Cloud-init files updated successfully!"
echo "==================================================================="
echo ""
echo "Verification:"
echo "  terraform state list | grep cloud_init"
echo ""
echo "On Proxmox host:"
echo "  ls -la /var/lib/vz/snippets/cloud-init-*.yaml"
echo ""
echo "Future VM deployments will now have correct hostnames from first boot."
echo ""

