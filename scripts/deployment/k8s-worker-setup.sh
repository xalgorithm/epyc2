#!/bin/bash
set -euxo pipefail

# Kubernetes Worker Node Setup Script
# This script joins worker nodes to the Kubernetes cluster

LOG_FILE="/var/log/k8s-worker-setup.log"
mkdir -p /var/log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Kubernetes worker node setup..."

# Check if node is already joined to the cluster
if [ -f /etc/kubernetes/kubelet.conf ]; then
  echo "Node already joined to cluster, skipping kubeadm join..."
  echo "If you want to rejoin, run: sudo kubeadm reset -f && reboot"
else
  # Verify SSH key exists
  if [ ! -f "${SSH_PRIVATE_KEY_PATH}" ]; then
    echo "ERROR: SSH private key not found at ${SSH_PRIVATE_KEY_PATH}"
    exit 1
  fi
  
  # Verify SSH key permissions
  chmod 600 ${SSH_PRIVATE_KEY_PATH}
  
  # Test SSH connectivity to control plane
  echo "Testing SSH connectivity to control plane ${CONTROL_PLANE_IP}..."
  if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${SSH_PRIVATE_KEY_PATH} ${SSH_USER}@${CONTROL_PLANE_IP} "echo 'SSH connection successful'"; then
    echo "ERROR: Cannot SSH to control plane at ${CONTROL_PLANE_IP}"
    echo "Please verify:"
    echo "  1. Control plane is accessible"
    echo "  2. SSH key is correct"
    echo "  3. User ${SSH_USER} exists on control plane"
    exit 1
  fi
  
  # Get the join command from control plane
  echo "Retrieving join command from control plane..."
  if ! scp -o StrictHostKeyChecking=no -i ${SSH_PRIVATE_KEY_PATH} ${SSH_USER}@${CONTROL_PLANE_IP}:/tmp/kubeadm-join-command.sh /tmp/kubeadm-join-command.sh; then
    echo "ERROR: Failed to retrieve join command from control plane"
    echo "Checking if join command exists on control plane..."
    ssh -o StrictHostKeyChecking=no -i ${SSH_PRIVATE_KEY_PATH} ${SSH_USER}@${CONTROL_PLANE_IP} "ls -la /tmp/kubeadm-join-command.sh" || echo "Join command file not found on control plane!"
    exit 1
  fi

  # Make sure the join command is executable
  chmod +x /tmp/kubeadm-join-command.sh
  
  # Show the join command (for debugging)
  echo "Join command content:"
  cat /tmp/kubeadm-join-command.sh

  # Join the cluster
  echo "Joining the Kubernetes cluster..."
  /tmp/kubeadm-join-command.sh
fi

echo "Worker node setup completed successfully!"
echo "Node should now be part of the Kubernetes cluster."