#!/usr/bin/env bash
# Deploy work.xalg.im VM
# This script automates the deployment of the work VM

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROXMOX_HOST="${PROXMOX_HOST:-192.168.0.7}"
PROXMOX_USER="${PROXMOX_USER:-root}"
DEBIAN_TEMPLATE_ID=9001
WORK_VM_IP="192.168.0.50"

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

    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install it first."
        exit 1
    fi

    # Check if we're in the right directory
    if [ ! -f "$PROJECT_DIR/terraform.tfvars" ]; then
        log_error "terraform.tfvars not found. Are you in the correct directory?"
        exit 1
    fi

    # Check SSH connectivity to Proxmox
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$PROXMOX_USER@$PROXMOX_HOST" "echo 'ok'" >/dev/null 2>&1; then
        log_error "Cannot connect to Proxmox host $PROXMOX_HOST"
        exit 1
    fi

    log_info "✓ Prerequisites check passed"
}

# Check if Debian template exists
check_debian_template() {
    log_step "Checking for Debian 13 template (VM ID $DEBIAN_TEMPLATE_ID)..."

    if ! ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "qm status $DEBIAN_TEMPLATE_ID" >/dev/null 2>&1; then
        log_warn "Debian 13 template (VM ID $DEBIAN_TEMPLATE_ID) not found!"
        echo ""
        read -p "Would you like to create it now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Creating Debian 13 template..."
            "$SCRIPT_DIR/create-debian-template.sh"
        else
            log_error "Cannot proceed without Debian template. Please create it first with:"
            log_error "  $SCRIPT_DIR/create-debian-template.sh"
            exit 1
        fi
    else
        log_info "✓ Debian 13 template found"
    fi
}

# Initialize Terraform
init_terraform() {
    log_step "Initializing Terraform..."
    cd "$PROJECT_DIR"
    
    if ! terraform init -upgrade >/dev/null 2>&1; then
        log_error "Terraform initialization failed"
        exit 1
    fi
    
    log_info "✓ Terraform initialized"
}

# Validate Terraform configuration
validate_terraform() {
    log_step "Validating Terraform configuration..."
    cd "$PROJECT_DIR"
    
    if ! terraform validate; then
        log_error "Terraform validation failed"
        exit 1
    fi
    
    log_info "✓ Terraform configuration valid"
}

# Plan deployment
plan_deployment() {
    log_step "Planning deployment..."
    cd "$PROJECT_DIR"
    
    echo ""
    log_info "Running: terraform plan -target=proxmox_virtual_environment_file.cloud_init_work -target=proxmox_virtual_environment_vm.work"
    echo ""
    
    terraform plan \
        -target=proxmox_virtual_environment_file.cloud_init_work \
        -target=proxmox_virtual_environment_vm.work
    
    echo ""
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Deployment cancelled by user"
        exit 0
    fi
}

# Deploy VM
deploy_vm() {
    log_step "Deploying work.xalg.im VM..."
    cd "$PROJECT_DIR"
    
    echo ""
    terraform apply -auto-approve \
        -target=proxmox_virtual_environment_file.cloud_init_work \
        -target=proxmox_virtual_environment_vm.work
    
    if [ $? -eq 0 ]; then
        log_info "✓ VM deployed successfully"
    else
        log_error "VM deployment failed"
        exit 1
    fi
}

# Wait for VM to be ready
wait_for_vm() {
    log_step "Waiting for VM to be ready..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if ping -c 1 -W 2 "$WORK_VM_IP" >/dev/null 2>&1; then
            log_info "✓ VM is responding to ping"
            break
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_warn "VM did not respond to ping within expected time"
        log_warn "It may still be initializing. Check with: ssh xalg@$WORK_VM_IP"
        return 1
    fi
    
    # Wait for SSH
    log_info "Waiting for SSH to be ready..."
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o BatchMode=yes "xalg@$WORK_VM_IP" "echo 'ok'" >/dev/null 2>&1; then
            log_info "✓ SSH is ready"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 3
    done
    
    log_warn "SSH not ready yet. Cloud-init may still be running."
    log_info "Try connecting manually: ssh xalg@$WORK_VM_IP"
    return 1
}

# Verify VM configuration
verify_vm() {
    log_step "Verifying VM configuration..."
    
    if ! ping -c 1 -W 2 "$WORK_VM_IP" >/dev/null 2>&1; then
        log_warn "Cannot ping VM yet. Skipping verification."
        return 1
    fi
    
    log_info "Connecting to VM to verify configuration..."
    
    # Try to verify, but don't fail if SSH isn't ready yet
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "xalg@$WORK_VM_IP" bash <<'EOF' 2>/dev/null; then
echo "Hostname: $(hostname -f)"
echo "NFS mount: $(df -h | grep '/data' || echo 'Not mounted yet')"
echo "Installed packages:"
dpkg -l | grep -E "nfs-common|hstr|openssh-server" | awk '{print "  - " $2 " " $3}'
echo "QEMU guest agent: $(systemctl is-active qemu-guest-agent || echo 'not running')"
EOF
        log_info "✓ VM verification complete"
        return 0
    else
        log_warn "Could not verify VM configuration yet (SSH/cloud-init may still be initializing)"
        return 1
    fi
}

# Show connection info
show_connection_info() {
    echo ""
    echo "=========================================="
    log_info "Work VM Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "VM Details:"
    echo "  Name:       work"
    echo "  FQDN:       work.xalg.im"
    echo "  IP:         $WORK_VM_IP"
    echo "  VM ID:      110"
    echo "  User:       xalg"
    echo "  NFS Mount:  192.168.0.7:/data -> /data"
    echo ""
    echo "Connect to your VM:"
    echo "  ssh xalg@$WORK_VM_IP"
    echo ""
    echo "Verify configuration:"
    echo "  ssh xalg@$WORK_VM_IP 'hostname -f && df -h | grep /data'"
    echo ""
    echo "View VM in Terraform:"
    echo "  terraform output vm_info"
    echo ""
    
    if ! ping -c 1 -W 2 "$WORK_VM_IP" >/dev/null 2>&1; then
        log_warn "Note: VM is not responding yet. Cloud-init may still be running."
        log_warn "Wait a few minutes and try: ssh xalg@$WORK_VM_IP"
    fi
}

# Main execution
main() {
    echo "======================================"
    echo "Work VM Deployment Script"
    echo "======================================"
    echo ""
    
    check_prerequisites
    check_debian_template
    init_terraform
    validate_terraform
    plan_deployment
    deploy_vm
    
    echo ""
    log_info "Waiting for VM to initialize (this may take 2-3 minutes)..."
    sleep 10
    
    if wait_for_vm; then
        verify_vm
    fi
    
    show_connection_info
}

# Run main function
main "$@"

