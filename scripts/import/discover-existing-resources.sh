#!/bin/bash

echo "=== Discovering Existing Resources ==="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_section() {
    echo -e "${GREEN}=== $1 ===${NC}"
}

print_found() {
    echo -e "${YELLOW}FOUND: $1${NC}"
}

print_missing() {
    echo -e "${RED}MISSING: $1${NC}"
}

# Check Proxmox VMs (you'll need to check this manually in Proxmox UI)
print_section "Proxmox VMs (Check manually in Proxmox UI)"
echo "Login to https://192.168.0.7:8006 and note VM IDs for:"
echo "- bumblebee (control plane)"
echo "- prime (worker)"  
echo "- wheeljack (worker)"
echo ""

# Check Kubernetes cluster access
print_section "Kubernetes Cluster Access"
if kubectl cluster-info &> /dev/null; then
    print_found "Kubernetes cluster is accessible"
else
    print_missing "Cannot access Kubernetes cluster"
    echo "Please ensure ~/.kube/config is properly configured"
    exit 1
fi

# Check namespaces
print_section "Kubernetes Namespaces"
for ns in monitoring media automation backup metallb-system ingress-nginx kube-system; do
    if kubectl get namespace $ns &> /dev/null; then
        print_found "Namespace: $ns"
    else
        print_missing "Namespace: $ns"
    fi
done

# Check Helm releases
print_section "Helm Releases"
echo "Checking Helm releases..."
helm list -A

# Check deployments
print_section "Deployments"
for ns in monitoring media automation; do
    echo "Deployments in namespace $ns:"
    kubectl get deployments -n $ns 2>/dev/null || echo "  No deployments or namespace doesn't exist"
done

# Check services
print_section "Services"
for ns in monitoring media automation; do
    echo "Services in namespace $ns:"
    kubectl get services -n $ns 2>/dev/null || echo "  No services or namespace doesn't exist"
done

# Check ingresses
print_section "Ingresses"
for ns in monitoring media automation; do
    echo "Ingresses in namespace $ns:"
    kubectl get ingresses -n $ns 2>/dev/null || echo "  No ingresses or namespace doesn't exist"
done

# Check storage classes
print_section "Storage Classes"
kubectl get storageclass

# Check PVCs
print_section "Persistent Volume Claims"
kubectl get pvc -A

echo ""
echo "=== Discovery Complete ==="
echo "Use this information to update the import script with correct resource names and IDs"