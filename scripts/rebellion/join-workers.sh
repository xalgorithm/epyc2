#!/usr/bin/env bash
# Join Worker Nodes to Rebellion Cluster
# This script joins Leia and Han to the Kubernetes cluster

set -euo pipefail

# Configuration
LUKE_IP="192.168.0.40"
LEIA_IP="192.168.0.41"
HAN_IP="192.168.0.42"
SSH_USER="xalg"
SSH_KEY="~/.ssh/id_ed25519"
KUBECONFIG_FILE="$HOME/.kube/configs/rebellion-config"
JOIN_CMD_FILE="/tmp/rebellion-join-command.sh"

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

# Get join command from control plane
get_join_command() {
    log_step "Getting join command from control plane..."
    
    if [ -f "$JOIN_CMD_FILE" ]; then
        log_info "Using existing join command from $JOIN_CMD_FILE"
    else
        log_info "Generating new join command..."
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$LUKE_IP" \
            "sudo kubeadm token create --print-join-command" > "$JOIN_CMD_FILE"
        
        if [ $? -ne 0 ]; then
            log_error "Failed to get join command from control plane"
            return 1
        fi
    fi
    
    chmod +x "$JOIN_CMD_FILE"
    log_info "Join command:"
    cat "$JOIN_CMD_FILE"
}

# Join a worker node
join_worker() {
    local vm_name=$1
    local vm_ip=$2
    
    log_step "Joining $vm_name ($vm_ip) to the cluster..."
    
    # Check if node is already in the cluster
    export KUBECONFIG="$KUBECONFIG_FILE"
    if kubectl get node "$vm_name" >/dev/null 2>&1; then
        log_info "✓ $vm_name is already in the cluster, skipping join"
        return 0
    fi
    
    # Get join command
    local join_cmd=$(cat "$JOIN_CMD_FILE")
    
    # Execute join command on worker
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$vm_ip" \
        "JOIN_CMD='$join_cmd'" 'bash -s' <<'ENDSSH'
set -euo pipefail

echo "[$(date)] Joining worker node to cluster..."

# Check if already joined by checking for kubelet.conf
if [ -f /etc/kubernetes/kubelet.conf ]; then
    echo "Node is already joined to a cluster, skipping join..."
    echo "[$(date)] Using existing cluster membership!"
else
    # Execute kubeadm join
    echo "Running: $JOIN_CMD"
    sudo $JOIN_CMD
    echo "[$(date)] Worker node joined successfully!"
fi

ENDSSH
    
    if [ $? -eq 0 ]; then
        log_info "✓ $vm_name joined successfully"
    else
        log_error "✗ Failed to join $vm_name"
        return 1
    fi
}

# Label worker nodes
label_workers() {
    log_step "Labeling worker nodes..."
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    # Wait for nodes to appear
    sleep 10
    
    # Label Leia
    kubectl label node leia node-role.kubernetes.io/worker=worker --overwrite || true
    log_info "✓ Labeled leia as worker"
    
    # Label Han
    kubectl label node han node-role.kubernetes.io/worker=worker --overwrite || true
    log_info "✓ Labeled han as worker"
}

# Verify cluster
verify_cluster() {
    log_step "Verifying cluster status..."
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    echo ""
    log_info "Waiting for all nodes to be Ready..."
    sleep 20
    
    echo ""
    log_info "Cluster Nodes:"
    kubectl get nodes -o wide
    
    echo ""
    log_info "System Pods:"
    kubectl get pods -n kube-system -o wide
    
    echo ""
    log_info "Calico Pods:"
    kubectl get pods -n calico-system -o wide
    
    echo ""
    log_info "Node Status:"
    kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name): \(.status.conditions[] | select(.type=="Ready") | .status)"' || kubectl get nodes
}

# Main execution
main() {
    echo "=========================================="
    echo "Join Worker Nodes to Rebellion Cluster"
    echo "=========================================="
    echo ""
    log_info "Control Plane: Luke ($LUKE_IP)"
    log_info "Workers: Leia ($LEIA_IP), Han ($HAN_IP)"
    echo ""
    
    # Check if kubeconfig exists
    if [ ! -f "$KUBECONFIG_FILE" ]; then
        log_error "Kubeconfig not found at $KUBECONFIG_FILE"
        log_error "Please run bootstrap-control-plane.sh first"
        exit 1
    fi
    
    get_join_command
    echo ""
    
    join_worker "leia" "$LEIA_IP"
    echo ""
    
    join_worker "han" "$HAN_IP"
    echo ""
    
    label_workers
    echo ""
    
    verify_cluster
    
    echo ""
    echo "=========================================="
    log_info "✓ Worker Nodes Joined Successfully!"
    echo "=========================================="
    echo ""
    log_info "Cluster is ready! All 3 nodes joined:"
    echo "  - Luke (control-plane)"
    echo "  - Leia (worker)"
    echo "  - Han (worker)"
    echo ""
    log_info "To use the cluster:"
    echo "  export KUBECONFIG=$KUBECONFIG_FILE"
    echo "  kubectl get nodes"
    echo "  kubectl get pods -A"
    echo ""
    log_info "Next steps:"
    echo "  1. Install MetalLB: terraform apply -target=helm_release.rebellion_metallb"
    echo "  2. Install Istio Gateway: cd pulumi/rebellion-cluster && pulumi up"
    echo "  3. Bootstrap Flux: ./scripts/rebellion/bootstrap-flux.sh"
    echo ""
}

# Run main function
main "$@"

