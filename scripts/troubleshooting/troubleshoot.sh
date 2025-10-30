#!/bin/bash

echo "=== Kubernetes Cluster Troubleshooting ==="
echo ""

# Check SSH connectivity
echo "1. Checking SSH connectivity..."
ssh_key_path=$(grep ssh_private_key_path terraform.tfvars | cut -d '"' -f 2 | sed 's|~|'$HOME'|')
control_plane_ip=$(grep control_plane_ip terraform.tfvars | cut -d '"' -f 2)
worker_ips=$(grep -A 2 worker_ips terraform.tfvars | grep -o '192\.168\.0\.[0-9]*')

echo "Testing SSH to control plane ($control_plane_ip)..."
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$ssh_key_path" ubuntu@$control_plane_ip "echo 'SSH OK'" 2>/dev/null; then
    echo "✓ Control plane SSH: OK"
else
    echo "✗ Control plane SSH: FAILED"
fi

for worker_ip in $worker_ips; do
    echo "Testing SSH to worker ($worker_ip)..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$ssh_key_path" ubuntu@$worker_ip "echo 'SSH OK'" 2>/dev/null; then
        echo "✓ Worker $worker_ip SSH: OK"
    else
        echo "✗ Worker $worker_ip SSH: FAILED"
    fi
done

echo ""
echo "2. Checking if Kubernetes components are installed on control plane..."
ssh -o StrictHostKeyChecking=no -i "$ssh_key_path" ubuntu@$control_plane_ip "
    echo 'Checking kubeadm...'
    if command -v kubeadm &> /dev/null; then
        echo '✓ kubeadm: $(kubeadm version -o short)'
    else
        echo '✗ kubeadm: NOT FOUND'
    fi
    
    echo 'Checking kubelet...'
    if command -v kubelet &> /dev/null; then
        echo '✓ kubelet: $(kubelet --version)'
    else
        echo '✗ kubelet: NOT FOUND'
    fi
    
    echo 'Checking kubectl...'
    if command -v kubectl &> /dev/null; then
        echo '✓ kubectl: $(kubectl version --client --short)'
    else
        echo '✗ kubectl: NOT FOUND'
    fi
    
    echo 'Checking containerd...'
    if systemctl is-active containerd &> /dev/null; then
        echo '✓ containerd: RUNNING'
    else
        echo '✗ containerd: NOT RUNNING'
    fi
" 2>/dev/null

echo ""
echo "3. Checking Terraform state..."
if [ -f "terraform.tfstate" ]; then
    echo "✓ Terraform state file exists"
    if terraform show &> /dev/null; then
        echo "✓ Terraform state is valid"
    else
        echo "✗ Terraform state may be corrupted"
    fi
else
    echo "✗ No terraform.tfstate file found"
fi

echo ""
echo "4. Checking kubeconfig..."
if [ -f "$HOME/.kube/config" ]; then
    echo "✓ Kubeconfig file exists"
    if kubectl cluster-info &> /dev/null; then
        echo "✓ Can connect to cluster"
        kubectl get nodes 2>/dev/null || echo "✗ Cannot get nodes"
    else
        echo "✗ Cannot connect to cluster"
    fi
else
    echo "✗ No kubeconfig file found"
fi

echo ""
echo "=== Troubleshooting Complete ==="
echo ""
echo "Common solutions:"
echo "1. If SSH fails: Check SSH key path and VM accessibility"
echo "2. If Kubernetes components missing: Run 'terraform destroy' then 'terraform apply'"
echo "3. If cluster connection fails: Check if control plane is running"
echo "4. For detailed logs: Check /var/log/syslog on the VMs"
