#!/usr/bin/env bash
# Bootstrap Rebellion Kubernetes Control Plane
# This script initializes kubeadm on Luke and installs Calico CNI

set -euo pipefail

# Configuration
LUKE_IP="192.168.0.40"
SSH_USER="xalg"
SSH_KEY="~/.ssh/id_ed25519"
POD_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.96.0.0/12"
CLUSTER_NAME="rebellion"
KUBECONFIG_DIR="$HOME/.kube/configs"
KUBECONFIG_FILE="$KUBECONFIG_DIR/rebellion-config"

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

# Initialize control plane
initialize_control_plane() {
    log_step "Initializing control plane on Luke ($LUKE_IP)..."
    
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$LUKE_IP" \
        "POD_CIDR='$POD_CIDR' SERVICE_CIDR='$SERVICE_CIDR' CLUSTER_NAME='$CLUSTER_NAME'" \
        'bash -s' <<'ENDSSH'
set -euo pipefail

echo "[$(date)] Initializing Kubernetes control plane..."

# Check if cluster is already initialized
if [ -f /etc/kubernetes/admin.conf ]; then
    echo "Cluster already initialized, skipping kubeadm init..."
    
    # Ensure kubeconfig is set up for current user
    echo "Setting up kubeconfig..."
    mkdir -p $HOME/.kube
    sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    
    echo "[$(date)] Using existing control plane!"
else
    # Initialize kubeadm
    echo "Running kubeadm init..."
    sudo kubeadm init \
        --pod-network-cidr="$POD_CIDR" \
        --service-cidr="$SERVICE_CIDR" \
        --control-plane-endpoint="$(hostname -I | awk '{print $1}')" \
        --upload-certs

    # Setup kubeconfig for current user
    echo "Setting up kubeconfig..."
    mkdir -p $HOME/.kube
    sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # Verify control plane is running
    echo "Waiting for control plane to be ready..."
    sleep 10
    kubectl wait --for=condition=Ready node/luke --timeout=120s || true

    echo "[$(date)] Control plane initialized successfully!"
fi

ENDSSH
    
    if [ $? -eq 0 ]; then
        log_info "✓ Control plane initialized successfully"
    else
        log_error "✗ Control plane initialization failed"
        return 1
    fi
}

# Install Calico CNI
install_calico() {
    log_step "Installing Calico CNI on Luke..."
    
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$LUKE_IP" \
        "POD_CIDR='$POD_CIDR'" 'bash -s' <<'ENDSSH'
set -euo pipefail

echo "[$(date)] Installing Calico CNI..."

# Check if Calico is already installed
if kubectl get namespace tigera-operator >/dev/null 2>&1; then
    echo "Calico operator namespace already exists, checking installation..."
    
    if kubectl get deployment tigera-operator -n tigera-operator >/dev/null 2>&1; then
        echo "Calico operator already installed, verifying status..."
        kubectl wait --for=condition=Available --timeout=60s deployment/tigera-operator -n tigera-operator || true
    fi
    
    if kubectl get installation default >/dev/null 2>&1; then
        echo "Calico Installation resource already exists, verifying status..."
        kubectl wait --for=condition=Available --timeout=60s deployment/calico-kube-controllers -n calico-system || true
        echo "[$(date)] Calico CNI already configured!"
    else
        echo "Installing Calico Installation resource..."
        # Install Calico custom resources
        cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: $POD_CIDR
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
  registry: quay.io/
EOF
        echo "Waiting for Calico to be ready..."
        sleep 30
        kubectl wait --for=condition=Available --timeout=600s deployment/calico-kube-controllers -n calico-system || true
        echo "[$(date)] Calico CNI installed successfully!"
    fi
else
    echo "Installing Calico operator..."
    # Install Calico operator
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml

    # Wait for operator to be ready
    echo "Waiting for Calico operator..."
    kubectl wait --for=condition=Available --timeout=300s deployment/tigera-operator -n tigera-operator

    # Install Calico custom resources
    echo "Installing Calico Installation resource..."
    cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: $POD_CIDR
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
  registry: quay.io/
EOF

    # Wait for Calico to be ready
    echo "Waiting for Calico to be ready..."
    sleep 30
    kubectl wait --for=condition=Available --timeout=600s deployment/calico-kube-controllers -n calico-system || true

    echo "[$(date)] Calico CNI installed successfully!"
fi

ENDSSH
    
    if [ $? -eq 0 ]; then
        log_info "✓ Calico CNI installed successfully"
    else
        log_error "✗ Calico CNI installation failed"
        return 1
    fi
}

# Copy kubeconfig locally
copy_kubeconfig() {
    log_step "Copying kubeconfig to local machine..."
    
    # Create kubeconfig directory
    mkdir -p "$KUBECONFIG_DIR"
    
    # Copy kubeconfig from Luke
    scp -o StrictHostKeyChecking=no -i "$SSH_KEY" \
        "$SSH_USER@$LUKE_IP:.kube/config" \
        "$KUBECONFIG_FILE"
    
    if [ $? -eq 0 ]; then
        log_info "✓ Kubeconfig copied to $KUBECONFIG_FILE"
        
        # Update context name
        sed -i.bak "s/kubernetes-admin@kubernetes/rebellion-admin@rebellion/g" "$KUBECONFIG_FILE"
        rm -f "${KUBECONFIG_FILE}.bak"
        
        log_info "To use the rebellion cluster, run:"
        echo "  export KUBECONFIG=$KUBECONFIG_FILE"
        echo "  kubectl get nodes"
    else
        log_error "✗ Failed to copy kubeconfig"
        return 1
    fi
}

# Generate join command and save it
generate_join_command() {
    log_step "Generating join command for worker nodes..."
    
    # Get join command from Luke
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$LUKE_IP" \
        "sudo kubeadm token create --print-join-command" > /tmp/rebellion-join-command.sh
    
    if [ $? -eq 0 ]; then
        chmod +x /tmp/rebellion-join-command.sh
        log_info "✓ Join command saved to /tmp/rebellion-join-command.sh"
        log_info "Join command:"
        cat /tmp/rebellion-join-command.sh
    else
        log_error "✗ Failed to generate join command"
        return 1
    fi
}

# Check control plane status
check_status() {
    log_step "Checking control plane status..."
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    echo ""
    log_info "Nodes:"
    kubectl get nodes -o wide || true
    
    echo ""
    log_info "System Pods:"
    kubectl get pods -n kube-system || true
    
    echo ""
    log_info "Calico Pods:"
    kubectl get pods -n calico-system || true
}

# Main execution
main() {
    echo "=========================================="
    echo "Bootstrap Rebellion Control Plane"
    echo "=========================================="
    echo ""
    log_info "Control Plane: Luke ($LUKE_IP)"
    log_info "Pod CIDR: $POD_CIDR"
    log_info "Service CIDR: $SERVICE_CIDR"
    log_info "Cluster Name: $CLUSTER_NAME"
    echo ""
    
    initialize_control_plane
    echo ""
    
    install_calico
    echo ""
    
    copy_kubeconfig
    echo ""
    
    generate_join_command
    echo ""
    
    log_info "Waiting for control plane to stabilize..."
    sleep 20
    
    check_status
    
    echo ""
    echo "=========================================="
    log_info "✓ Control Plane Bootstrap Complete!"
    echo "=========================================="
    echo ""
    log_info "Next steps:"
    echo "  1. Join workers: ./scripts/rebellion/join-workers.sh"
    echo "  2. Verify cluster: export KUBECONFIG=$KUBECONFIG_FILE && kubectl get nodes"
    echo ""
    log_info "Kubeconfig location: $KUBECONFIG_FILE"
    echo ""
}

# Run main function
main "$@"

