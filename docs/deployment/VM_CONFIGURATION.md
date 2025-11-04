# Proxmox VM Configuration

## VM Mapping

| VM Name   | VM ID | IP Address    | Role          | Resources        |
|-----------|-------|---------------|---------------|------------------|
| bumblebee | 100   | 192.168.0.32  | Control Plane | 8 CPU, 16GB RAM  |
| wheeljack | 101   | 192.168.0.33  | Worker Node   | 8 CPU, 16GB RAM  |
| prime     | 103   | 192.168.0.34  | Worker Node   | 8 CPU, 16GB RAM  |

## Configuration Details

### bumblebee (VM ID 100)
- **Role**: Kubernetes Control Plane
- **IP**: 192.168.0.32
- **CPU**: 8 cores (host type)
- **Memory**: 16GB
- **Disk**: 256GB (SCSI with iothread)
- **Network**: virtio on vmbr0
- **Guest Agent**: Installed via cloud-init ✅
- **NFS Common**: Installed via cloud-init ✅

### wheeljack (VM ID 101)
- **Role**: Kubernetes Worker Node
- **IP**: 192.168.0.33
- **CPU**: 8 cores (host type)
- **Memory**: 16GB
- **Disk**: 256GB (SCSI with iothread)
- **Network**: virtio on vmbr0
- **Guest Agent**: Installed via cloud-init ✅
- **NFS Common**: Installed via cloud-init ✅

### prime (VM ID 103)
- **Role**: Kubernetes Worker Node
- **IP**: 192.168.0.34
- **CPU**: 8 cores (host type)
- **Memory**: 16GB
- **Disk**: 256GB (SCSI with iothread)
- **Network**: virtio on vmbr0
- **Guest Agent**: Installed via cloud-init ✅
- **NFS Common**: Installed via cloud-init ✅

## Configuration in terraform.tfvars

```hcl
control_plane_ip = "192.168.0.32"  # bumblebee (VM ID 100)
worker_ips       = ["192.168.0.34", "192.168.0.33"]  # prime (103), wheeljack (101)
worker_names     = ["prime", "wheeljack"]
```

## Configuration in proxmox-vms.tf

Each VM resource now includes a specific `vm_id`:

```hcl
resource "proxmox_virtual_environment_vm" "bumblebee" {
  vm_id     = 100
  name      = "bumblebee"
  # ...
}

resource "proxmox_virtual_environment_vm" "prime" {
  vm_id     = 103
  name      = "prime"
  # ...
}

resource "proxmox_virtual_environment_vm" "wheeljack" {
  vm_id     = 101
  name      = "wheeljack"
  # ...
}
```

## Network Configuration

- **Gateway**: 192.168.0.1
- **Bridge**: vmbr0
- **Network Model**: virtio
- **Subnet**: /24 (255.255.255.0)

## Cloud-Init Configuration

All VMs use the same cloud-init snippet that:
- Installs `qemu-guest-agent` (enables Proxmox IP detection)
- Installs `nfs-common` (enables NFS storage)
- Starts and enables guest agent service
- Configures SSH user (`ubuntu`) with public key (`~/.ssh/maint-rsa.pub`)

## Storage Configuration

- **Datastore**: local-lvm (or configured value)
- **Interface**: SCSI0
- **Controller**: virtio-scsi-single
- **iothread**: Enabled for better performance
- **Size**: 256GB per VM

## Cloning Source

All VMs are cloned from:
- **Template ID**: 9000 (or configured value)
- **Clone Type**: Full clone

## Lifecycle Management

VMs are configured to:
- Start automatically on boot: `on_boot = true`
- Start after creation: `started = true`
- Ignore agent configuration changes in updates

## Important Notes

### VM ID Assignment
- VM IDs are **hardcoded** in the configuration
- If VMs with these IDs already exist, Terraform will:
  - **Option 1**: Fail with a conflict error
  - **Option 2**: Try to import existing VMs (if you run import commands)

### If VMs Already Exist

If these VM IDs are already in use, you have options:

1. **Destroy existing VMs**:
   ```bash
   # In Proxmox
   qm destroy 100
   qm destroy 101
   qm destroy 103
   ```

2. **Import existing VMs**:
   ```bash
   terraform import proxmox_virtual_environment_vm.bumblebee 100
   terraform import proxmox_virtual_environment_vm.wheeljack 101
   terraform import proxmox_virtual_environment_vm.prime 103
   ```

3. **Use different VM IDs**:
   - Change the `vm_id` values in `proxmox-vms.tf`

### IP Address Verification

After VMs are created, verify IPs match:
```bash
# In Proxmox
qm guest cmd 100 network-get-interfaces
qm guest cmd 101 network-get-interfaces
qm guest cmd 103 network-get-interfaces

# Or SSH test
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.32  # bumblebee
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.33  # wheeljack
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.34  # prime
```

## Deployment Commands

With these VM IDs configured, you can deploy using:

### Stage 1: Create VMs and Bootstrap Cluster
```bash
terraform apply \
  -target=proxmox_virtual_environment_file.cloud_init_user_data \
  -target=proxmox_virtual_environment_vm.bumblebee \
  -target=proxmox_virtual_environment_vm.prime \
  -target=proxmox_virtual_environment_vm.wheeljack \
  -target=null_resource.prepare_kubeconfig \
  -target=null_resource.wait_for_vms \
  -target=null_resource.control_plane_setup \
  -target=null_resource.worker_setup \
  -target=null_resource.copy_kubeconfig \
  -target=null_resource.kubeconfig_ready \
  -target=null_resource.cluster_api_ready \
  -var="bootstrap_cluster=true"
```

### Stage 2: Deploy Kubernetes Resources
```bash
terraform apply -var="bootstrap_cluster=true"
```

## Output Information

After deployment, Terraform will output:

```
vm_info = {
  bumblebee = {
    vm_id = 100
    name  = "bumblebee"
    ip    = "192.168.0.32"
    role  = "control-plane"
    disk  = "256GB"
  }
  prime = {
    vm_id = 103
    name  = "prime"
    ip    = "192.168.0.34"
    role  = "worker"
    disk  = "256GB"
  }
  wheeljack = {
    vm_id = 101
    name  = "wheeljack"
    ip    = "192.168.0.33"
    role  = "worker"
    disk  = "256GB"
  }
}
```

## Verification Checklist

After deployment, verify:

- [ ] All 3 VMs exist in Proxmox with correct IDs
- [ ] All VMs have correct IP addresses
- [ ] Guest agent is running on all VMs
- [ ] SSH access works to all VMs
- [ ] Kubernetes cluster is healthy
- [ ] All nodes are in "Ready" state

```bash
# Verify Kubernetes cluster
kubectl get nodes -o wide

# Should show:
# NAME        STATUS   ROLES           AGE   VERSION   INTERNAL-IP      ...
# bumblebee   Ready    control-plane   ...   ...       192.168.0.32     ...
# prime       Ready    <none>          ...   ...       192.168.0.34     ...
# wheeljack   Ready    <none>          ...   ...       192.168.0.33     ...
```

