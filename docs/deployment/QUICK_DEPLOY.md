# Quick Deployment Guide

## Current Situation

You're getting errors because Terraform is trying to connect to the Kubernetes cluster before it exists. This requires a **two-stage deployment**.

## Solution: Two-Stage Deployment

### Stage 1: Create VMs and Kubernetes Cluster

Run this command to create the VMs and bootstrap the cluster:

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

**What this does:**
- Creates placeholder kubeconfig
- Uploads cloud-init configuration to Proxmox
- Creates 3 VMs (bumblebee, prime, wheeljack)
- Installs qemu-guest-agent and nfs-common via cloud-init
- Bootstraps Kubernetes on all nodes
- Copies real kubeconfig to your local machine
- Validates cluster API is accessible

**Expected time:** 10-15 minutes

### Verify Cluster is Ready

After Stage 1 completes, verify the cluster is working:

```bash
kubectl cluster-info
kubectl get nodes
```

You should see all 3 nodes in "Ready" state.

### Stage 2: Deploy Kubernetes Resources

Once the cluster is ready, deploy all remaining resources:

```bash
terraform apply -var="bootstrap_cluster=true"
```

**What this does:**
- Deploys MetalLB load balancer
- Configures NFS storage
- Deploys monitoring stack (Prometheus, Grafana, Loki, Mimir)
- Deploys applications (Mylar, n8n)
- Configures backups
- Sets up Ingress

**Expected time:** 5-10 minutes

## Alternative: Use the Automated Script

Instead of running commands manually, use the deployment script which now handles both stages automatically:

```bash
./scripts/deployment/deploy-full-stack.sh
```

This script will:
1. Check prerequisites
2. Run Stage 1 (VMs + cluster)
3. Wait for cluster to stabilize
4. Run Stage 2 (Kubernetes resources)
5. Display access information

## Why Two Stages?

The Kubernetes and Helm providers need to connect to the cluster during the `apply` phase. Even though we have dependencies and a placeholder kubeconfig, Terraform will still try to connect to the actual cluster when applying Kubernetes resources.

By splitting into two stages:
- **Stage 1** creates the infrastructure and cluster
- **Stage 2** deploys resources onto the now-existing cluster

## Troubleshooting

### Error: VMs already exist

If you get errors about VMs already existing, you can import them:

```bash
# Check what exists
terraform import proxmox_virtual_environment_vm.bumblebee <vmid>
terraform import proxmox_virtual_environment_vm.prime <vmid>
terraform import proxmox_virtual_environment_vm.wheeljack <vmid>
```

Or use the import script:
```bash
./scripts/import/import-existing-vms-safe.sh
```

### Error: Cluster still not reachable

If Stage 1 completes but cluster isn't reachable:

1. Check VM status in Proxmox UI
2. Try to SSH to control plane:
   ```bash
   ssh your-user@192.168.0.32
   kubectl get nodes
   ```
3. Check API server:
   ```bash
   curl -k https://192.168.0.32:6443/healthz
   ```

### Error: Stage 2 fails

If Stage 2 fails, you can safely retry:

```bash
terraform apply -var="bootstrap_cluster=true"
```

The idempotent nature of Terraform means it will only create what's missing.

## Quick Commands Reference

### Full automated deployment
```bash
./scripts/deployment/deploy-full-stack.sh
```

### Manual Stage 1 only
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

### Manual Stage 2 only
```bash
terraform apply -var="bootstrap_cluster=true"
```

### Check cluster status
```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
```

### Destroy everything
```bash
terraform destroy -var="bootstrap_cluster=true"
```

## Next Steps After Deployment

Once both stages complete successfully:

1. **Update /etc/hosts** (or your DNS):
   ```
   192.168.0.35 grafana.home prometheus.home loki.home mimir.home mylar.home
   ```
   (Replace 192.168.0.35 with your actual ingress IP)

2. **Access services**:
   - Grafana: http://grafana.home (admin/admin)
   - Prometheus: http://prometheus.home
   - Loki: http://loki.home
   - Mimir: http://mimir.home
   - Mylar: http://mylar.home

3. **Verify backups** are configured:
   ```bash
   kubectl get cronjob -n backup
   kubectl get pods -n backup
   ```

## Important Notes

- ✅ **qemu-guest-agent** is now installed via cloud-init (fixes IP detection)
- ✅ **nfs-common** is pre-installed (ready for NFS storage)
- ✅ **Placeholder kubeconfig** prevents initial plan failures
- ⚠️ **Two-stage apply** is required for fresh deployments
- 💡 **Idempotent** - You can run terraform apply multiple times safely

## Getting Help

If you encounter issues:

1. Check logs: `terraform show`
2. Validate config: `terraform validate`
3. Check state: `terraform state list`
4. Review docs: `docs/deployment/BOOTSTRAP-IMPROVEMENTS.md`

