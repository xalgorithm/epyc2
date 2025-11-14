#!/usr/bin/env bash
# Full Stack Deployment for Rebellion Cluster
# This script orchestrates the complete deployment of the rebellion cluster

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_phase() {
    echo -e "${CYAN}[PHASE]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Phase tracking
CURRENT_PHASE=0
TOTAL_PHASES=7

# Start time
START_TIME=$(date +%s)

# Progress tracker
show_progress() {
    local phase=$1
    local title=$2
    
    echo ""
    echo "=========================================="
    log_phase "[$phase/$TOTAL_PHASES] $title"
    echo "=========================================="
    echo ""
}

# Elapsed time
show_elapsed() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - START_TIME))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    
    log_info "Elapsed time: ${minutes}m ${seconds}s"
}

# Phase 1: Pre-flight checks
phase1_preflight() {
    show_progress 1 "Pre-Flight Checks"
    
    log_step "Checking prerequisites..."
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed"
        exit 1
    fi
    log_info "✓ Terraform found"
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    log_info "✓ kubectl found"
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed"
        exit 1
    fi
    log_info "✓ Node.js found"
    
    # Check Pulumi
    if ! command -v pulumi &> /dev/null; then
        log_warn "Pulumi not found, will install during Istio phase"
    else
        log_info "✓ Pulumi found"
    fi
    
    # Check SSH key
    if [ ! -f ~/.ssh/id_ed25519 ]; then
        log_error "SSH key not found at ~/.ssh/id_ed25519"
        exit 1
    fi
    log_info "✓ SSH key found"
    
    # Check Proxmox connectivity
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@192.168.0.7 "echo ok" >/dev/null 2>&1; then
        log_error "Cannot connect to Proxmox host"
        exit 1
    fi
    log_info "✓ Proxmox connectivity OK"
    
    log_info "✓ All prerequisites met"
    show_elapsed
}

# Phase 2: Deploy VMs
phase2_deploy_vms() {
    show_progress 2 "Deploy Virtual Machines"
    
    log_step "Deploying Luke, Leia, and Han VMs..."
    
    cd "$PROJECT_DIR"
    
    # Deploy VMs
    "$SCRIPT_DIR/deploy-rebellion-vms.sh"
    
    log_info "✓ VMs deployed successfully"
    show_elapsed
}

# Phase 3: Install Kubernetes
phase3_install_kubernetes() {
    show_progress 3 "Install Kubernetes"
    
    log_step "Installing Kubernetes on all nodes..."
    "$PROJECT_DIR/scripts/rebellion/install-kubernetes.sh"
    
    log_step "Bootstrapping control plane..."
    "$PROJECT_DIR/scripts/rebellion/bootstrap-control-plane.sh"
    
    log_step "Joining worker nodes..."
    "$PROJECT_DIR/scripts/rebellion/join-workers.sh"
    
    log_info "✓ Kubernetes cluster operational"
    show_elapsed
}

# Phase 4: Deploy MetalLB
phase4_deploy_metallb() {
    show_progress 4 "Deploy MetalLB Load Balancer"
    
    log_step "Deploying MetalLB with Terraform..."
    
    cd "$PROJECT_DIR"
    
    terraform apply -auto-approve \
        -target=helm_release.rebellion_metallb \
        -target=kubernetes_manifest.rebellion_metallb_ippool \
        -target=kubernetes_manifest.rebellion_metallb_l2_advertisement
    
    log_info "Waiting for MetalLB to be ready..."
    sleep 30
    
    log_info "✓ MetalLB deployed successfully"
    show_elapsed
}

# Phase 5: Deploy Istio Gateway API
phase5_deploy_istio() {
    show_progress 5 "Deploy Istio Gateway API"
    
    log_step "Deploying Istio with Pulumi..."
    "$PROJECT_DIR/scripts/rebellion/deploy-istio-gateway.sh"
    
    log_info "✓ Istio Gateway API deployed successfully"
    show_elapsed
}

# Phase 6: Bootstrap Flux GitOps
phase6_bootstrap_flux() {
    show_progress 6 "Bootstrap Flux GitOps"
    
    log_step "Bootstrapping Flux..."
    "$PROJECT_DIR/scripts/rebellion/bootstrap-flux.sh"
    
    log_step "Deploying infrastructure manifests..."
    export KUBECONFIG=~/.kube/configs/rebellion-config
    kubectl apply -k "$PROJECT_DIR/flux/rebellion/infrastructure/" || log_warn "Infrastructure manifests will be reconciled by Flux"
    
    log_step "Deploying monitoring stack..."
    kubectl apply -k "$PROJECT_DIR/flux/rebellion/monitoring/" || log_warn "Monitoring manifests will be reconciled by Flux"
    
    log_info "✓ Flux GitOps operational"
    show_elapsed
}

# Phase 7: Deploy monitoring and run tests
phase7_monitoring_and_tests() {
    show_progress 7 "Deploy Monitoring & Run Tests"
    
    log_step "Deploying monitoring integration..."
    
    cd "$PROJECT_DIR"
    
    terraform apply -auto-approve \
        -target=kubernetes_config_map.rebellion_grafana_dashboards \
        -target=kubernetes_config_map.prometheus_rebellion_targets || log_warn "Monitoring integration will be applied when main cluster is accessible"
    
    log_step "Waiting for components to stabilize..."
    sleep 30
    
    log_step "Running end-to-end tests..."
    "$PROJECT_DIR/scripts/rebellion/test-cluster.sh"
    
    log_info "✓ Monitoring deployed and tests completed"
    show_elapsed
}

# Show deployment summary
show_summary() {
    local end_time=$(date +%s)
    local total_elapsed=$((end_time - START_TIME))
    local minutes=$((total_elapsed / 60))
    local seconds=$((total_elapsed % 60))
    
    echo ""
    echo "=========================================="
    log_info "Rebellion Cluster Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "Total deployment time: ${minutes}m ${seconds}s"
    echo ""
    
    log_info "Cluster Information:"
    echo "  Cluster Name: rebellion"
    echo "  Control Plane: Luke (192.168.0.40)"
    echo "  Workers: Leia (192.168.0.41), Han (192.168.0.42)"
    echo "  MetalLB Pool: 192.168.0.43-192.168.0.49"
    echo ""
    
    log_info "Access Commands:"
    echo "  export KUBECONFIG=~/.kube/configs/rebellion-config"
    echo "  kubectl get nodes"
    echo "  kubectl get pods -A"
    echo ""
    
    # Get gateway IP
    export KUBECONFIG=~/.kube/configs/rebellion-config
    local gateway_ip=$(kubectl get svc -n istio-ingress istio-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    
    log_info "Istio Gateway:"
    echo "  IP: $gateway_ip"
    echo "  Test: curl -H \"Host: httpbin.rebellion.local\" http://$gateway_ip/"
    echo ""
    
    log_info "Monitoring:"
    echo "  Grafana: http://grafana.home"
    echo "  Dashboards: Rebellion Cluster Overview, Rebellion Istio Gateway"
    echo ""
    
    log_info "Next Steps:"
    echo "  1. Deploy applications with HTTPRoutes"
    echo "  2. Configure custom monitoring and alerts"
    echo "  3. Set up backups and disaster recovery"
    echo "  4. Review security best practices"
    echo ""
    
    log_info "Documentation:"
    echo "  Setup Guide: docs/deployment/REBELLION_CLUSTER_SETUP.md"
    echo "  Monitoring: docs/monitoring/REBELLION_MONITORING.md"
    echo "  Quick Ref: REBELLION_CLUSTER_SUMMARY.md"
    echo ""
}

# Interactive mode
interactive_mode() {
    echo "=========================================="
    echo "Rebellion Cluster Full Stack Deployment"
    echo "=========================================="
    echo ""
    echo "This script will deploy the complete rebellion cluster:"
    echo "  1. Deploy 3 VMs (Luke, Leia, Han)"
    echo "  2. Install Kubernetes with kubeadm"
    echo "  3. Deploy MetalLB load balancer"
    echo "  4. Deploy Istio Gateway API"
    echo "  5. Bootstrap Flux GitOps"
    echo "  6. Deploy monitoring stack"
    echo "  7. Run end-to-end tests"
    echo ""
    echo "Estimated time: 20-30 minutes"
    echo ""
    
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Deployment cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Skip VM deployment? (if VMs already exist) (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        SKIP_VMS=true
    else
        SKIP_VMS=false
    fi
    
    echo ""
    read -p "Skip Kubernetes installation? (if already installed) (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        SKIP_K8S=true
    else
        SKIP_K8S=false
    fi
}

# Error handler
error_handler() {
    local line_no=$1
    log_error "Deployment failed at line $line_no"
    log_error "Check the error messages above for details"
    show_elapsed
    exit 1
}

trap 'error_handler $LINENO' ERR

# Main execution
main() {
    # Interactive mode
    interactive_mode
    
    echo ""
    log_info "Starting deployment..."
    echo ""
    
    # Phase 1: Pre-flight checks
    phase1_preflight
    
    # Phase 2: Deploy VMs
    if [ "$SKIP_VMS" = false ]; then
        phase2_deploy_vms
    else
        log_warn "Skipping VM deployment"
    fi
    
    # Phase 3: Install Kubernetes
    if [ "$SKIP_K8S" = false ]; then
        phase3_install_kubernetes
    else
        log_warn "Skipping Kubernetes installation"
    fi
    
    # Phase 4: Deploy MetalLB
    phase4_deploy_metallb
    
    # Phase 5: Deploy Istio
    phase5_deploy_istio
    
    # Phase 6: Bootstrap Flux
    phase6_bootstrap_flux
    
    # Phase 7: Monitoring and tests
    phase7_monitoring_and_tests
    
    # Show summary
    show_summary
}

# Run main function
main "$@"

