#!/bin/bash

set -e

echo "🧹 Cleaning Git History to Remove Sensitive Information"
echo "======================================================"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    log_error "Not in a git repository. Nothing to clean."
    exit 1
fi

log_warning "This will completely remove all git history and create a fresh repository!"
log_warning "This action cannot be undone!"
echo ""
read -p "Are you sure you want to proceed? (type 'YES' to continue): " -r

if [ "$REPLY" != "YES" ]; then
    log_info "Operation cancelled"
    exit 0
fi

log_info "Backing up current branch name..."
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

log_info "Removing all git history..."
rm -rf .git

log_info "Initializing fresh git repository..."
git init

log_info "Setting up initial branch..."
git checkout -b "$CURRENT_BRANCH" 2>/dev/null || git checkout -b main

log_info "Adding all files to new repository..."
git add .

log_info "Creating initial commit..."
git commit -m "Initial commit: Kubernetes Infrastructure on Proxmox

- Complete Infrastructure as Code for Kubernetes on Proxmox
- Monitoring stack with Prometheus, Grafana, Loki, Mimir
- NetAlertX network monitoring
- Comprehensive backup and restore system
- MetalLB load balancer configuration
- Traefik ingress controller
- All sensitive information removed and parameterized"

log_success "Git history cleaned successfully!"
echo ""
log_info "Summary:"
echo "  - All previous commits and history removed"
echo "  - Fresh repository initialized"
echo "  - All files committed to new initial commit"
echo "  - Branch: $CURRENT_BRANCH"
echo ""
log_info "Next steps:"
echo "  1. Review files one more time for any missed sensitive data"
echo "  2. Add remote repository: git remote add origin <your-repo-url>"
echo "  3. Push to remote: git push -u origin $CURRENT_BRANCH"
echo ""
log_warning "Remember: All sensitive data should now be in terraform.tfvars (not committed)"

# Clean up this script
rm -f clean-git-history.sh