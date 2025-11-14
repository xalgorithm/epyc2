#!/usr/bin/env bash
# Deploy Istio Gateway API using Pulumi
# This script deploys Istio with Gateway API support to the rebellion cluster

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PULUMI_DIR="$PROJECT_DIR/pulumi/rebellion-cluster"
KUBECONFIG_FILE="$HOME/.kube/configs/rebellion-config"

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

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check if Pulumi is installed
    if ! command -v pulumi &> /dev/null; then
        log_error "Pulumi is not installed. Installing..."
        curl -fsSL https://get.pulumi.com | sh
        export PATH=$PATH:$HOME/.pulumi/bin
    fi

    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js 18+ first."
        exit 1
    fi

    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed. Please install npm first."
        exit 1
    fi

    # Check if kubeconfig exists
    if [ ! -f "$KUBECONFIG_FILE" ]; then
        log_error "Kubeconfig not found at $KUBECONFIG_FILE"
        log_error "Please bootstrap the rebellion cluster first."
        exit 1
    fi

    # Check if cluster is accessible
    if ! kubectl --kubeconfig="$KUBECONFIG_FILE" get nodes >/dev/null 2>&1; then
        log_error "Cannot access rebellion cluster"
        log_error "Please ensure the cluster is running and kubeconfig is correct."
        exit 1
    fi

    log_info "✓ Prerequisites check passed"
}

# Install npm dependencies
install_dependencies() {
    log_step "Installing npm dependencies..."
    
    cd "$PULUMI_DIR"
    
    if [ ! -d "node_modules" ]; then
        npm install
    else
        log_info "Dependencies already installed"
    fi
    
    log_info "✓ Dependencies installed"
}

# Initialize Pulumi stack
initialize_pulumi() {
    log_step "Initializing Pulumi stack..."
    
    cd "$PULUMI_DIR"
    
    # Login to local backend
    pulumi login --local
    
    # Check if stack exists
    if pulumi stack select rebellion 2>/dev/null; then
        log_info "Using existing stack: rebellion"
    else
        log_info "Creating new stack: rebellion"
        pulumi stack init rebellion
    fi
    
    # Set kubeconfig path
    pulumi config set kubernetes:kubeconfig "$KUBECONFIG_FILE"
    
    log_info "✓ Pulumi initialized"
}

# Deploy Istio
deploy_istio() {
    log_step "Deploying Istio Gateway API..."
    
    cd "$PULUMI_DIR"
    
    # Set environment variable for kubeconfig
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    echo ""
    log_info "Running: pulumi up"
    echo ""
    
    pulumi up --yes
    
    if [ $? -eq 0 ]; then
        log_info "✓ Istio Gateway API deployed successfully"
    else
        log_error "✗ Istio deployment failed"
        exit 1
    fi
}

# Show deployment info
show_info() {
    log_step "Getting deployment information..."
    
    cd "$PULUMI_DIR"
    
    echo ""
    log_info "Deployment Outputs:"
    pulumi stack output
    
    echo ""
    log_info "Gateway IP:"
    GATEWAY_IP=$(pulumi stack output gatewayIP 2>/dev/null || echo "pending")
    echo "  $GATEWAY_IP"
    
    echo ""
    log_info "Test Command:"
    echo "  curl -H \"Host: httpbin.rebellion.local\" http://$GATEWAY_IP/"
    
    echo ""
    log_info "Or add to /etc/hosts:"
    echo "  echo \"$GATEWAY_IP httpbin.rebellion.local\" | sudo tee -a /etc/hosts"
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    echo ""
    log_info "Istio System Pods:"
    kubectl get pods -n istio-system
    
    echo ""
    log_info "Istio Ingress Pods:"
    kubectl get pods -n istio-ingress
    
    echo ""
    log_info "Gateway Resources:"
    kubectl get gateway -A
    
    echo ""
    log_info "HTTPRoute Resources:"
    kubectl get httproute -A
    
    echo ""
    log_info "Gateway Service:"
    kubectl get svc -n istio-ingress
}

# Main execution
main() {
    echo "=========================================="
    echo "Deploy Istio Gateway API"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    echo ""
    
    install_dependencies
    echo ""
    
    initialize_pulumi
    echo ""
    
    deploy_istio
    echo ""
    
    show_info
    echo ""
    
    verify_deployment
    
    echo ""
    echo "=========================================="
    log_info "✓ Istio Gateway API Deployment Complete!"
    echo "=========================================="
    echo ""
    log_info "Next steps:"
    echo "  1. Bootstrap Flux: ./scripts/rebellion/bootstrap-flux.sh"
    echo "  2. Test the gateway with the test command above"
    echo "  3. Deploy your applications with HTTPRoute resources"
    echo ""
    log_info "Pulumi commands:"
    echo "  cd $PULUMI_DIR"
    echo "  pulumi stack output    # View outputs"
    echo "  pulumi refresh         # Refresh state"
    echo "  pulumi destroy         # Remove Istio"
    echo ""
}

# Run main function
main "$@"

