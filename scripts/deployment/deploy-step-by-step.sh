#!/bin/bash

set -e

echo "📋 Step-by-Step Deployment Script"
echo "================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to wait for user confirmation
wait_for_confirmation() {
    local message="$1"
    echo ""
    print_warning "$message"
    read -p "Press Enter to continue or Ctrl+C to abort..."
}

# Function to check if VMs are accessible
check_vm_accessibility() {
    local vms=("192.168.1.32:prime" "192.168.1.33:bumblebee" "192.168.1.34:wheeljack")
    # Get SSH key path from terraform.tfvars or use default
    local ssh_key=$(grep ssh_private_key_path terraform.tfvars 2>/dev/null | cut -d '"' -f 2 | sed 's|~|'$HOME'|' || echo "$HOME/.ssh/id_ed25519")
    local ssh_user="xalg"
    
    print_status "Checking VM accessibility..."
    
    for vm_info in "${vms[@]}"; do
        local ip=$(echo "$vm_info" | cut -d':' -f1)
        local name=$(echo "$vm_info" | cut -d':' -f2)
        
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$ssh_key" "$ssh_user@$ip" "echo 'SSH test successful'" &>/dev/null; then
            print_success "$name ($ip) is accessible"
        else
            print_error "$name ($ip) is not accessible"
            return 1
        fi
    done
    
    return 0
}

echo "This script deploys the infrastructure in stages to avoid state conflicts."
echo ""

# Step 1: Clean up any existing state issues
print_status "STEP 1: Clean up Terraform state"
echo "================================"
print_status "Removing any stale Kubernetes resources from Terraform state..."

# Remove Kubernetes resources from state (they may be stale)
terraform state list | grep "kubernetes_" | xargs -r terraform state rm 2>/dev/null || true

print_success "State cleanup completed"

# Step 2: Deploy VMs
print_status "STEP 2: Deploy VMs"
echo "=================="
print_status "Creating VMs in Proxmox..."

if terraform apply -target=proxmox_virtual_environment_vm.prime -target=proxmox_virtual_environment_vm.bumblebee -target=proxmox_virtual_environment_vm.wheeljack -auto-approve; then
    print_success "VMs created successfully"
else
    print_error "VM creation failed"
    exit 1
fi

wait_for_confirmation "VMs created. Waiting for them to boot and cloud-init to complete (2-3 minutes)..."

# Step 3: Wait for VMs to be ready
print_status "STEP 3: Wait for VM readiness"
echo "============================="

# Wait for VMs to be accessible
local max_attempts=30
local attempt=1

while [ $attempt -le $max_attempts ]; do
    print_status "Attempt $attempt/$max_attempts: Checking VM accessibility..."
    
    if check_vm_accessibility; then
        print_success "All VMs are accessible"
        break
    else
        if [ $attempt -eq $max_attempts ]; then
            print_error "VMs are not accessible after $max_attempts attempts"
            print_status "Please check VM status in Proxmox web interface"
            exit 1
        fi
        
        print_status "Waiting 30 seconds before next check..."
        sleep 30
        ((attempt++))
    fi
done

# Step 4: Copy SSH keys
print_status "STEP 4: Copy SSH keys to VMs"
echo "============================"
print_status "Copying SSH keys for inter-node communication..."

if ./scripts/copy-ssh-keys.sh; then
    print_success "SSH keys copied successfully"
else
    print_error "SSH key copying failed"
    exit 1
fi

wait_for_confirmation "SSH keys copied. Ready to deploy Kubernetes cluster..."

# Step 5: Deploy Kubernetes cluster
print_status "STEP 5: Deploy Kubernetes cluster"
echo "================================="
print_status "Installing Kubernetes on all nodes..."

if terraform apply -target=null_resource.control_plane_setup -target=null_resource.worker_setup -target=null_resource.copy_kubeconfig -auto-approve; then
    print_success "Kubernetes cluster deployed successfully"
else
    print_error "Kubernetes deployment failed"
    print_status "Check the logs above for specific errors"
    exit 1
fi

# Step 6: Verify cluster
print_status "STEP 6: Verify Kubernetes cluster"
echo "================================="
print_status "Checking cluster status..."

if kubectl get nodes &>/dev/null; then
    print_success "Kubernetes cluster is accessible"
    echo ""
    kubectl get nodes -o wide
else
    print_error "Cannot access Kubernetes cluster"
    print_status "Check kubeconfig and cluster status"
    exit 1
fi

wait_for_confirmation "Kubernetes cluster is ready. Ready to deploy applications..."

# Step 7: Deploy applications
print_status "STEP 7: Deploy applications and monitoring"
echo "=========================================="
print_status "Deploying monitoring, backup, and media services..."

if terraform apply -auto-approve; then
    print_success "Applications deployed successfully"
else
    print_error "Application deployment failed"
    print_status "Some applications may have failed to deploy"
    print_status "You can retry with: terraform apply"
fi

# Step 8: Final verification
print_status "STEP 8: Final verification"
echo "=========================="
print_status "Checking final deployment status..."

echo ""
print_status "Cluster nodes:"
kubectl get nodes -o wide

echo ""
print_status "All namespaces:"
kubectl get ns

echo ""
print_status "Services with LoadBalancer IPs:"
kubectl get svc -A | grep LoadBalancer

echo ""
print_success "Deployment completed! 🎉"
echo ""
print_status "Access your services:"
echo "• Get Grafana IP: kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
echo "• Get Prometheus IP: kubectl get svc prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
echo "• Get Mylar IP: kubectl get svc mylar -n media -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"