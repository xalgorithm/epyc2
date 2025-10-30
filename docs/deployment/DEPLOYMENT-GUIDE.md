# Complete Deployment Guide

This guide provides step-by-step instructions for deploying the Kubernetes homelab infrastructure.

## 🔑 Prerequisites

### 1. SSH Key Setup
Ensure you have SSH keys configured:

```bash
# Check if SSH keys exist
ls -la ~/.ssh/id_ed25519*

# If not, create them
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Generate public key if missing
# Public key is automatically generated with ed25519

# Set correct permissions
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

### 2. Proxmox Template
Create Ubuntu 22.04 template in Proxmox (ID: 9000):

```bash
# SSH to Proxmox host
ssh root@YOUR_PROXMOX_IP

# Create template
cd /tmp
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
qm create 9000 --name ubuntu-22.04-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9000 jammy-server-cloudimg-amd64.img local-lvm
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent enabled=1
qm template 9000
```

### 3. Configuration
Update `terraform.tfvars` with your environment:

```hcl
# Proxmox Configuration
proxmox_api_url           = "https://YOUR_PROXMOX_IP:8006/api2/json"
proxmox_user              = "root@pam"  # fallback user
proxmox_password          = "your_password"  # fallback password
proxmox_api_token_id      = "user@pam!tokenname"  # API token (recommended)
proxmox_api_token_secret  = "your-token-secret"   # API token secret
proxmox_node              = "pve"
vm_template               = "ubuntu-22.04-template"
vm_template_id            = 9000
vm_storage                = "local-lvm"
vm_network_bridge         = "vmbr0"

# SSH Configuration
ssh_user             = "xalg"
ssh_private_key_path = "~/.ssh/id_ed25519"
```

## 🚀 Deployment Options

### Option 1: Automated Deployment (Recommended)

```bash
# Run the enhanced deployment script
./scripts/deploy-with-cloud-init-wait.sh
```

This script will:
1. Create VMs in Proxmox
2. Wait for cloud-init completion
3. Copy SSH keys to all nodes
4. Deploy Kubernetes cluster
5. Deploy monitoring and applications

### Option 2: Manual Step-by-Step Deployment

#### Step 1: Create VMs
```bash
terraform apply -target=proxmox_virtual_environment_vm.prime \
                -target=proxmox_virtual_environment_vm.bumblebee \
                -target=proxmox_virtual_environment_vm.wheeljack
```

#### Step 2: Wait for VMs to Boot
```bash
# Wait 2-3 minutes for VMs to fully boot
sleep 180

# Test SSH connectivity
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.1.10 "echo 'Prime ready'"
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.1.11 "echo 'Bumblebee ready'"
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.1.12 "echo 'Wheeljack ready'"
```

#### Step 3: Copy SSH Keys (Critical!)
```bash
# Copy SSH keys to all nodes for inter-node communication
./scripts/copy-ssh-keys.sh
```

#### Step 4: Deploy Kubernetes
```bash
# Deploy Kubernetes cluster
terraform apply -target=null_resource.control_plane_setup \
                -target=null_resource.worker_setup \
                -target=null_resource.copy_kubeconfig
```

#### Step 5: Deploy Applications
```bash
# Deploy monitoring, backup, and media services
terraform apply
```

### Option 3: VM Creation Only
```bash
# Just create VMs without Kubernetes
./scripts/create-vms-only.sh

# Then copy SSH keys
./scripts/copy-ssh-keys.sh

# Then deploy Kubernetes manually
terraform apply
```

## 🔍 Verification Steps

### 1. Check VM Status
```bash
# Test SSH to all VMs
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.1.10 "hostname && uptime"
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.1.11 "hostname && uptime"
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.1.12 "hostname && uptime"
```

### 2. Verify Cloud-Init Completion
```bash
# Check cloud-init status on each VM
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.1.11 "sudo cloud-init status"
```

### 3. Test Inter-Node SSH
```bash
# Test SSH from control plane to workers
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.1.11 "
  ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_ed25519 ubuntu@192.168.1.10 'echo Prime reachable'
  ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_ed25519 ubuntu@192.168.1.12 'echo Wheeljack reachable'
"
```

### 4. Check Kubernetes Cluster
```bash
# Verify cluster status
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
```

### 5. Check Services
```bash
# Get LoadBalancer IPs
kubectl get svc -n monitoring | grep LoadBalancer
kubectl get svc -n media | grep LoadBalancer
```

## 🛠️ Troubleshooting

### SSH Key Issues
```bash
# If SSH keys are missing on nodes
./scripts/copy-ssh-keys.sh

# Check SSH key permissions
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.1.11 "ls -la ~/.ssh/"
```

### Cloud-Init Issues
```bash
# Check cloud-init logs
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.1.11 "
  sudo cloud-init status --long
  sudo tail -20 /var/log/cloud-init-output.log
"
```

### APT Lock Issues
```bash
# Check for stuck apt processes
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.1.11 "
  sudo lsof /var/lib/apt/lists/lock
  sudo ps aux | grep apt
"
```

### Kubernetes Issues
```bash
# Check kubelet status
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.1.11 "
  sudo systemctl status kubelet
  sudo journalctl -u kubelet --no-pager -l
"
```

## 📋 VM Specifications

After deployment, you'll have:

- **Prime** (192.168.1.10): Worker node - 8 cores, 16GB RAM, 256GB disk
- **Bumblebee** (192.168.1.11): Control plane - 8 cores, 16GB RAM, 256GB disk
- **Wheeljack** (192.168.1.12): Worker node - 8 cores, 16GB RAM, 256GB disk

## 🌐 Service Access

Once deployed, access services via LoadBalancer IPs:

```bash
# Get service URLs
kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
kubectl get svc prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
kubectl get svc mylar -n media -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

- **Grafana**: `http://<grafana-ip>:3000` (admin/admin)
- **Prometheus**: `http://<prometheus-ip>:9090`
- **Mylar**: `http://<mylar-ip>:8090`

## 🔄 Cleanup

To start over:

```bash
# Delete everything
terraform destroy

# Or just VMs
./scripts/delete-vms.sh
```

---

This deployment process ensures proper SSH key distribution and cloud-init handling for reliable cluster setup! 🚀