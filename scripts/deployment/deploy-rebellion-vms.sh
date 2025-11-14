#!/usr/bin/env bash
# Deploy Rebellion Cluster VMs
# This script deploys Luke, Leia, and Han VMs using Terraform

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROXMOX_HOST="${PROXMOX_HOST:-192.168.0.7}"
PROXMOX_USER="${PROXMOX_USER:-root}"

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

    # Check if SSH key exists
    if [ ! -f ~/.ssh/id_ed25519 ]; then
        log_error "SSH key ~/.ssh/id_ed25519 not found"
        exit 1
    fi

    log_info "✓ Prerequisites check passed"
}

# Check if Ubuntu template exists
check_template() {
    log_step "Checking for Ubuntu 22.04 template (VM ID 9000)..."

    if ! ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "qm status 9000" >/dev/null 2>&1; then
        log_error "Ubuntu 22.04 template (VM ID 9000) not found!"
        log_error "Please create the template first."
        exit 1
    else
        log_info "✓ Ubuntu 22.04 template found"
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
    log_info "Running: terraform plan for rebellion VMs"
    echo ""
    
    terraform plan \
        -target=proxmox_virtual_environment_file.cloud_init_luke \
        -target=proxmox_virtual_environment_file.cloud_init_leia \
        -target=proxmox_virtual_environment_file.cloud_init_han \
        -target=proxmox_virtual_environment_vm.luke \
        -target=proxmox_virtual_environment_vm.leia \
        -target=proxmox_virtual_environment_vm.han
    
    echo ""
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Deployment cancelled by user"
        exit 0
    fi
}

# Deploy VMs
deploy_vms() {
    log_step "Deploying Rebellion cluster VMs..."
    cd "$PROJECT_DIR"
    
    echo ""
    terraform apply -auto-approve \
        -target=proxmox_virtual_environment_file.cloud_init_luke \
        -target=proxmox_virtual_environment_file.cloud_init_leia \
        -target=proxmox_virtual_environment_file.cloud_init_han \
        -target=proxmox_virtual_environment_vm.luke \
        -target=proxmox_virtual_environment_vm.leia \
        -target=proxmox_virtual_environment_vm.han
    
    if [ $? -eq 0 ]; then
        log_info "✓ VMs deployed successfully"
    else
        log_error "VM deployment failed"
        exit 1
    fi
}

# Wait for VMs to be ready
wait_for_vms() {
    log_step "Waiting for VMs to initialize (this may take 3-5 minutes)..."
    
    local vms=("192.168.0.40:luke" "192.168.0.41:leia" "192.168.0.42:han")
    local max_attempts=60
    local ready_count=0
    
    echo ""
    log_info "Waiting for VMs to respond to ping..."
    
    for vm_info in "${vms[@]}"; do
        IFS=':' read -r ip name <<< "$vm_info"
        local attempt=0
        
        echo -n "Waiting for $name ($ip)... "
        while [ $attempt -lt $max_attempts ]; do
            if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
                echo "✓"
                ((ready_count++))
                break
            fi
            
            attempt=$((attempt + 1))
            sleep 2
        done
        
        if [ $attempt -eq $max_attempts ]; then
            echo "✗ (timeout)"
            log_warn "$name did not respond to ping within expected time"
        fi
    done
    
    if [ $ready_count -eq 3 ]; then
        log_info "✓ All VMs are responding"
    else
        log_warn "Some VMs are not responding yet"
    fi
    
    # Wait for SSH
    log_info "Waiting for SSH to be ready on all VMs..."
    sleep 30
    
    for vm_info in "${vms[@]}"; do
        IFS=':' read -r ip name <<< "$vm_info"
        local attempt=0
        
        echo -n "Waiting for SSH on $name ($ip)... "
        while [ $attempt -lt 30 ]; do
            if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o BatchMode=yes \
                "xalg@$ip" "echo 'ok'" >/dev/null 2>&1; then
                echo "✓"
                break
            fi
            
            attempt=$((attempt + 1))
            sleep 3
        done
        
        if [ $attempt -eq 30 ]; then
            echo "✗ (timeout)"
            log_warn "SSH not ready on $name yet. Cloud-init may still be running."
        fi
    done
}

# Run validation tests
run_tests() {
    log_step "Running validation tests..."
    
    if [ -f "$SCRIPT_DIR/test-rebellion-vms.sh" ]; then
        echo ""
        "$SCRIPT_DIR/test-rebellion-vms.sh"
    else
        log_warn "Test script not found, skipping validation"
    fi
}

# Show connection info
show_connection_info() {
    echo ""
    echo "=========================================="
    log_info "Rebellion Cluster VMs Deployed!"
    echo "=========================================="
    echo ""
    echo "VM Details:"
    echo "  Luke (Control Plane):"
    echo "    IP:     192.168.0.40"
    echo "    VM ID:  120"
    echo "    SSH:    ssh xalg@192.168.0.40"
    echo ""
    echo "  Leia (Worker 1):"
    echo "    IP:     192.168.0.41"
    echo "    VM ID:  121"
    echo "    SSH:    ssh xalg@192.168.0.41"
    echo ""
    echo "  Han (Worker 2):"
    echo "    IP:     192.168.0.42"
    echo "    VM ID:  122"
    echo "    SSH:    ssh xalg@192.168.0.42"
    echo ""
    echo "Next Steps:"
    echo "  1. Wait for cloud-init to complete (if tests failed)"
    echo "  2. Install Kubernetes: ./scripts/rebellion/install-kubernetes.sh"
    echo "  3. Bootstrap control plane: ./scripts/rebellion/bootstrap-control-plane.sh"
    echo "  4. Join workers: ./scripts/rebellion/join-workers.sh"
    echo ""
    echo "View VM info in Terraform:"
    echo "  terraform output rebellion_vm_info"
    echo ""
}

# Main execution
main() {
    echo "=========================================="
    echo "Rebellion Cluster VM Deployment"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    check_template
    init_terraform
    validate_terraform
    plan_deployment
    deploy_vms
    wait_for_vms
    
    echo ""
    log_info "Waiting additional 30 seconds for cloud-init to complete..."
    sleep 30
    
    run_tests
    show_connection_info
}

# Run main function
main "$@"

