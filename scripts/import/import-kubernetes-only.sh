#!/bin/bash
set -e

echo "=== Import Kubernetes Resources Only ==="
echo "This script imports Kubernetes resources without managing Proxmox VMs"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_step() {
    echo -e "${GREEN}=== $1 ===${NC}"
}

print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

# Check Kubernetes access
print_step "Step 1: Verify Kubernetes Access"
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot access Kubernetes cluster"
    echo "Please ensure:"
    echo "1. Kubernetes cluster is running"
    echo "2. ~/.kube/config is properly configured"
    echo "3. You can access the cluster from this environment"
    exit 1
fi
print_info "Kubernetes cluster is accessible"

# Import namespaces first
print_step "Step 2: Import Namespaces"
for ns in monitoring media automation backup; do
    if kubectl get namespace $ns &> /dev/null; then
        echo "Importing namespace: $ns"
        terraform import kubernetes_namespace.${ns} $ns 2>/dev/null || echo "  Already imported or failed"
    else
        print_info "Namespace $ns does not exist - will be created"
    fi
done

# Import storage class
print_step "Step 3: Import Storage Class"
if kubectl get storageclass nfs-storage &> /dev/null; then
    echo "Importing storage class: nfs-storage"
    terraform import kubernetes_storage_class.nfs_storage_class nfs-storage 2>/dev/null || echo "  Already imported or failed"
else
    print_info "Storage class nfs-storage does not exist - will be created"
fi

# Import Helm releases
print_step "Step 4: Import Helm Releases"
echo "Checking existing Helm releases..."
helm list -A

# Try to import common Helm releases
for release in "metallb metallb-system" "ingress-nginx ingress-nginx" "csi-driver-nfs kube-system"; do
    release_name=$(echo $release | cut -d' ' -f1)
    namespace=$(echo $release | cut -d' ' -f2)
    
    if helm list -n $namespace | grep -q $release_name; then
        echo "Importing Helm release: $release_name in $namespace"
        terraform import helm_release.${release_name} ${release_name}/${namespace} 2>/dev/null || echo "  Already imported or failed"
    else
        print_info "Helm release $release_name not found in $namespace"
    fi
done

# Import key services
print_step "Step 5: Import Services"
services=(
    "prometheus monitoring"
    "grafana monitoring" 
    "loki monitoring"
    "mylar media"
)

for service in "${services[@]}"; do
    svc_name=$(echo $service | cut -d' ' -f1)
    namespace=$(echo $service | cut -d' ' -f2)
    
    if kubectl get service $svc_name -n $namespace &> /dev/null; then
        echo "Importing service: $svc_name in $namespace"
        terraform import kubernetes_service.${svc_name} ${namespace}/${svc_name} 2>/dev/null || echo "  Already imported or failed"
    else
        print_info "Service $svc_name not found in $namespace"
    fi
done

# Import key deployments
print_step "Step 6: Import Deployments"
deployments=(
    "prometheus monitoring"
    "grafana monitoring"
    "loki monitoring" 
    "mylar media"
)

for deployment in "${deployments[@]}"; do
    dep_name=$(echo $deployment | cut -d' ' -f1)
    namespace=$(echo $deployment | cut -d' ' -f2)
    
    if kubectl get deployment $dep_name -n $namespace &> /dev/null; then
        echo "Importing deployment: $dep_name in $namespace"
        terraform import kubernetes_deployment.${dep_name} ${namespace}/${dep_name} 2>/dev/null || echo "  Already imported or failed"
    else
        print_info "Deployment $dep_name not found in $namespace"
    fi
done

print_step "Step 7: Verify Import"
echo "Running terraform plan to see what needs to be created..."
terraform plan

print_step "Import Complete!"
echo ""
echo "Summary:"
echo "- VMs are managed externally (not by Terraform)"
echo "- Kubernetes resources have been imported where they exist"
echo "- Review the terraform plan output above"
echo ""
echo "Next steps:"
echo "1. If plan shows resources to create, run: terraform apply"
echo "2. If plan shows unwanted changes, adjust configurations"
