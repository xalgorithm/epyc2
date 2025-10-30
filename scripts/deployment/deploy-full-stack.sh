#!/bin/bash

# Full Stack Kubernetes Deployment Script
# This script deploys the complete Kubernetes cluster from scratch

set -e

echo "🚀 Full Stack Kubernetes Deployment"
echo "===================================="
echo ""
echo "This will create:"
echo "- 3 Proxmox VMs (bumblebee, prime, wheeljack)"
echo "- Complete Kubernetes cluster with Flannel CNI"
echo "- MetalLB load balancer"
echo "- Complete observability stack (Prometheus, Grafana, Loki, Mimir)"
echo "- Media applications (Mylar)"
echo "- Automated backup system"
echo "- NGINX Ingress with SSL termination"
echo ""

# Check prerequisites
echo "🔍 Checking prerequisites..."

# Check if SSH key exists
if [ ! -f ~/.ssh/maint-rsa ]; then
    echo "❌ SSH key ~/.ssh/maint-rsa not found"
    echo "Please create an SSH key pair first:"
    echo "ssh-keygen -t rsa -b 4096 -f ~/.ssh/maint-rsa"
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found"
    echo "Please install Terraform first"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found"
    echo "Please install kubectl first"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

# Validate Terraform configuration
echo "🔧 Validating Terraform configuration..."
terraform validate
if [ $? -ne 0 ]; then
    echo "❌ Terraform validation failed"
    exit 1
fi
echo "✅ Terraform configuration is valid"
echo ""

# Initialize Terraform
echo "📦 Initializing Terraform..."
terraform init
echo ""

# Show deployment plan
echo "📋 Showing deployment plan..."
echo "This will show what resources will be created..."
echo ""
terraform plan -var="bootstrap_cluster=true" -out=tfplan
echo ""

# Confirm deployment
read -p "🤔 Do you want to proceed with the deployment? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    rm -f tfplan
    exit 0
fi

echo ""
echo "🚀 Starting deployment..."
echo "This may take 15-20 minutes..."
echo ""

# Apply Terraform configuration
terraform apply -auto-approve tfplan

# Check deployment status
echo ""
echo "🔍 Checking deployment status..."

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
timeout 300 bash -c 'until kubectl get nodes &>/dev/null; do sleep 5; done'

# Show cluster status
echo ""
echo "📊 Cluster Status:"
echo "=================="
kubectl get nodes -o wide
echo ""

echo "📦 Pod Status:"
echo "=============="
kubectl get pods -A
echo ""

echo "🌐 Service Status:"
echo "=================="
kubectl get svc -A -o wide | grep -E "(LoadBalancer|NodePort)"
echo ""

echo "🎯 Ingress Status:"
echo "=================="
kubectl get ingress -A
echo ""

# Show access information
echo ""
echo "🎉 Deployment Complete!"
echo "======================="
echo ""
echo "📋 Access Information:"
echo "- Grafana: http://grafana.home (admin/admin)"
echo "  └── Includes comprehensive Kubernetes monitoring dashboards"
echo "- Prometheus: http://prometheus.home"
echo "- Loki: http://loki.home"
echo "- Mimir: http://mimir.home"
echo "- Mylar: http://mylar.home"
echo "- NetAlertX: http://netalertx.home"
echo ""
echo "💡 Add these entries to your /etc/hosts file:"
echo "${INGRESS_IP:-192.168.1.40} grafana.home prometheus.home loki.home mimir.home mylar.home netalertx.home"
echo ""
echo "🔧 Useful Commands:"
echo "- Check nodes: kubectl get nodes -o wide"
echo "- Check pods: kubectl get pods -A"
echo "- Check services: kubectl get svc -A"
echo "- Check ingress: kubectl get ingress -A"
echo ""
echo "📚 For more information, see DEPLOYMENT_ORDER.md"
echo ""
echo "Happy monitoring! 🚀"