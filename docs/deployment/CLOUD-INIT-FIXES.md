# Cloud-Init and VM Readiness Fixes

This document explains the fixes implemented to handle cloud-init completion and VM readiness issues.

## 🐛 Problems Identified

### 1. APT Lock Conflicts
```
E: Could not get lock /var/lib/apt/lists/lock. It is held by process 1514 (apt-get)
E: Unable to lock directory /var/lib/apt/lists/
```
**Cause**: Terraform was trying to run `apt-get` commands while cloud-init was still running its own package updates.

### 2. Premature Script Execution
**Cause**: Kubernetes setup scripts were running before VMs were fully initialized and cloud-init had completed.

### 3. SCSI Controller Warning
```
WARN: iothread is only valid with virtio disk or virtio-scsi-single controller, ignoring
```
**Cause**: Using iothread with default SCSI controller instead of virtio-scsi-single.

## ✅ Solutions Implemented

### 1. Cloud-Init Wait Mechanism
Added proper waiting for cloud-init completion in `k8s-cluster.tf`:

```bash
# Wait for cloud-init to complete
sudo cloud-init status --wait

# Wait for apt locks to be released
timeout 300 bash -c 'while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do 
  echo "Waiting for apt lock..."; sleep 5; 
done'

timeout 300 bash -c 'while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do 
  echo "Waiting for dpkg lock..."; sleep 5; 
done'
```

### 2. SCSI Controller Fix
Updated VM configuration in `proxmox-vms.tf`:

```hcl
# SCSI Controller for iothread support
scsi_hardware = "virtio-scsi-single"

# Disk Configuration - 256GB
disk {
  datastore_id = var.vm_storage
  interface    = "scsi0"
  iothread     = true
  size         = 256
}
```

### 3. Enhanced Deployment Script
Created `scripts/deploy-with-cloud-init-wait.sh` with:
- VM creation with proper waiting
- SSH connectivity verification
- Cloud-init completion checks
- APT lock release verification
- Staged deployment (VMs → Kubernetes → Applications)

## 🚀 Deployment Process

### Stage 1: VM Creation
```bash
terraform apply -target=proxmox_virtual_environment_vm.prime \
                -target=proxmox_virtual_environment_vm.bumblebee \
                -target=proxmox_virtual_environment_vm.wheeljack
```

### Stage 2: Wait for Readiness
For each VM:
1. Wait for SSH connectivity
2. Wait for cloud-init completion: `sudo cloud-init status --wait`
3. Wait for APT locks to be released
4. Verify system is ready

### Stage 3: Kubernetes Deployment
```bash
terraform apply -target=null_resource.control_plane_setup \
                -target=null_resource.worker_setup \
                -target=null_resource.copy_kubeconfig
```

### Stage 4: Applications
```bash
terraform apply  # Deploy monitoring, backup, and media services
```

## 🛠️ Manual Verification Commands

### Check Cloud-Init Status
```bash
# On each VM
sudo cloud-init status
sudo cloud-init status --wait

# Check cloud-init logs
sudo tail -f /var/log/cloud-init-output.log
```

### Check APT Locks
```bash
# Check if apt is running
sudo fuser /var/lib/apt/lists/lock
sudo fuser /var/lib/dpkg/lock-frontend

# Wait for locks to be released
while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do 
  echo "Waiting for apt lock..."; sleep 5; 
done
```

### Verify VM Readiness
```bash
# Test SSH connectivity
ssh -i ~/.ssh/maint-rsa xalg@192.168.1.32 "echo 'Prime ready'"
ssh -i ~/.ssh/maint-rsa xalg@192.168.1.33 "echo 'Bumblebee ready'"
ssh -i ~/.ssh/maint-rsa xalg@192.168.1.34 "echo 'Wheeljack ready'"

# Check system status
ssh -i ~/.ssh/maint-rsa xalg@192.168.1.33 "
  sudo cloud-init status
  sudo systemctl is-active qemu-guest-agent
  free -h
  df -h
"
```

## 📋 Best Practices

### 1. Always Wait for Cloud-Init
Never run provisioning scripts until cloud-init completes:
```bash
sudo cloud-init status --wait
```

### 2. Handle APT Locks Gracefully
Use timeouts to avoid infinite waits:
```bash
timeout 300 bash -c 'while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do 
  sleep 5; 
done'
```

### 3. Use Proper SCSI Controllers
For iothread support:
```hcl
scsi_hardware = "virtio-scsi-single"
```

### 4. Staged Deployment
Deploy in stages to handle dependencies:
1. Infrastructure (VMs)
2. Wait for readiness
3. Core services (Kubernetes)
4. Applications

## 🔍 Troubleshooting

### Cloud-Init Issues
```bash
# Check cloud-init status
sudo cloud-init status --long

# View cloud-init logs
sudo journalctl -u cloud-init
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log
```

### APT Lock Issues
```bash
# Find processes using apt
sudo lsof /var/lib/apt/lists/lock
sudo lsof /var/lib/dpkg/lock-frontend

# Kill stuck apt processes (use carefully)
sudo killall apt-get
sudo killall dpkg
```

### VM Boot Issues
```bash
# Check VM status in Proxmox
qm status VMID

# Check VM logs
qm monitor VMID
info status
```

## 📚 References

- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
- [Proxmox Cloud-Init Guide](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [BPG Proxmox Provider Docs](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)

---

These fixes ensure reliable VM deployment and Kubernetes cluster initialization! 🚀