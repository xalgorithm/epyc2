#!/bin/bash
set -euxo pipefail

# Kubernetes Control Plane Setup Script
# This script initializes the Kubernetes control plane

LOG_FILE="/var/log/k8s-control-plane-setup.log"
mkdir -p /var/log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Kubernetes control plane setup..."

# Check if cluster is already initialized
if [ -f /etc/kubernetes/admin.conf ]; then
  echo "Kubernetes cluster already initialized, skipping kubeadm init..."
  echo "If you want to reinitialize, run: sudo kubeadm reset -f"
else
  # Initialize Kubernetes cluster
  kubeadm init \
    --pod-network-cidr=${POD_NETWORK_CIDR} \
    --service-cidr=${SERVICE_CIDR} \
    --apiserver-advertise-address=${CONTROL_PLANE_IP} \
    --control-plane-endpoint=${CONTROL_PLANE_IP} \
    --upload-certs
fi

# Set up kubectl for root user
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

# Set up kubectl for regular user
mkdir -p /home/${SSH_USER}/.kube
cp -f /etc/kubernetes/admin.conf /home/${SSH_USER}/.kube/config
chown ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/.kube/config

# Install Flannel CNI (idempotent)
echo "Installing/updating Flannel CNI..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Wait for control plane to be ready
echo "Waiting for control plane to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Generate join command for worker nodes
kubeadm token create --print-join-command > /tmp/kubeadm-join-command.sh
chmod +x /tmp/kubeadm-join-command.sh

echo "Control plane setup completed successfully!"
echo "Join command saved to /tmp/kubeadm-join-command.sh"