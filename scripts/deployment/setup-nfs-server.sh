#!/bin/bash

echo "🗄️  NFS Server Setup for Kubernetes Storage"
echo "============================================"

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

# Configuration
# Get NFS server IP from terraform.tfvars or use default
NFS_SERVER=$(grep nfs_server_ip terraform.tfvars 2>/dev/null | cut -d '"' -f 2 || echo "192.168.1.100")
NFS_BASE_PATH="/data"
K8S_STORAGE_PATH="/data/kubernetes"
BACKUP_PATH="/data/backups"

echo "This script will set up NFS directories on the server for Kubernetes storage."
echo ""
print_status "NFS Server: $NFS_SERVER"
print_status "Kubernetes Storage Path: $K8S_STORAGE_PATH"
print_status "Backup Path: $BACKUP_PATH"
echo ""

# Function to test SSH connectivity
test_ssh() {
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$NFS_SERVER" "echo 'SSH test successful'" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to create NFS directories
create_nfs_directories() {
    print_status "Creating NFS directories on $NFS_SERVER..."
    
    if ssh -o StrictHostKeyChecking=no root@"$NFS_SERVER" "
        # Create base directory
        mkdir -p $NFS_BASE_PATH
        
        # Create Kubernetes storage directory
        mkdir -p $K8S_STORAGE_PATH
        chmod 755 $K8S_STORAGE_PATH
        chown nobody:nogroup $K8S_STORAGE_PATH
        
        # Create backup directory
        mkdir -p $BACKUP_PATH
        chmod 755 $BACKUP_PATH
        chown nobody:nogroup $BACKUP_PATH
        
        echo 'Directories created successfully'
    "; then
        print_success "NFS directories created successfully"
        return 0
    else
        print_error "Failed to create NFS directories"
        return 1
    fi
}

# Function to configure NFS exports
configure_nfs_exports() {
    print_status "Configuring NFS exports..."
    
    # Create exports configuration
    local exports_config="
# Kubernetes Storage Exports
$K8S_STORAGE_PATH *(rw,sync,no_subtree_check,no_root_squash,insecure)
$BACKUP_PATH *(rw,sync,no_subtree_check,no_root_squash,insecure)
"
    
    if ssh -o StrictHostKeyChecking=no root@"$NFS_SERVER" "
        # Backup existing exports
        cp /etc/exports /etc/exports.backup.\$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
        
        # Add our exports (remove duplicates first)
        grep -v '$K8S_STORAGE_PATH' /etc/exports > /tmp/exports.tmp 2>/dev/null || touch /tmp/exports.tmp
        grep -v '$BACKUP_PATH' /tmp/exports.tmp > /tmp/exports.clean 2>/dev/null || touch /tmp/exports.clean
        
        # Add new exports
        echo '$exports_config' >> /tmp/exports.clean
        
        # Install new exports file
        mv /tmp/exports.clean /etc/exports
        
        # Reload NFS exports
        exportfs -ra
        
        echo 'NFS exports configured successfully'
    "; then
        print_success "NFS exports configured successfully"
        return 0
    else
        print_error "Failed to configure NFS exports"
        return 1
    fi
}

# Function to ensure NFS services are running
ensure_nfs_services() {
    print_status "Ensuring NFS services are running..."
    
    if ssh -o StrictHostKeyChecking=no root@"$NFS_SERVER" "
        # Install NFS server if not present
        if ! systemctl is-active --quiet nfs-server; then
            echo 'Installing NFS server...'
            apt-get update
            apt-get install -y nfs-kernel-server
        fi
        
        # Enable and start NFS services
        systemctl enable nfs-server
        systemctl start nfs-server
        systemctl enable rpcbind
        systemctl start rpcbind
        
        # Check service status
        systemctl is-active --quiet nfs-server && echo 'NFS server is running'
        systemctl is-active --quiet rpcbind && echo 'RPC bind is running'
    "; then
        print_success "NFS services are running"
        return 0
    else
        print_error "Failed to start NFS services"
        return 1
    fi
}

# Function to test NFS mount
test_nfs_mount() {
    print_status "Testing NFS mount from local machine..."
    
    local test_dir="/tmp/nfs_test_$$"
    
    # Create test mount point
    mkdir -p "$test_dir"
    
    # Try to mount
    if mount -t nfs "$NFS_SERVER:$K8S_STORAGE_PATH" "$test_dir" 2>/dev/null; then
        print_success "NFS mount test successful"
        
        # Test write
        if echo "test" > "$test_dir/test_file" 2>/dev/null; then
            print_success "NFS write test successful"
            rm -f "$test_dir/test_file"
        else
            print_warning "NFS write test failed - check permissions"
        fi
        
        # Unmount
        umount "$test_dir"
        rmdir "$test_dir"
        return 0
    else
        print_error "NFS mount test failed"
        print_status "Make sure NFS client is installed: sudo apt-get install nfs-common"
        rmdir "$test_dir"
        return 1
    fi
}

# Function to show current exports
show_exports() {
    print_status "Current NFS exports on $NFS_SERVER:"
    
    ssh -o StrictHostKeyChecking=no root@"$NFS_SERVER" "
        exportfs -v
    " || print_error "Could not retrieve exports"
}

# Function to show troubleshooting info
show_troubleshooting() {
    echo ""
    print_status "Troubleshooting Information"
    echo "=========================="
    
    echo ""
    print_status "1. Check NFS server status:"
    echo "   ssh root@$NFS_SERVER 'systemctl status nfs-server'"
    
    echo ""
    print_status "2. Check NFS exports:"
    echo "   ssh root@$NFS_SERVER 'exportfs -v'"
    
    echo ""
    print_status "3. Test NFS mount manually:"
    echo "   sudo mkdir -p /mnt/test"
    echo "   sudo mount -t nfs $NFS_SERVER:$K8S_STORAGE_PATH /mnt/test"
    echo "   ls -la /mnt/test"
    echo "   sudo umount /mnt/test"
    
    echo ""
    print_status "4. Install NFS client (if needed):"
    echo "   sudo apt-get install nfs-common"
    
    echo ""
    print_status "5. Check firewall on NFS server:"
    echo "   ssh root@$NFS_SERVER 'ufw status'"
    echo "   # If firewall is active, allow NFS:"
    echo "   ssh root@$NFS_SERVER 'ufw allow from 192.168.1.0/24 to any port nfs'"
}

# Main execution
main() {
    print_status "Starting NFS server setup..."
    
    # Test SSH connectivity
    if test_ssh; then
        print_success "SSH connection to NFS server successful"
    else
        print_error "Cannot SSH to NFS server ($NFS_SERVER)"
        print_status "Please ensure:"
        echo "  - NFS server is running and accessible"
        echo "  - SSH key authentication is set up for root user"
        echo "  - Network connectivity to $NFS_SERVER"
        exit 1
    fi
    
    # Create directories
    if ! create_nfs_directories; then
        print_error "Failed to create NFS directories"
        exit 1
    fi
    
    # Configure NFS exports
    if ! configure_nfs_exports; then
        print_error "Failed to configure NFS exports"
        exit 1
    fi
    
    # Ensure NFS services are running
    if ! ensure_nfs_services; then
        print_error "Failed to start NFS services"
        exit 1
    fi
    
    # Show current exports
    echo ""
    show_exports
    
    # Test NFS mount
    echo ""
    if test_nfs_mount; then
        print_success "✅ NFS server setup completed successfully!"
        
        echo ""
        print_status "Next steps:"
        echo "1. Apply the Terraform configuration to deploy NFS storage class:"
        echo "   terraform apply"
        echo ""
        echo "2. Verify the storage class is default:"
        echo "   kubectl get storageclass"
        echo ""
        echo "3. Test with a PVC:"
        echo "   kubectl get pvc nfs-test-pvc"
        
    else
        print_warning "NFS server setup completed but mount test failed"
        show_troubleshooting
    fi
}

# Check if running as root for mount test
if [ "$EUID" -ne 0 ] && [ "$1" != "--no-mount-test" ]; then
    print_warning "Running without root privileges - mount test will be skipped"
    print_status "Run with sudo for full testing, or use --no-mount-test flag"
    
    if [ "$1" != "--no-mount-test" ]; then
        read -p "Continue without mount test? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Run main function
main