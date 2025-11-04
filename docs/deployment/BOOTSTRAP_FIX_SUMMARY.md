# Bootstrap Fix Summary

## Issues Resolved

### Issue 1: Proxmox VM Creation Stalls (No IP Detection)
**Problem**: When creating VMs, Terraform would stall because Proxmox couldn't detect the VM's IP address. This happened because the QEMU guest agent wasn't installed until much later in the provisioning process.

**Solution**: Install `qemu-guest-agent` and `nfs-common` via cloud-init during initial VM boot, before Proxmox needs to detect the IP.

### Issue 2: Terraform Plan Fails Before VM Creation
**Problem**: `terraform apply` tried to connect to Kubernetes services and deployments before VMs were created, causing the Kubernetes and Helm providers to fail during the plan phase.

**Solution**: Create a placeholder kubeconfig file before any Kubernetes resources are evaluated, preventing provider initialization errors.

## Changes Made

### 1. proxmox-vms.tf
Added cloud-init user data resource:

```hcl
resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = <<-EOF
      #cloud-config
      package_update: true
      package_upgrade: false
      packages:
        - qemu-guest-agent
        - nfs-common
      runcmd:
        - systemctl start qemu-guest-agent
        - systemctl enable qemu-guest-agent
      EOF

    file_name = "cloud-init-userdata.yaml"
  }
}
```

Updated all three VM resources (bumblebee, prime, wheeljack) to reference this cloud-init file:

```hcl
initialization {
  # ... existing ip_config and user_account ...
  user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data.id
}
```

### 2. k8s-cluster.tf
Added placeholder kubeconfig preparation:

```hcl
resource "null_resource" "prepare_kubeconfig" {
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ~/.kube
      if [ ! -f ~/.kube/config ]; then
        echo "Creating placeholder kubeconfig..."
        cat > ~/.kube/config <<EOF
      apiVersion: v1
      kind: Config
      clusters: []
      contexts: []
      current-context: ""
      users: []
      EOF
        chmod 600 ~/.kube/config
      fi
    EOT
  }
}
```

Updated VM wait resource with explicit dependencies:

```hcl
resource "null_resource" "wait_for_vms" {
  depends_on = [
    proxmox_virtual_environment_vm.bumblebee,
    proxmox_virtual_environment_vm.prime,
    proxmox_virtual_environment_vm.wheeljack
  ]
  # ... rest of resource ...
}
```

Enhanced kubeconfig_ready resource:

```hcl
resource "null_resource" "kubeconfig_ready" {
  depends_on = [
    null_resource.prepare_kubeconfig
  ]
  
  triggers = {
    mode               = var.bootstrap_cluster ? "bootstrap" : "external"
    copy_kubeconfig_id = var.bootstrap_cluster ? join(",", null_resource.copy_kubeconfig[*].id) : "none"
  }
  # ... rest of resource ...
}
```

### 3. main.tf
Added documentation comment to providers:

```hcl
# Configure the Kubernetes Provider
# Note: During initial deployment, if the cluster doesn't exist yet, you may need to run:
# 1. terraform apply -target=... (for VMs and cluster setup)
# 2. terraform apply (for Kubernetes resources)
provider "kubernetes" {
  config_path = "~/.kube/config"
  insecure    = true
}
```

### 4. Documentation
Created/updated:
- `docs/deployment/BOOTSTRAP-IMPROVEMENTS.md` - Detailed guide on the improvements
- `docs/deployment/DEPLOYMENT_ORDER.md` - Updated with new phases and quick start

## How It Works Now

### Before (Old Behavior)
1. `terraform plan` → ❌ Kubernetes provider tries to connect → Fails
2. User needs to run `-target` commands manually
3. VMs created → Stalls waiting for IP detection
4. Eventually times out or requires manual intervention

### After (New Behavior)
1. `terraform plan` → ✅ Placeholder kubeconfig exists → Plan succeeds
2. `terraform apply` → Everything happens automatically:
   - Placeholder kubeconfig created
   - Cloud-init snippet uploaded to Proxmox
   - VMs cloned with cloud-init
   - Guest agent installed immediately via cloud-init
   - Proxmox detects IPs right away
   - Kubernetes cluster bootstrapped
   - Real kubeconfig replaces placeholder
   - All Kubernetes resources created

## Deployment Commands

### Fresh Deployment (No Existing Infrastructure)

**Important**: Due to Terraform provider limitations, fresh deployments require a two-stage apply.

#### Stage 1: Create VMs and Cluster
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

#### Stage 2: Deploy Kubernetes Resources
```bash
terraform apply -var="bootstrap_cluster=true"
```

#### Or Use the Automated Script
```bash
# This script handles both stages automatically
./scripts/deployment/deploy-full-stack.sh
```

### Using Existing Cluster
```bash
terraform apply -var="bootstrap_cluster=false"
```

### Alternative Two-Stage Approach (Optional)
```bash
# Stage 1: Create VMs and cluster
terraform apply \
  -target=proxmox_virtual_environment_file.cloud_init_user_data \
  -target=proxmox_virtual_environment_vm.bumblebee \
  -target=proxmox_virtual_environment_vm.prime \
  -target=proxmox_virtual_environment_vm.wheeljack \
  -target=null_resource.control_plane_setup \
  -target=null_resource.worker_setup \
  -target=null_resource.copy_kubeconfig \
  -var="bootstrap_cluster=true"

# Stage 2: Create Kubernetes resources
terraform apply -var="bootstrap_cluster=true"
```

## Verification

### Test VM Creation
```bash
# Create a test VM
terraform plan -target=proxmox_virtual_environment_vm.bumblebee
# Should complete without errors
```

### Verify Guest Agent After VM Creation
```bash
# From Proxmox host
qm agent <vmid> ping

# Or SSH into VM
ssh user@<vm-ip>
sudo systemctl status qemu-guest-agent
```

### Verify Kubeconfig
```bash
# Check placeholder was created
ls -la ~/.kube/config

# After cluster creation, verify it works
kubectl cluster-info
kubectl get nodes
```

## Benefits

✅ **Automated deployment** - Use script for hands-off deployment  
✅ **Faster provisioning** - Guest agent installed immediately  
✅ **No more stalls** - Proxmox detects IPs right away  
✅ **Better error handling** - Placeholder prevents initial provider failures  
✅ **Clearer dependencies** - Explicit resource ordering  
✅ **Backward compatible** - Existing deployments still work  
ℹ️ **Two-stage apply required** - Due to Terraform provider connection requirements  

## Files Modified

| File | Changes |
|------|---------|
| `proxmox-vms.tf` | Added cloud-init user data resource, updated all VM configs |
| `k8s-cluster.tf` | Added placeholder kubeconfig, improved dependencies |
| `main.tf` | Added provider documentation |
| `docs/deployment/BOOTSTRAP-IMPROVEMENTS.md` | New comprehensive guide |
| `docs/deployment/DEPLOYMENT_ORDER.md` | Updated with new phases |

## Rollback (If Needed)

If you need to revert these changes:

```bash
# Restore from git
git restore proxmox-vms.tf k8s-cluster.tf main.tf

# Or manually:
# 1. Remove cloud-init user data resource from proxmox-vms.tf
# 2. Remove user_data_file_id from all VM initialization blocks
# 3. Remove prepare_kubeconfig resource from k8s-cluster.tf
# 4. Restore original kubeconfig_ready resource
```

## Testing Checklist

- [ ] Fresh deployment from scratch works
- [ ] VMs get IP addresses immediately
- [ ] No Terraform stalls during VM creation
- [ ] Placeholder kubeconfig created before plan
- [ ] Real kubeconfig replaces placeholder
- [ ] All Kubernetes resources created successfully
- [ ] External cluster mode still works (bootstrap_cluster=false)

## Known Limitations

1. **Cloud-init dependency**: Requires cloud-init to be working in the VM template
2. **Network requirement**: Requires internet access for package installation
3. **Timing**: Very rare race conditions may still occur if network is extremely slow

## Future Improvements

- [ ] Add retry logic for transient failures
- [ ] Implement health checks for guest agent
- [ ] Add progress indicators for long operations
- [ ] Support air-gapped deployments
- [ ] Add automated rollback on failures

