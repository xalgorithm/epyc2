# Terraform Deployment Order

This document outlines the proper deployment order for the full Kubernetes cluster stack.

## 🎉 Recent Improvements

The bootstrap process has been significantly improved to support **single-command deployment**. Key improvements include:

- ✅ **Early guest agent installation** via cloud-init (fixes Proxmox IP detection)
- ✅ **Placeholder kubeconfig creation** (prevents provider initialization errors)
- ✅ **Improved dependency chain** (ensures proper resource ordering)

**For detailed information about these improvements, see [BOOTSTRAP-IMPROVEMENTS.md](BOOTSTRAP-IMPROVEMENTS.md)**

## Quick Start

For a fresh deployment:

```bash
terraform init
terraform apply -var="bootstrap_cluster=true"
```

That's it! The deployment now works end-to-end in a single command.

## Detailed Deployment Phases

The following phases happen automatically during `terraform apply`:

## Phase 0: Pre-Bootstrap

0. **Kubeconfig Preparation**
   - `null_resource.prepare_kubeconfig` - Creates placeholder kubeconfig if needed
   - Prevents Kubernetes provider from failing during initial plan

## Phase 1: Infrastructure (VMs)

1. **Cloud-Init Configuration**
   - `proxmox_virtual_environment_file.cloud_init_user_data` - Uploads cloud-init snippet
   - Installs qemu-guest-agent and nfs-common during first boot

2. **Proxmox VMs Creation**
   - `proxmox_virtual_environment_vm.bumblebee` (Control Plane)
   - `proxmox_virtual_environment_vm.prime` (Worker 1)
   - `proxmox_virtual_environment_vm.wheeljack` (Worker 2)

## Phase 2: VM Readiness

3. **VM Accessibility Check**
   - `null_resource.wait_for_vms` - Waits for SSH connectivity to all VMs

## Phase 3: Kubernetes Cluster Bootstrap

4. **Control Plane Setup**
   - `null_resource.control_plane_setup` - Installs and configures Kubernetes control plane
   - Runs kubeadm init
   - Installs Flannel CNI
   - Configures cluster networking

5. **Worker Nodes Setup**
   - `null_resource.worker_setup` - Joins worker nodes to the cluster
   - Runs kubeadm join on each worker

6. **Kubeconfig Management**
   - `null_resource.copy_kubeconfig` - Copies kubeconfig to local machine (replaces placeholder)
   - `null_resource.kubeconfig_ready` - Validates kubeconfig availability

## Phase 4: Cluster API Readiness

7. **API Server Validation**
   - `null_resource.cluster_api_ready` - Ensures Kubernetes API is accessible

## Phase 5: Core Networking (Load Balancer)

8. **MetalLB Installation**
   - `null_resource.metallb_namespace` - Creates MetalLB namespace via kubectl
   - `helm_release.metallb` - Installs MetalLB via Helm
   - `null_resource.metallb_ready` - Waits for MetalLB controller
   - `null_resource.metallb_ipaddresspool` - Configures IP pool
   - `null_resource.metallb_l2advertisement` - Configures L2 advertisements
   - `null_resource.metallb_operational` - Final MetalLB readiness check

## Phase 6: Storage

9. **NFS Storage Configuration**
   - `null_resource.create_nfs_directory` - Creates NFS directories
   - `null_resource.remove_default_storage_class` - Removes default storage class
   - `kubernetes_storage_class.nfs_storage_class` - Creates NFS storage class

## Phase 7: Application Namespaces

9. **Namespace Creation**
   - `kubernetes_namespace.monitoring` - Monitoring stack namespace
   - `kubernetes_namespace.mylar` (media) - Media applications namespace
   - `kubernetes_namespace.backup` - Backup system namespace

## Phase 8: Ingress Controller

10. **NGINX Ingress**
    - `helm_release.ingress_nginx` - Installs NGINX Ingress Controller
    - Depends on MetalLB being operational

## Phase 9: Observability Stack

11. **Monitoring Components**
    - Prometheus, Grafana, Loki, Mimir deployments
    - Service accounts, config maps, services
    - Persistent volumes for data storage

## Phase 10: Media Applications

12. **Media Stack**
    - Mylar deployment and services

## Phase 11: Backup System

13. **Backup Infrastructure**
    - Backup service accounts, roles, and bindings
    - Backup CronJobs for etcd and data
    - Cleanup jobs

## Phase 12: Ingress Rules

14. **Application Ingress**
    - Grafana, Prometheus, Loki, Mimir, Mylar ingress rules
    - Depends on both applications and ingress controller

## Key Dependencies

### Critical Path

VMs → VM Readiness → K8s Bootstrap → API Ready → MetalLB → Ingress → Applications

### Bootstrap Control

- Set `bootstrap_cluster = true` for full deployment from scratch
- Set `bootstrap_cluster = false` to skip VM and cluster setup (use existing cluster)

### Timeouts and Waits

- VM accessibility: 300 seconds
- Kubernetes API: 900 seconds  
- MetalLB readiness: 300 seconds
- Application deployments: 600 seconds

## Deployment Commands

### Full Stack Deployment

```bash
# Ensure bootstrap is enabled
terraform plan -var="bootstrap_cluster=true"
terraform apply -var="bootstrap_cluster=true"
```

### Existing Cluster Deployment

```bash
# Use existing cluster
terraform plan -var="bootstrap_cluster=false"  
terraform apply -var="bootstrap_cluster=false"
```

### Destroy Everything

```bash
terraform destroy
```

This order ensures that each component is available before dependent components are deployed.

## Important Notes

### API Validation Fix

The MetalLB configuration uses `null_resource` with `kubectl` commands instead of `kubernetes_manifest` resources to avoid Kubernetes API validation during the planning phase. This ensures that Terraform can plan the deployment even when the Kubernetes cluster doesn't exist yet.

### Resource Types Used

- **VM Creation**: `proxmox_virtual_environment_vm` resources
- **Kubernetes Bootstrap**: `null_resource` with SSH provisioners
- **MetalLB Setup**: `null_resource` with `kubectl` commands (avoids API validation issues)
- **Application Deployment**: Standard Kubernetes resources (depend on cluster readiness)

This approach ensures that the planning phase works correctly regardless of cluster state, while the apply phase executes resources in the proper dependency order.
