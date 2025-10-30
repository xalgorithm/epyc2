#!/bin/bash

set -e

echo "🔧 NFS Server Configuration Fix Script"
echo "======================================"

# Get NFS server IP from terraform.tfvars or use default
NFS_SERVER=$(grep nfs_server_ip terraform.tfvars 2>/dev/null | cut -d '"' -f 2 || echo "192.168.1.100")
NFS_PATH="/data/kubernetes/backups"

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

show_usage() {
    echo "This script helps configure NFS server permissions for Kubernetes backup access."
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --remote-fix    Try to fix NFS server remotely via SSH"
    echo "  --show-config   Show the required NFS configuration"
    echo "  --test-access   Test current NFS access from backup pod"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --show-config   # Show what needs to be configured"
    echo "  $0 --test-access   # Test current access"
    echo "  $0 --remote-fix    # Try to fix remotely (requires SSH access)"
}

show_nfs_config() {
    log_info "Required NFS Server Configuration"
    echo ""
    
    # Get pod network info
    POD_CIDR=$(kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}' 2>/dev/null || echo "10.42.0.0/16")
    
    log_info "=== /etc/exports configuration on $NFS_SERVER ==="
    echo ""
    echo "# Kubernetes backup storage"
    echo "$NFS_PATH 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)"
    echo "$NFS_PATH $POD_CIDR(rw,sync,no_subtree_check,no_root_squash)"
    echo ""
    
    log_info "=== Commands to run on NFS server ($NFS_SERVER) ==="
    echo ""
    echo "# 1. Create backup directory"
    echo "sudo mkdir -p $NFS_PATH"
    echo "sudo chown nobody:nogroup $NFS_PATH"
    echo "sudo chmod 755 $NFS_PATH"
    echo ""
    echo "# 2. Add to /etc/exports (append these lines)"
    echo "echo '$NFS_PATH 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)' | sudo tee -a /etc/exports"
    echo "echo '$NFS_PATH $POD_CIDR(rw,sync,no_subtree_check,no_root_squash)' | sudo tee -a /etc/exports"
    echo ""
    echo "# 3. Reload NFS exports"
    echo "sudo exportfs -ra"
    echo ""
    echo "# 4. Restart NFS service"
    echo "sudo systemctl restart nfs-kernel-server"
    echo ""
    echo "# 5. Verify exports"
    echo "sudo exportfs -v"
    echo "showmount -e localhost"
}

test_nfs_access() {
    log_info "Testing NFS access from Kubernetes backup pod..."
    
    # Check if backup pod exists
    BACKUP_POD=$(kubectl get pods -n backup -l app=backup-metrics -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$BACKUP_POD" ] || [ "$BACKUP_POD" = "null" ]; then
        log_error "Backup pod not found. Deploy backup system first."
        return 1
    fi
    
    log_info "Using backup pod: $BACKUP_POD"
    
    # Test mount
    if kubectl exec -n backup "$BACKUP_POD" -- mount | grep -q nfs; then
        log_success "NFS is mounted"
    else
        log_error "NFS is not mounted"
        return 1
    fi
    
    # Test read access
    if kubectl exec -n backup "$BACKUP_POD" -- ls /host/backup > /dev/null 2>&1; then
        log_success "Read access OK"
    else
        log_error "Read access failed"
        return 1
    fi
    
    # Test write access
    TEST_FILE="/host/backup/write-test-$(date +%s).txt"
    if kubectl exec -n backup "$BACKUP_POD" -- sh -c "echo 'Write test' > $TEST_FILE" 2>/dev/null; then
        log_success "Write access OK"
        kubectl exec -n backup "$BACKUP_POD" -- rm -f "$TEST_FILE" 2>/dev/null || true
        return 0
    else
        log_error "Write access failed"
        
        # Show detailed error
        log_info "Detailed error:"
        kubectl exec -n backup "$BACKUP_POD" -- sh -c "echo 'Write test' > $TEST_FILE" 2>&1 || true
        
        # Check permissions
        PERMS=$(kubectl exec -n backup "$BACKUP_POD" -- ls -ld /host/backup 2>/dev/null || echo "Could not get permissions")
        log_info "Directory permissions: $PERMS"
        
        return 1
    fi
}

remote_fix() {
    log_info "Attempting to fix NFS server configuration remotely..."
    
    # Use the correct SSH key
    SSH_KEY="$HOME/.ssh/id_ed25519"
    
    if [ ! -f "$SSH_KEY" ]; then
        log_error "SSH private key not found at $SSH_KEY"
        log_info "Please ensure the SSH key exists or configure NFS manually."
        log_info "Run: $0 --show-config"
        return 1
    fi
    
    log_info "Using SSH key: $SSH_KEY"
    log_info "Connecting to NFS server: $NFS_SERVER"
    
    # Get pod CIDR
    POD_CIDR=$(kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}' 2>/dev/null || echo "10.42.0.0/16")
    
    # Create a temporary script to run on the remote server
    TEMP_SCRIPT=$(mktemp)
    cat > "$TEMP_SCRIPT" << 'SCRIPT_EOF'
#!/bin/bash
set -e

NFS_PATH="/data/kubernetes/backups"
POD_CIDR="$1"

echo "Creating backup directory..."
if sudo -n mkdir -p "$NFS_PATH" 2>/dev/null; then
    echo "Directory created successfully"
else
    echo "Need sudo password for directory creation"
    sudo mkdir -p "$NFS_PATH"
fi

echo "Setting directory ownership..."
if sudo -n chown nobody:nogroup "$NFS_PATH" 2>/dev/null; then
    echo "Ownership set successfully"
else
    echo "Need sudo password for ownership change"
    sudo chown nobody:nogroup "$NFS_PATH"
fi

echo "Setting directory permissions..."
if sudo -n chmod 755 "$NFS_PATH" 2>/dev/null; then
    echo "Permissions set successfully"
else
    echo "Need sudo password for permission change"
    sudo chmod 755 "$NFS_PATH"
fi

echo "Checking /etc/exports..."
if ! grep -q "$NFS_PATH" /etc/exports 2>/dev/null; then
    echo "Adding NFS exports..."
    if sudo -n tee -a /etc/exports >/dev/null 2>&1 << EOF
$NFS_PATH 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
$NFS_PATH $POD_CIDR(rw,sync,no_subtree_check,no_root_squash)
EOF
    then
        echo "Exports added successfully"
    else
        echo "Need sudo password for exports configuration"
        sudo tee -a /etc/exports << EOF
$NFS_PATH 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
$NFS_PATH $POD_CIDR(rw,sync,no_subtree_check,no_root_squash)
EOF
    fi
else
    echo "NFS exports already configured"
fi

echo "Reloading NFS exports..."
if sudo -n exportfs -ra 2>/dev/null; then
    echo "Exports reloaded successfully"
else
    echo "Need sudo password for export reload"
    sudo exportfs -ra
fi

echo "Restarting NFS service..."
if sudo -n systemctl restart nfs-kernel-server 2>/dev/null; then
    echo "NFS service restarted successfully"
else
    echo "Need sudo password for service restart"
    sudo systemctl restart nfs-kernel-server
fi

echo "Verifying exports..."
if sudo -n exportfs -v 2>/dev/null; then
    echo "Export verification completed"
else
    echo "Need sudo password for export verification"
    sudo exportfs -v
fi

echo "NFS configuration completed successfully!"
SCRIPT_EOF
    
    # Copy script to remote server and execute
    if scp -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$TEMP_SCRIPT" ubuntu@$NFS_SERVER:/tmp/nfs-fix.sh; then
        log_info "Script uploaded successfully"
        
        # Make script executable and run it
        if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no -t ubuntu@$NFS_SERVER "chmod +x /tmp/nfs-fix.sh && /tmp/nfs-fix.sh '$POD_CIDR' && rm -f /tmp/nfs-fix.sh"; then
            log_success "NFS server configured successfully!"
            log_info "Testing access..."
            sleep 5
            test_nfs_access
        else
            log_error "Failed to execute configuration script on remote server"
            log_info "Please configure manually using: $0 --show-config"
            rm -f "$TEMP_SCRIPT"
            return 1
        fi
    else
        log_error "Failed to upload script to remote server"
        log_info "Please configure manually using: $0 --show-config"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    
    # Clean up
    rm -f "$TEMP_SCRIPT"
}

# Main execution
case "${1:-}" in
    "--show-config")
        show_nfs_config
        ;;
    "--test-access")
        test_nfs_access
        ;;
    "--remote-fix")
        remote_fix
        ;;
    "--help"|"-h"|"")
        show_usage
        ;;
    *)
        log_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac