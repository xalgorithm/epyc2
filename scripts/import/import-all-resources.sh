#!/bin/bash
set -e

echo "=== Comprehensive Terraform State Import Script ==="
echo "This script will import all existing VMs and Kubernetes resources"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}=== $1 ===${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

# Step 1: Import Proxmox VMs
print_step "Step 1: Import Proxmox VMs"
echo "First, you need to find the VM IDs in Proxmox:"
echo "1. Login to Proxmox web interface (https://192.168.0.7:8006)"
echo "2. Note the VM IDs for bumblebee, prime, and wheeljack"
echo "3. Update the VM_IDS below with the actual values"
echo ""

# VM IDs - UPDATE THESE WITH ACTUAL VALUES FROM PROXMOX
BUMBLEBEE_ID="102"  # Replace with actual VM ID
PRIME_ID="101"      # Replace with actual VM ID  
WHEELJACK_ID="100"  # Replace with actual VM ID

echo "Current VM ID assignments:"
echo "  bumblebee: $BUMBLEBEE_ID"
echo "  prime: $PRIME_ID"
echo "  wheeljack: $WHEELJACK_ID"
echo ""

read -p "Are these VM IDs correct? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please edit this script and update the VM_IDS variables with the correct values"
    exit 1
fi

# Import VMs
echo "Importing Proxmox VMs..."
terraform import proxmox_virtual_environment_vm.bumblebee pve/$BUMBLEBEE_ID || print_error "Failed to import bumblebee"
terraform import proxmox_virtual_environment_vm.prime pve/$PRIME_ID || print_error "Failed to import prime"
terraform import proxmox_virtual_environment_vm.wheeljack pve/$WHEELJACK_ID || print_error "Failed to import wheeljack"

print_step "Step 2: Import Kubernetes Resources"
echo "Now importing Kubernetes resources..."

# Check if kubectl is working
if ! kubectl cluster-info &> /dev/null; then
    print_error "kubectl is not working. Please ensure:"
    echo "1. Kubernetes cluster is running"
    echo "2. ~/.kube/config is properly configured"
    echo "3. You can access the cluster"
    exit 1
fi

# Import Kubernetes namespaces
echo "Importing namespaces..."
kubectl get namespace monitoring &> /dev/null && terraform import kubernetes_namespace.monitoring monitoring || echo "monitoring namespace not found"
kubectl get namespace media &> /dev/null && terraform import kubernetes_namespace.mylar media || echo "media namespace not found"


kubectl get namespace backup &> /dev/null && terraform import kubernetes_namespace.backup backup || echo "backup namespace not found"

# Import Helm releases
echo "Importing Helm releases..."
helm list -n metallb-system | grep -q metallb && terraform import helm_release.metallb metallb/metallb-system || echo "metallb helm release not found"
helm list -n ingress-nginx | grep -q ingress-nginx && terraform import helm_release.ingress_nginx ingress-nginx/ingress-nginx || echo "ingress-nginx helm release not found"
helm list -n kube-system | grep -q csi-driver-nfs && terraform import helm_release.nfs_csi_driver csi-driver-nfs/kube-system || echo "nfs-csi-driver helm release not found"

# Import Storage Classes
echo "Importing storage classes..."
kubectl get storageclass nfs-storage &> /dev/null && terraform import kubernetes_storage_class.nfs_storage_class nfs-storage || echo "nfs-storage storageclass not found"

# Import Services
echo "Importing services..."
kubectl get svc -n monitoring prometheus &> /dev/null && terraform import kubernetes_service.prometheus monitoring/prometheus || echo "prometheus service not found"
kubectl get svc -n monitoring grafana &> /dev/null && terraform import kubernetes_service.grafana monitoring/grafana || echo "grafana service not found"
kubectl get svc -n monitoring loki &> /dev/null && terraform import kubernetes_service.loki monitoring/loki || echo "loki service not found"
kubectl get svc -n media mylar &> /dev/null && terraform import kubernetes_service.mylar media/mylar || echo "mylar service not found"



# Import Deployments
echo "Importing deployments..."
kubectl get deployment -n monitoring prometheus &> /dev/null && terraform import kubernetes_deployment.prometheus monitoring/prometheus || echo "prometheus deployment not found"
kubectl get deployment -n monitoring grafana &> /dev/null && terraform import kubernetes_deployment.grafana monitoring/grafana || echo "grafana deployment not found"
kubectl get deployment -n monitoring loki &> /dev/null && terraform import kubernetes_deployment.loki monitoring/loki || echo "loki deployment not found"
kubectl get deployment -n media mylar &> /dev/null && terraform import kubernetes_deployment.mylar media/mylar || echo "mylar deployment not found"



# Import Ingresses
echo "Importing ingresses..."
kubectl get ingress -n monitoring grafana &> /dev/null && terraform import kubernetes_ingress_v1.grafana monitoring/grafana || echo "grafana ingress not found"
kubectl get ingress -n monitoring prometheus &> /dev/null && terraform import kubernetes_ingress_v1.prometheus monitoring/prometheus || echo "prometheus ingress not found"
kubectl get ingress -n monitoring loki &> /dev/null && terraform import kubernetes_ingress_v1.loki monitoring/loki || echo "loki ingress not found"
kubectl get ingress -n media mylar &> /dev/null && terraform import kubernetes_ingress_v1.mylar media/mylar || echo "mylar ingress not found"



print_step "Step 3: Verify Import"
echo "Running terraform plan to verify imports..."
terraform plan

print_step "Import Complete!"
echo "State has been recreated. Review the terraform plan output above."
echo "If there are still resources showing as 'to be created', you may need to:"
echo "1. Import additional resources manually"
echo "2. Adjust resource configurations to match existing infrastructure"
echo "3. Use terraform apply to create missing resources"
