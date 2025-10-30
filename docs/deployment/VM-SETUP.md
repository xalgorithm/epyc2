# VM Setup Guide for Proxmox

This guide explains how to create the required VMs for your Kubernetes cluster on Proxmox 8.4.14.

## Prerequisites

### 1. Proxmox Template
You need an Ubuntu 22.04 cloud-init template in Proxmox. If you don't have one:

```bash
# On your Proxmox host, create a template:
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

### 2. Update Configuration
Edit `terraform.tfvars` with your Proxmox details:

```hcl
# Proxmox Configuration
proxmox_api_url      = "https://YOUR_PROXMOX_IP:8006/api2/json"
proxmox_user         = "root@pam"
proxmox_password     = "YOUR_PROXMOX_PASSWORD"
proxmox_node         = "YOUR_NODE_NAME"  # Usually "pve"
vm_template          = "ubuntu-22.04-template"
vm_storage           = "local-lvm"       # Your storage pool
vm_network_bridge    = "vmbr0"          # Your network bridge
```

## VM Specifications

The deployment will create 3 VMs with these specifications:

### Prime (Worker 1)
- **Name**: prime
- **IP**: 192.168.1.32
- **Role**: Kubernetes Worker Node
- **CPU**: 8 cores (host type)
- **RAM**: 16GB
- **Disk**: 256GB (SCSI with iothread)
- **OS**: Ubuntu 22.04

### Bumblebee (Control Plane)
- **Name**: bumblebee
- **IP**: 192.168.1.33
- **Role**: Kubernetes Control Plane
- **CPU**: 8 cores (host type)
- **RAM**: 16GB
- **Disk**: 256GB (SCSI with iothread)
- **OS**: Ubuntu 22.04

### Wheeljack (Worker 2)
- **Name**: wheeljack
- **IP**: 192.168.1.34
- **Role**: Kubernetes Worker Node
- **CPU**: 8 cores (host type)
- **RAM**: 16GB
- **Disk**: 256GB (SCSI with iothread)
- **OS**: Ubuntu 22.04

## Deployment Steps

### 1. Prepare SSH Keys
Ensure your SSH keys are in place:

```bash
# Check if keys exist
ls -la ~/.ssh/maint-rsa*

# If not, create them:
ssh-keygen -t rsa -b 4096 -f ~/.ssh/maint-rsa -N ""

# Generate public key if missing:
ssh-keygen -y -f ~/.ssh/maint-rsa > ~/.ssh/maint-rsa.pub
```

### 2. Initialize Terraform
```bash
terraform init
```

### 3. Validate Configuration
```bash
terraform validate
terraform plan
```

### 4. Deploy VMs and Cluster
Use the automated deployment script:

```bash
./scripts/deploy-with-vms.sh
```

Or deploy manually:

```bash
# Create VMs first
terraform apply -target=proxmox_vm_qemu.bumblebee -target=proxmox_vm_qemu.prime -target=proxmox_vm_qemu.wheeljack

# Wait for VMs to boot (2-3 minutes)
sleep 180

# Deploy Kubernetes cluster
terraform apply
```

## Verification

### 1. Check VM Status in Proxmox
- Log into Proxmox web interface
- Verify all 3 VMs are running
- Check that they have the correct IPs assigned

### 2. Test SSH Connectivity
```bash
ssh -i ~/.ssh/maint-rsa xalg@192.168.1.32  # Prime
ssh -i ~/.ssh/maint-rsa xalg@192.168.1.33  # Bumblebee
ssh -i ~/.ssh/maint-rsa xalg@192.168.1.34  # Wheeljack
```

### 3. Check Kubernetes Cluster
```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
```

## Troubleshooting

### VM Creation Issues
1. **Template not found**: Ensure the template name matches exactly
2. **Storage issues**: Check that the storage pool exists and has space
3. **Network issues**: Verify the bridge name is correct

### SSH Connection Issues
1. **Keys not working**: Check key permissions (`chmod 600 ~/.ssh/maint-rsa`)
2. **Network unreachable**: Verify VM network configuration
3. **Cloud-init not working**: Check VM has cloud-init disk attached

### Kubernetes Issues
1. **Nodes not joining**: Check firewall rules and network connectivity
2. **Services not accessible**: Verify MetalLB configuration
3. **Pods not starting**: Check resource availability

## Manual Cleanup

If you need to start over:

```bash
# Destroy everything
terraform destroy

# Or just VMs
terraform destroy -target=proxmox_vm_qemu.bumblebee -target=proxmox_vm_qemu.prime -target=proxmox_vm_qemu.wheeljack
```

## Network Configuration

The VMs will be configured with:
- **Gateway**: 192.168.1.1
- **Subnet**: 192.168.1.0/24
- **DNS**: Inherited from Proxmox/Gateway

Ensure your network supports these IPs and they don't conflict with existing devices.