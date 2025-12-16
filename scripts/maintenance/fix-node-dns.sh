#!/bin/bash

# Fix DNS Resolution on Kubernetes Nodes
# This script updates systemd-resolved on all nodes to use Cloudflare DNS

set -e

# Configuration
CONTROL_PLANE_IP="192.168.0.32"  # bumblebee
WORKER_IPS=("192.168.0.34" "192.168.0.33")  # prime, wheeljack
WORKER_NAMES=("prime" "wheeljack")
SSH_USER="ubuntu"
SSH_KEY="~/.ssh/maint-rsa"

# DNS servers to use (Cloudflare)
DNS_SERVERS="1.1.1.1 1.0.0.1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

fix_dns_on_node() {
    local node_name=$1
    local node_ip=$2
    
    log_info "Fixing DNS on ${node_name} (${node_ip})..."
    
    # Test SSH connectivity
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ${SSH_KEY} ${SSH_USER}@${node_ip} "echo connected" &>/dev/null; then
        log_error "Cannot connect to ${node_name} at ${node_ip}"
        return 1
    fi
    
    # Backup current resolved.conf
    log_info "  Backing up current DNS configuration..."
    ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} ${SSH_USER}@${node_ip} \
        "sudo cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.backup-\$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    
    # Update DNS configuration
    log_info "  Updating DNS servers to: ${DNS_SERVERS}..."
    ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} ${SSH_USER}@${node_ip} "sudo bash -c 'cat > /tmp/resolved.conf << EOF
[Resolve]
DNS=${DNS_SERVERS}
FallbackDNS=8.8.8.8 8.8.4.4
#Domains=
#DNSSEC=no
#DNSOverTLS=no
#MulticastDNS=no
#LLMNR=no
#Cache=yes
#CacheFromLocalhost=no
#DNSStubListener=yes
#DNSStubListenerExtra=
#ReadEtcHosts=yes
#ResolveUnicastSingleLabel=no
EOF
sudo mv /tmp/resolved.conf /etc/systemd/resolved.conf
sudo chmod 644 /etc/systemd/resolved.conf
'"
    
    if [ $? -ne 0 ]; then
        log_error "  Failed to update DNS configuration on ${node_name}"
        return 1
    fi
    
    # Restart systemd-resolved
    log_info "  Restarting systemd-resolved..."
    ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} ${SSH_USER}@${node_ip} \
        "sudo systemctl restart systemd-resolved"
    
    if [ $? -ne 0 ]; then
        log_error "  Failed to restart systemd-resolved on ${node_name}"
        return 1
    fi
    
    # Wait a moment for DNS to stabilize
    sleep 2
    
    # Verify DNS resolution
    log_info "  Verifying DNS resolution..."
    if ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} ${SSH_USER}@${node_ip} \
        "getent hosts google.com" &>/dev/null; then
        log_info "  ✓ DNS working on ${node_name}"
        
        # Test specific registries
        for registry in "lscr.io" "registry-1.docker.io" "docker.io"; do
            if ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} ${SSH_USER}@${node_ip} \
                "getent hosts ${registry}" &>/dev/null; then
                log_info "    ✓ Can resolve ${registry}"
            else
                log_warn "    ✗ Cannot resolve ${registry}"
            fi
        done
    else
        log_error "  ✗ DNS still not working on ${node_name}"
        return 1
    fi
    
    echo ""
    return 0
}

# Main execution
echo "=========================================="
echo "Fix DNS Resolution on Kubernetes Nodes"
echo "=========================================="
echo ""

# Fix DNS on control plane
fix_dns_on_node "bumblebee" "${CONTROL_PLANE_IP}"

# Fix DNS on workers
for i in "${!WORKER_IPS[@]}"; do
    fix_dns_on_node "${WORKER_NAMES[$i]}" "${WORKER_IPS[$i]}"
done

echo "=========================================="
log_info "DNS fix complete on all nodes!"
echo "=========================================="
echo ""
log_info "Next steps:"
echo "  1. Wait 1-2 minutes for containerd to pick up DNS changes"
echo "  2. Restart any pods stuck in ImagePullBackOff:"
echo "     kubectl delete pod -n media -l app=mylar"
echo "  3. Check CoreDNS pods:"
echo "     kubectl get pods -n kube-system -l k8s-app=kube-dns"
echo "  4. If CoreDNS is stuck, delete pods to restart:"
echo "     kubectl delete pod -n kube-system -l k8s-app=kube-dns"
echo ""

