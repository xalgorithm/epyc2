#!/bin/bash

echo "✈️  Pre-Flight Check"
echo "=================="

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
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

ISSUES=0

echo "Checking prerequisites for Terraform deployment..."
echo ""

# Check 1: Terraform configuration
print_status "1. Checking Terraform configuration..."
if terraform validate &>/dev/null; then
    print_success "Terraform configuration is valid"
else
    print_error "Terraform configuration has errors"
    terraform validate
    ((ISSUES++))
fi

# Check 2: SSH keys
print_status "2. Checking SSH keys..."
# Get SSH key path from terraform.tfvars or use default
SSH_KEY=$(grep ssh_private_key_path terraform.tfvars 2>/dev/null | cut -d '"' -f 2 | sed 's|~|'$HOME'|' || echo "$HOME/.ssh/id_ed25519")
SSH_KEY_EXPANDED="${SSH_KEY/#\~/$HOME}"

if [ -f "$SSH_KEY_EXPANDED" ]; then
    print_success "SSH private key found"
    
    if [ -f "$SSH_KEY_EXPANDED.pub" ]; then
        print_success "SSH public key found"
    else
        print_error "SSH public key missing"
        echo "  Generate with: ssh-keygen -y -f $SSH_KEY_EXPANDED > $SSH_KEY_EXPANDED.pub"
        ((ISSUES++))
    fi
    
    # Check permissions
    PERMS=$(stat -f "%A" "$SSH_KEY_EXPANDED" 2>/dev/null || stat -c "%a" "$SSH_KEY_EXPANDED" 2>/dev/null)
    if [ "$PERMS" = "600" ]; then
        print_success "SSH key permissions are correct"
    else
        print_warning "SSH key permissions should be 600"
        echo "  Fix with: chmod 600 $SSH_KEY_EXPANDED"
    fi
else
    print_error "SSH private key not found at $SSH_KEY_EXPANDED"
    echo "  Create with: ssh-keygen -t rsa -b 4096 -f $SSH_KEY_EXPANDED -N ''"
    ((ISSUES++))
fi

# Check 3: terraform.tfvars configuration
print_status "3. Checking terraform.tfvars configuration..."
if [ -f "terraform.tfvars" ]; then
    print_success "terraform.tfvars file exists"
    
    # Check required variables
    REQUIRED_VARS=("proxmox_api_url" "proxmox_user" "vm_template_id" "ssh_user")
    
    for var in "${REQUIRED_VARS[@]}"; do
        if grep -q "^$var" terraform.tfvars; then
            print_success "$var is configured"
        else
            print_error "$var is missing from terraform.tfvars"
            ((ISSUES++))
        fi
    done
    
    # Extract and validate Proxmox IP
    PROXMOX_URL=$(grep "proxmox_api_url" terraform.tfvars | cut -d'"' -f2)
    if [ -n "$PROXMOX_URL" ]; then
        PROXMOX_IP=$(echo "$PROXMOX_URL" | sed 's|https://||' | cut -d':' -f1)
        print_status "Proxmox IP: $PROXMOX_IP"
        
        # Test network connectivity (this might fail in Kiro but worth trying)
        if ping -c 1 -W 2 "$PROXMOX_IP" &>/dev/null; then
            print_success "Proxmox server is reachable"
        else
            print_warning "Cannot ping Proxmox server (may be normal in some networks)"
        fi
    fi
    
else
    print_error "terraform.tfvars file not found"
    ((ISSUES++))
fi

# Check 4: Terraform providers
print_status "4. Checking Terraform providers..."
if [ -d ".terraform/providers" ]; then
    print_success "Terraform providers are initialized"
    
    # Check for BPG Proxmox provider
    if find .terraform/providers -name "*bpg*proxmox*" | grep -q .; then
        print_success "BPG Proxmox provider is installed"
    else
        print_warning "BPG Proxmox provider not found"
        echo "  Run: terraform init"
    fi
else
    print_error "Terraform not initialized"
    echo "  Run: terraform init"
    ((ISSUES++))
fi

# Check 5: Network configuration
print_status "5. Checking network configuration..."
CONTROL_PLANE_IP=$(grep "control_plane_ip" terraform.tfvars | cut -d'"' -f2)
WORKER_IPS=$(grep -A2 "worker_ips" terraform.tfvars | grep -o '"[0-9.]*"' | tr -d '"')

if [ -n "$CONTROL_PLANE_IP" ]; then
    print_success "Control plane IP: $CONTROL_PLANE_IP"
else
    print_error "Control plane IP not configured"
    ((ISSUES++))
fi

if [ -n "$WORKER_IPS" ]; then
    print_success "Worker IPs configured"
    echo "$WORKER_IPS" | while read ip; do
        echo "    Worker: $ip"
    done
else
    print_error "Worker IPs not configured"
    ((ISSUES++))
fi

echo ""
print_status "Pre-flight check summary:"
if [ $ISSUES -eq 0 ]; then
    print_success "All checks passed! Ready for deployment."
    echo ""
    echo "Next steps:"
    echo "1. Run: ./scripts/terraform-apply-debug.sh"
    echo "2. Or run: terraform apply"
else
    print_error "Found $ISSUES issue(s) that should be fixed before deployment."
    echo ""
    echo "Fix the issues above, then run this check again."
fi

exit $ISSUES