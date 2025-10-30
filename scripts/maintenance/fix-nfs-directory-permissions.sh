#!/bin/bash

set -e

echo "🔧 NFS Directory Permissions Fix Script"
echo "======================================="

# Get NFS server IP from terraform.tfvars or use default
NFS_SERVER=$(grep nfs_server_ip terraform.tfvars 2>/dev/null | cut -d '"' -f 2 || echo "192.168.1.100")
NFS_PATH="/data/kubernetes/backups"
SSH_KEY="$HOME/.ssh/id_ed25519"

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

# Check SSH key
if [ ! -f "$SSH_KEY" ]; then
    log_error "SSH private key not found at $SSH_KEY"
    exit 1
fi

log_info "Using SSH key: $SSH_KEY"
log_info "Connecting to NFS server: $NFS_SERVER"

# Create a script to fix directory permissions
TEMP_SCRIPT=$(mktemp)
cat > "$TEMP_SCRIPT" << 'SCRIPT_EOF'
#!/bin/bash
set -e

NFS_PATH="/data/kubernetes/backups"

echo "🔧 Fixing NFS directory permissions..."

# Create the directory if it doesn't exist
if [ ! -d "$NFS_PATH" ]; then
    echo "Creating NFS backup directory..."
    sudo mkdir -p "$NFS_PATH"
fi

# Set proper ownership and permissions
echo "Setting directory ownership to nobody:nogroup..."
sudo chown -R nobody:nogroup "$NFS_PATH"

echo "Setting directory permissions to 777 (full access)..."
sudo chmod -R 777 "$NFS_PATH"

# Verify permissions
echo "Current directory permissions:"
ls -la "$NFS_PATH"
ls -ld "$NFS_PATH"

# Test write access
echo "Testing write access..."
TEST_FILE="$NFS_PATH/write-test-$(date +%s).txt"
if sudo -u nobody sh -c "echo 'Write test from nobody user' > '$TEST_FILE'" 2>/dev/null; then
    echo "✅ Write test as nobody user: SUCCESS"
    rm -f "$TEST_FILE"
else
    echo "❌ Write test as nobody user: FAILED"
fi

# Test as root
if echo 'Write test from root' > "$NFS_PATH/root-test-$(date +%s).txt" 2>/dev/null; then
    echo "✅ Write test as root: SUCCESS"
    rm -f "$NFS_PATH"/root-test-*.txt
else
    echo "❌ Write test as root: FAILED"
fi

echo "✅ NFS directory permissions fixed successfully!"
SCRIPT_EOF

# Upload and execute the script
log_info "Uploading permission fix script to NFS server..."

if scp -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$TEMP_SCRIPT" ubuntu@$NFS_SERVER:/tmp/fix-nfs-perms.sh; then
    log_info "Script uploaded successfully"
    
    # Execute the script
    if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no -t ubuntu@$NFS_SERVER "chmod +x /tmp/fix-nfs-perms.sh && /tmp/fix-nfs-perms.sh && rm -f /tmp/fix-nfs-perms.sh"; then
        log_success "NFS directory permissions fixed successfully!"
        
        # Test from Kubernetes pod
        log_info "Testing write access from Kubernetes backup pod..."
        sleep 5
        
        # Get backup pod
        BACKUP_POD=$(kubectl get pods -n backup -l app=backup-metrics -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ -n "$BACKUP_POD" ] && [ "$BACKUP_POD" != "null" ]; then
            log_info "Using backup pod: $BACKUP_POD"
            
            # Test directory creation
            TEST_DIR="/host/backup/test-dir-$(date +%s)"
            if kubectl exec -n backup "$BACKUP_POD" -- mkdir -p "$TEST_DIR" 2>/dev/null; then
                log_success "Directory creation test: PASSED"
                kubectl exec -n backup "$BACKUP_POD" -- rmdir "$TEST_DIR" 2>/dev/null || true
                
                # Test file creation
                TEST_FILE="/host/backup/write-test-$(date +%s).txt"
                if kubectl exec -n backup "$BACKUP_POD" -- sh -c "echo 'Write test successful' > $TEST_FILE" 2>/dev/null; then
                    log_success "File creation test: PASSED"
                    kubectl exec -n backup "$BACKUP_POD" -- rm -f "$TEST_FILE" 2>/dev/null || true
                    
                    log_success "🎉 All tests passed! NFS backup storage is now fully writable!"
                    echo ""
                    log_info "You can now run manual backups successfully:"
                    echo "  ./scripts/trigger-manual-backup.sh"
                    echo ""
                else
                    log_error "File creation test: FAILED"
                    kubectl exec -n backup "$BACKUP_POD" -- sh -c "echo 'Write test' > $TEST_FILE" 2>&1 || true
                fi
            else
                log_error "Directory creation test: FAILED"
                kubectl exec -n backup "$BACKUP_POD" -- mkdir -p "$TEST_DIR" 2>&1 || true
            fi
        else
            log_warning "Backup pod not found. Deploy backup system to test access."
        fi
        
    else
        log_error "Failed to execute permission fix script on remote server"
        exit 1
    fi
else
    log_error "Failed to upload script to remote server"
    exit 1
fi

# Clean up
rm -f "$TEMP_SCRIPT"

echo ""
log_info "Summary of changes made:"
echo "  - Set directory ownership to nobody:nogroup"
echo "  - Set directory permissions to 777 (full access)"
echo "  - Verified write access from both root and nobody users"
echo ""
log_info "The NFS backup directory is now ready for Kubernetes backup operations."