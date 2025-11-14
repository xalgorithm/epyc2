#!/usr/bin/env bash
# Install Kubernetes on Rebellion Cluster Nodes
# This script installs containerd, kubeadm, kubelet, and kubectl on all nodes

set -euo pipefail

# Configuration
LUKE_IP="192.168.0.40"
LEIA_IP="192.168.0.41"
HAN_IP="192.168.0.42"
SSH_USER="xalg"
SSH_KEY="~/.ssh/id_ed25519"
K8S_VERSION="1.31" # Kubernetes 1.31 (latest stable)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Install Kubernetes on a node
install_kubernetes_node() {
    local vm_name=$1
    local vm_ip=$2
    
    log_step "Installing Kubernetes on $vm_name ($vm_ip)..."
    
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$vm_ip" 'bash -s' <<'ENDSSH'
set -euo pipefail

echo "[$(date)] Starting Kubernetes installation..."

# Disable swap
echo "Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Load kernel modules
echo "Loading kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Setup required sysctl params
echo "Configuring sysctl parameters..."
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

# Install containerd and dependencies
echo "Installing containerd and dependencies..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https conntrack socat

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --batch --yes -o /etc/apt/keyrings/docker.gpg 2>/dev/null
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y containerd.io

# Configure containerd
echo "Configuring containerd..."
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

# Enable SystemdCgroup
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

# Add Kubernetes repository
echo "Adding Kubernetes repository..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | \
    sudo gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install Kubernetes components
echo "Installing kubeadm, kubelet, and kubectl..."
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Enable kubelet
sudo systemctl enable kubelet

echo "[$(date)] Kubernetes installation completed!"
echo "Installed versions:"
kubeadm version -o short
kubelet --version
kubectl version --client --short 2>/dev/null || kubectl version --client

ENDSSH
    
    if [ $? -eq 0 ]; then
        log_info "✓ Kubernetes installed successfully on $vm_name"
    else
        log_error "✗ Kubernetes installation failed on $vm_name"
        return 1
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "Kubernetes Installation - Rebellion Cluster"
    echo "=========================================="
    echo ""
    log_info "Installing Kubernetes $K8S_VERSION on all nodes..."
    log_info "Nodes: Luke, Leia, Han"
    echo ""
    
    # Install on all nodes
    install_kubernetes_node "luke" "$LUKE_IP"
    echo ""
    install_kubernetes_node "leia" "$LEIA_IP"
    echo ""
    install_kubernetes_node "han" "$HAN_IP"
    
    echo ""
    echo "=========================================="
    log_info "✓ Kubernetes Installation Complete!"
    echo "=========================================="
    echo ""
    log_info "Next steps:"
    echo "  1. Bootstrap control plane: ./scripts/rebellion/bootstrap-control-plane.sh"
    echo "  2. Join workers: ./scripts/rebellion/join-workers.sh"
    echo ""
}

# Run main function
main "$@"

