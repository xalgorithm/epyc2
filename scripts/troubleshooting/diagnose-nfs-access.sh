#!/bin/bash

set -e

echo "🔍 NFS Access Diagnostic Script"
echo "==============================="

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

# Check kubectl connectivity
if ! kubectl cluster-info &> /dev/null; then
    log_error "kubectl connectivity failed"
    exit 1
fi

log_info "Gathering network information for NFS configuration..."
echo ""

# Get cluster network information
log_info "=== Cluster Network Information ==="

# Get node IPs
log_info "Node IP addresses:"
kubectl get nodes -o wide | awk 'NR>1 {print "  " $1 ": " $6 " (internal), " $7 " (external)"}'

# Get pod CIDR
log_info "Pod network CIDR:"
POD_CIDR=$(kubectl cluster-info dump | grep -oP 'cluster-cidr=\K[^"]*' | head -1 2>/dev/null || echo "Not found")
if [ "$POD_CIDR" != "Not found" ]; then
    echo "  $POD_CIDR"
else
    # Try alternative method
    POD_CIDR=$(kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}' 2>/dev/null || echo "Not found")
    if [ "$POD_CIDR" != "Not found" ]; then
        echo "  $POD_CIDR"
    else
        log_warning "Could not determine pod CIDR automatically"
        log_info "Checking pod IPs from running pods..."
        kubectl get pods --all-namespaces -o wide | awk 'NR>1 {print $7}' | sort -u | head -10 | while read ip; do
            if [ -n "$ip" ] && [ "$ip" != "<none>" ]; then
                echo "  Sample pod IP: $ip"
            fi
        done
    fi
fi

# Get service CIDR
log_info "Service network CIDR:"
SERVICE_CIDR=$(kubectl cluster-info dump | grep -oP 'service-cluster-ip-range=\K[^"]*' | head -1 2>/dev/null || echo "Not found")
if [ "$SERVICE_CIDR" != "Not found" ]; then
    echo "  $SERVICE_CIDR"
else
    log_warning "Could not determine service CIDR automatically"
    log_info "Checking service IPs..."
    kubectl get svc --all-namespaces | awk 'NR>1 {print $4}' | grep -v '<none>' | head -5 | while read ip; do
        if [ -n "$ip" ]; then
            echo "  Sample service IP: $ip"
        fi
    done
fi

echo ""
log_info "=== Current NFS Configuration ==="
log_info "NFS Server: 192.168.1.7"
log_info "NFS Path: /data/kubernetes/backups"

echo ""
log_info "=== Testing NFS Access from Backup Pod ==="

# Get backup pod
BACKUP_POD=$(kubectl get pods -n backup -l app=backup-metrics -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$BACKUP_POD" ] && [ "$BACKUP_POD" != "null" ]; then
    log_info "Using backup pod: $BACKUP_POD"
    
    # Get pod IP
    POD_IP=$(kubectl get pod "$BACKUP_POD" -n backup -o jsonpath='{.status.podIP}')
    log_info "Pod IP: $POD_IP"
    
    # Get node IP where pod is running
    NODE_NAME=$(kubectl get pod "$BACKUP_POD" -n backup -o jsonpath='{.spec.nodeName}')
    NODE_IP=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
    log_info "Node: $NODE_NAME ($NODE_IP)"
    
    # Test NFS mount
    log_info "Testing NFS mount..."
    if kubectl exec -n backup "$BACKUP_POD" -- mount | grep nfs > /dev/null 2>&1; then
        NFS_MOUNT=$(kubectl exec -n backup "$BACKUP_POD" -- mount | grep nfs)
        log_success "NFS mounted: $NFS_MOUNT"
    else
        log_error "NFS not mounted"
    fi
    
    # Test directory access
    log_info "Testing directory access..."
    if kubectl exec -n backup "$BACKUP_POD" -- ls -la /host/backup > /dev/null 2>&1; then
        log_success "Directory readable"
        PERMISSIONS=$(kubectl exec -n backup "$BACKUP_POD" -- ls -ld /host/backup)
        log_info "Directory permissions: $PERMISSIONS"
    else
        log_error "Directory not readable"
    fi
    
    # Test write access
    log_info "Testing write access..."
    TEST_FILE="/host/backup/nfs-test-$(date +%s).txt"
    if kubectl exec -n backup "$BACKUP_POD" -- sh -c "echo 'NFS write test' > $TEST_FILE" 2>/dev/null; then
        log_success "Write access successful"
        kubectl exec -n backup "$BACKUP_POD" -- rm -f "$TEST_FILE" 2>/dev/null || true
    else
        log_error "Write access failed"
        
        # Get more detailed error
        log_info "Detailed error information:"
        kubectl exec -n backup "$BACKUP_POD" -- sh -c "echo 'NFS write test' > $TEST_FILE" 2>&1 || true
        
        # Check if it's a permission issue
        kubectl exec -n backup "$BACKUP_POD" -- touch "$TEST_FILE" 2>&1 || true
    fi
    
    # Check available space
    log_info "Checking available space..."
    SPACE_INFO=$(kubectl exec -n backup "$BACKUP_POD" -- df -h /host/backup 2>/dev/null || echo "Could not get space info")
    echo "  $SPACE_INFO"
    
else
    log_error "Backup pod not found"
fi

echo ""
log_info "=== NFS Server Configuration Recommendations ==="
echo ""

# Determine network ranges to allow
log_info "Based on the network information above, you should configure your NFS server"
log_info "at 192.168.1.7 to allow access from the following networks:"
echo ""

# Node network (usually the main network)
log_info "1. Node Network (required):"
echo "   192.168.1.0/24  # Main node network"
echo ""

# Pod network
log_info "2. Pod Network (required for pod access):"
if [ "$POD_CIDR" != "Not found" ]; then
    echo "   $POD_CIDR  # Pod network CIDR"
else
    echo "   10.42.0.0/16  # Common K3s pod network (verify with your setup)"
    echo "   # OR check actual pod IPs above and use appropriate CIDR"
fi
echo ""

# Service network
log_info "3. Service Network (optional, for service-based access):"
if [ "$SERVICE_CIDR" != "Not found" ]; then
    echo "   $SERVICE_CIDR  # Service network CIDR"
else
    echo "   10.43.0.0/16  # Common K3s service network (verify with your setup)"
fi
echo ""

log_info "=== NFS Server /etc/exports Configuration ==="
echo ""
echo "Add these lines to /etc/exports on your NFS server (192.168.1.7):"
echo ""
echo "/data/kubernetes/backups 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)"
if [ "$POD_CIDR" != "Not found" ]; then
    echo "/data/kubernetes/backups $POD_CIDR(rw,sync,no_subtree_check,no_root_squash)"
else
    echo "/data/kubernetes/backups 10.42.0.0/16(rw,sync,no_subtree_check,no_root_squash)"
fi
echo ""

log_info "=== Commands to run on NFS server (192.168.1.7) ==="
echo ""
echo "# 1. Edit /etc/exports"
echo "sudo nano /etc/exports"
echo ""
echo "# 2. Create backup directory if it doesn't exist"
echo "sudo mkdir -p /data/kubernetes/backups"
echo "sudo chown nobody:nogroup /data/kubernetes/backups"
echo "sudo chmod 755 /data/kubernetes/backups"
echo ""
echo "# 3. Reload NFS exports"
echo "sudo exportfs -ra"
echo ""
echo "# 4. Restart NFS service"
echo "sudo systemctl restart nfs-kernel-server"
echo ""
echo "# 5. Verify exports"
echo "sudo exportfs -v"
echo ""

log_info "=== Verification Commands ==="
echo ""
echo "# From any Kubernetes node, test NFS access:"
echo "showmount -e 192.168.1.7"
echo ""
echo "# Test mount (from a node):"
echo "sudo mkdir -p /tmp/nfs-test"
echo "sudo mount -t nfs 192.168.1.7:/data/kubernetes/backups /tmp/nfs-test"
echo "sudo touch /tmp/nfs-test/test-file"
echo "sudo umount /tmp/nfs-test"
echo ""

log_info "=== After NFS Configuration ==="
echo ""
echo "1. Configure NFS server as shown above"
echo "2. Test connectivity: ./scripts/test-backup-connectivity.sh"
echo "3. Try manual backup: ./scripts/trigger-manual-backup.sh apps"
echo ""

log_warning "Note: The 'no_root_squash' option is needed because Kubernetes pods may run as root"
log_warning "Ensure your NFS server security is appropriate for your environment"