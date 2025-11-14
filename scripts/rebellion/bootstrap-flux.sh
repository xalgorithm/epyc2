#!/usr/bin/env bash
# Bootstrap Flux GitOps for Rebellion Cluster
# This script installs and configures Flux on the rebellion cluster

set -euo pipefail

# Configuration
KUBECONFIG_FILE="$HOME/.kube/configs/rebellion-config"
FLUX_VERSION="v2.2.3"
FLUX_NAMESPACE="flux-system"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FLUX_DIR="$PROJECT_DIR/flux/rebellion"

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

    # Check if kubeconfig exists
    if [ ! -f "$KUBECONFIG_FILE" ]; then
        log_error "Kubeconfig not found at $KUBECONFIG_FILE"
        exit 1
    fi

    # Check if cluster is accessible
    if ! kubectl --kubeconfig="$KUBECONFIG_FILE" get nodes >/dev/null 2>&1; then
        log_error "Cannot access rebellion cluster"
        exit 1
    fi

    log_info "✓ Prerequisites check passed"
}

# Install Flux CLI
install_flux_cli() {
    log_step "Checking Flux CLI..."

    if command -v flux &> /dev/null; then
        local current_version=$(flux version --client 2>/dev/null | grep 'flux' | head -1)
        log_info "✓ Flux CLI already installed: $current_version"
    else
        log_error "Flux CLI not found. Please install it:"
        echo "  macOS:   brew install fluxcd/tap/flux"
        echo "  Linux:   curl -s https://fluxcd.io/install.sh | sudo bash"
        exit 1
    fi
}

# Check Flux prerequisites
check_flux_prerequisites() {
    log_step "Checking Flux prerequisites..."
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    flux check --pre
    
    if [ $? -eq 0 ]; then
        log_info "✓ Cluster meets Flux requirements"
    else
        log_error "✗ Cluster does not meet Flux requirements"
        exit 1
    fi
}

# Prompt for Git repository
get_git_repo() {
    log_step "Git repository configuration..."
    
    echo ""
    log_info "Flux requires a Git repository to store manifests."
    log_info "You can use this repository or a separate one."
    echo ""
    
    read -p "Enter Git repository URL (leave empty to skip Git sync): " GIT_REPO_URL
    
    if [ -z "$GIT_REPO_URL" ]; then
        log_warn "No Git repository provided. Flux will be installed without Git sync."
        log_warn "You'll need to manually configure GitRepository source later."
        USE_GIT=false
    else
        USE_GIT=true
        
        read -p "Enter Git branch [main]: " GIT_BRANCH
        GIT_BRANCH=${GIT_BRANCH:-main}
        
        read -p "Enter path in repository [flux/rebellion]: " GIT_PATH
        GIT_PATH=${GIT_PATH:-flux/rebellion}
        
        log_info "Git Configuration:"
        echo "  Repository: $GIT_REPO_URL"
        echo "  Branch: $GIT_BRANCH"
        echo "  Path: $GIT_PATH"
    fi
}

# Install Flux without Git bootstrap
install_flux_standalone() {
    log_step "Installing Flux (standalone mode)..."
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    flux install --namespace="$FLUX_NAMESPACE"
    
    if [ $? -eq 0 ]; then
        log_info "✓ Flux installed successfully"
    else
        log_error "✗ Flux installation failed"
        exit 1
    fi
}

# Bootstrap Flux with Git
bootstrap_flux_git() {
    log_step "Bootstrapping Flux with Git..."
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    log_info "This requires Git credentials. Please ensure you have:"
    log_info "  - GitHub: GITHUB_TOKEN environment variable"
    log_info "  - GitLab: GITLAB_TOKEN environment variable"
    log_info "  - Generic: Git credentials configured"
    echo ""
    
    read -p "Press Enter to continue or Ctrl+C to cancel..."
    
    flux bootstrap generic \
        --url="$GIT_REPO_URL" \
        --branch="$GIT_BRANCH" \
        --path="$GIT_PATH" \
        --namespace="$FLUX_NAMESPACE"
    
    if [ $? -eq 0 ]; then
        log_info "✓ Flux bootstrapped with Git"
    else
        log_error "✗ Flux bootstrap failed"
        log_warn "Falling back to standalone installation..."
        install_flux_standalone
    fi
}

# Wait for Flux to be ready
wait_for_flux() {
    log_step "Waiting for Flux to be ready..."
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    kubectl wait --for=condition=Available --timeout=300s \
        deployment/source-controller -n "$FLUX_NAMESPACE"
    
    kubectl wait --for=condition=Available --timeout=300s \
        deployment/kustomize-controller -n "$FLUX_NAMESPACE"
    
    kubectl wait --for=condition=Available --timeout=300s \
        deployment/helm-controller -n "$FLUX_NAMESPACE"
    
    kubectl wait --for=condition=Available --timeout=300s \
        deployment/notification-controller -n "$FLUX_NAMESPACE"
    
    log_info "✓ Flux is ready"
}

# Create Flux directory structure
create_flux_structure() {
    log_step "Creating Flux directory structure..."
    
    mkdir -p "$FLUX_DIR/infrastructure/sources"
    mkdir -p "$FLUX_DIR/infrastructure/base"
    mkdir -p "$FLUX_DIR/apps"
    mkdir -p "$FLUX_DIR/monitoring"
    
    log_info "✓ Directory structure created at $FLUX_DIR"
}

# Verify Flux installation
verify_flux() {
    log_step "Verifying Flux installation..."
    
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    echo ""
    log_info "Flux version:"
    flux version
    
    echo ""
    log_info "Flux components:"
    kubectl get pods -n "$FLUX_NAMESPACE"
    
    echo ""
    log_info "Flux status:"
    flux check
}

# Show next steps
show_next_steps() {
    echo ""
    echo "=========================================="
    log_info "✓ Flux Bootstrap Complete!"
    echo "=========================================="
    echo ""
    log_info "Flux is now running on the rebellion cluster"
    echo ""
    log_info "Next steps:"
    echo "  1. Add HelmRepository sources:"
    echo "     kubectl --kubeconfig $KUBECONFIG_FILE apply -f flux/rebellion/infrastructure/sources/"
    echo ""
    echo "  2. Deploy infrastructure components:"
    echo "     kubectl --kubeconfig $KUBECONFIG_FILE apply -f flux/rebellion/infrastructure/"
    echo ""
    echo "  3. Monitor Flux reconciliation:"
    echo "     flux --kubeconfig $KUBECONFIG_FILE get sources git"
    echo "     flux --kubeconfig $KUBECONFIG_FILE get helmreleases -A"
    echo "     flux --kubeconfig $KUBECONFIG_FILE logs --follow"
    echo ""
    log_info "Flux directory: $FLUX_DIR"
    log_info "Manifests will be created in the next steps"
    echo ""
}

# Main execution
main() {
    echo "=========================================="
    echo "Bootstrap Flux GitOps - Rebellion Cluster"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    echo ""
    
    install_flux_cli
    echo ""
    
    check_flux_prerequisites
    echo ""
    
    get_git_repo
    echo ""
    
    if [ "$USE_GIT" = true ]; then
        bootstrap_flux_git
    else
        install_flux_standalone
    fi
    
    echo ""
    wait_for_flux
    echo ""
    
    create_flux_structure
    echo ""
    
    verify_flux
    
    show_next_steps
}

# Run main function
main "$@"

