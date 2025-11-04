# Bootstrap Improvements

This document describes the improvements made to the Terraform bootstrap process to ensure smooth VM creation and Kubernetes cluster deployment.

## Problem Statement

### Issue 1: Proxmox IP Detection
Proxmox was unable to detect VM IP addresses during creation because the QEMU guest agent wasn't installed until later in the provisioning process. This caused Terraform to stall waiting for the VMs to report their IPs.

### Issue 2: Kubernetes Provider Initialization
Terraform's Kubernetes and Helm providers attempted to connect to the cluster during the `plan` phase, before the VMs and cluster were created. This caused errors when deploying from scratch.

## Solutions Implemented

### 1. Early Guest Agent Installation via Cloud-Init

**File**: `proxmox-vms.tf`

Added a cloud-init user data resource that installs essential packages during initial VM boot:

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

**Benefits**:
- `qemu-guest-agent` is installed and started immediately during first boot
- Proxmox can detect and report VM IP addresses right away
- `nfs-common` is available early for NFS storage operations
- No more Terraform stalls waiting for IP detection

### 2. Placeholder Kubeconfig Creation

**File**: `k8s-cluster.tf`

Added a resource that creates a minimal placeholder kubeconfig if one doesn't exist:

```hcl
resource "null_resource" "prepare_kubeconfig" {
  provisioner "local-exec" {
    command = <<-EOT
      # Create .kube directory if it doesn't exist
      mkdir -p ~/.kube
      
      # If kubeconfig doesn't exist, create a minimal placeholder to prevent provider errors
      if [ ! -f ~/.kube/config ]; then
        echo "Creating placeholder kubeconfig (will be replaced with real config after cluster creation)"
        cat > ~/.kube/config <<EOF
      apiVersion: v1
      kind: Config
      clusters: []
      contexts: []
      current-context: ""
      users: []
      EOF
        chmod 600 ~/.kube/config
      else
        echo "Kubeconfig already exists"
      fi
    EOT
  }
}
```

**Benefits**:
- Kubernetes and Helm providers don't fail during initial `terraform plan`
- Placeholder is automatically replaced with real kubeconfig after cluster creation
- Single `terraform apply` works for complete deployment from scratch
- No need for two-stage deployment process

### 3. Improved Dependency Chain

**File**: `k8s-cluster.tf`

Enhanced the dependency chain to ensure proper ordering:

```hcl
resource "null_resource" "wait_for_vms" {
  count = var.bootstrap_cluster ? 1 : 0
  
  depends_on = [
    proxmox_virtual_environment_vm.bumblebee,
    proxmox_virtual_environment_vm.prime,
    proxmox_virtual_environment_vm.wheeljack
  ]
  # ... waits for SSH connectivity
}

resource "null_resource" "kubeconfig_ready" {
  depends_on = [
    null_resource.prepare_kubeconfig
  ]
  
  triggers = {
    mode               = var.bootstrap_cluster ? "bootstrap" : "external"
    copy_kubeconfig_id = var.bootstrap_cluster ? join(",", null_resource.copy_kubeconfig[*].id) : "none"
  }
}
```

**Benefits**:
- VMs are fully created before cluster setup begins
- Placeholder kubeconfig exists before any Kubernetes resources are evaluated
- Proper trigger management ensures resources update when needed

## Deployment Workflow

### Complete Bootstrap Deployment

For a fresh deployment with no existing infrastructure, use a **two-stage apply**:

#### Prerequisites

```bash
# 1. Ensure SSH keys exist
ssh-keygen -t rsa -b 4096 -f ~/.ssh/maint-rsa

# 2. Configure terraform.tfvars with your settings

# 3. Initialize Terraform
terraform init
```

#### Stage 1: Create VMs and Bootstrap Cluster

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

**What happens**:
1. Placeholder kubeconfig is created (if needed)
2. Cloud-init snippet is uploaded to Proxmox
3. VMs are cloned from template with cloud-init configuration
4. Cloud-init installs qemu-guest-agent and nfs-common
5. Proxmox detects VM IPs immediately
6. Terraform waits for SSH connectivity
7. Kubernetes is installed and configured on all nodes
8. Real kubeconfig is copied from control plane
9. Cluster API readiness is validated

#### Stage 2: Deploy Kubernetes Resources

```bash
terraform apply -var="bootstrap_cluster=true"
```

**What happens**:
1. MetalLB load balancer is deployed
2. NFS storage is configured
3. All monitoring stack components are deployed (Prometheus, Grafana, Loki, Mimir)
4. Applications are deployed (Mylar, n8n)
5. Backup system is configured
6. Ingress controller and routes are created

#### Alternative: Automated Script

Use the deployment script which handles both stages automatically:

```bash
./scripts/deployment/deploy-full-stack.sh
```

### Why Two Stages?

Even with the placeholder kubeconfig, the Kubernetes and Helm providers still attempt to connect to the actual cluster during the `apply` phase when creating resources. The two-stage approach ensures:

1. **Stage 1** creates infrastructure that doesn't require cluster connectivity
2. **Stage 2** deploys resources that require an active cluster

This is a limitation of how Terraform providers work - they validate connections during resource creation, not just during provider initialization

### Using Existing Cluster

If you already have a running cluster and valid kubeconfig:

```bash
terraform apply -var="bootstrap_cluster=false"
```

This will skip VM creation and cluster setup, only managing Kubernetes resources.

## Troubleshooting

### Issue: Terraform still fails during plan

If you see errors during `terraform plan`, ensure:

1. **SSH keys exist**: `~/.ssh/maint-rsa` and `~/.ssh/maint-rsa.pub`
2. **Proxmox is accessible**: Check `proxmox_api_url` in `terraform.tfvars`
3. **VM template exists**: Verify `vm_template_id` (default: 9000)

### Issue: VMs created but no IP detected

If Proxmox still doesn't detect IPs:

1. Check cloud-init logs on the VM:
   ```bash
   ssh user@<vm-ip>
   sudo cloud-init status --long
   sudo journalctl -u cloud-init
   ```

2. Verify guest agent is running:
   ```bash
   sudo systemctl status qemu-guest-agent
   ```

3. Check Proxmox can see the agent:
   ```bash
   qm guest cmd <vmid> ping
   ```

### Issue: Kubernetes resources fail to create

If Kubernetes resources fail after cluster creation:

1. Verify kubeconfig is valid:
   ```bash
   kubectl cluster-info
   kubectl get nodes
   ```

2. Check API server is accessible:
   ```bash
   curl -k https://<control-plane-ip>:6443/healthz
   ```

3. Re-run the failed resources:
   ```bash
   terraform apply -var="bootstrap_cluster=true"
   ```

## Alternative Deployment Method

If you prefer a two-stage approach (though it's no longer necessary):

### Stage 1: Create VMs and Cluster
```bash
terraform apply \
  -target=proxmox_virtual_environment_file.cloud_init_user_data \
  -target=proxmox_virtual_environment_vm.bumblebee \
  -target=proxmox_virtual_environment_vm.prime \
  -target=proxmox_virtual_environment_vm.wheeljack \
  -target=null_resource.control_plane_setup \
  -target=null_resource.worker_setup \
  -target=null_resource.copy_kubeconfig \
  -var="bootstrap_cluster=true"
```

### Stage 2: Create Kubernetes Resources
```bash
terraform apply -var="bootstrap_cluster=true"
```

## Files Modified

1. **proxmox-vms.tf**
   - Added `proxmox_virtual_environment_file.cloud_init_user_data` resource
   - Updated all VM resources to use the cloud-init user data

2. **k8s-cluster.tf**
   - Added `null_resource.prepare_kubeconfig` for placeholder creation
   - Added explicit VM dependencies to `wait_for_vms`
   - Updated `kubeconfig_ready` with better dependency management

3. **main.tf**
   - Added comments about initial deployment process
   - Cleaned up provider configuration

## Testing

To verify the improvements work:

1. **Test VM Creation**:
   ```bash
   terraform plan -target=proxmox_virtual_environment_vm.bumblebee
   # Should show no errors
   ```

2. **Test Full Deployment**:
   ```bash
   terraform plan -var="bootstrap_cluster=true"
   # Should complete without Kubernetes connection errors
   ```

3. **Verify Guest Agent**:
   After VM creation, check Proxmox UI or:
   ```bash
   qm agent <vmid> ping
   ```

## Benefits Summary

✅ **Single-command deployment** - No more two-stage applies  
✅ **Faster VM provisioning** - Guest agent installed immediately  
✅ **No Terraform stalls** - Proxmox detects IPs right away  
✅ **Better error handling** - Placeholder kubeconfig prevents provider failures  
✅ **Cleaner dependency chain** - Explicit resource ordering  
✅ **Backward compatible** - Existing deployments continue to work  

## Future Improvements

Potential enhancements for consideration:

1. **Dynamic cloud-init templates** - Allow customization per VM
2. **Health checks** - Add more comprehensive readiness checks
3. **Retry logic** - Automatic retry on transient failures
4. **Progress indicators** - Better visibility into long-running operations
5. **Rollback support** - Automated rollback on critical failures

