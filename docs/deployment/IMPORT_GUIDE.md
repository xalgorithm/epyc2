# Terraform State Import Guide

This guide will help you import all existing VMs and applications into Terraform state.

## Prerequisites

1. **Kubernetes cluster access**: Ensure `kubectl` works
2. **Proxmox access**: You can access Proxmox UI at https://192.168.0.7:8006
3. **Helm installed**: For checking Helm releases

## Step 1: Discover Existing Resources

Run the discovery script to see what exists:

```bash
./scripts/import/discover-existing-resources.sh
```

## Step 2: Import Proxmox VMs

### Find VM IDs in Proxmox
1. Login to Proxmox UI: https://192.168.0.7:8006
2. Note the VM IDs for your VMs (they appear in the left panel)

### Import VMs
Replace `XXX` with actual VM IDs from Proxmox:

```bash
# Import VMs (replace XXX with actual VM IDs)
terraform import proxmox_virtual_environment_vm.bumblebee pve/XXX
terraform import proxmox_virtual_environment_vm.prime pve/XXX
terraform import proxmox_virtual_environment_vm.wheeljack pve/XXX
```

## Step 3: Import Kubernetes Resources

### Import in this order to handle dependencies:

#### 3.1 Namespaces
```bash
terraform import kubernetes_namespace.monitoring monitoring
terraform import kubernetes_namespace.mylar media


terraform import kubernetes_namespace.backup backup
```

#### 3.2 Storage Classes
```bash
terraform import kubernetes_storage_class.nfs_storage_class nfs-storage
```

#### 3.3 Helm Releases
```bash
# Check what Helm releases exist first
helm list -A

# Import existing releases
terraform import helm_release.metallb metallb/metallb-system
terraform import helm_release.ingress_nginx ingress-nginx/ingress-nginx
terraform import helm_release.nfs_csi_driver csi-driver-nfs/kube-system
```

#### 3.4 ConfigMaps (if they exist)
```bash
# Check what configmaps exist
kubectl get configmap -A | grep -E "(prometheus|grafana|loki)"

# Import configmaps (adjust names as needed)
terraform import kubernetes_config_map.prometheus_config monitoring/prometheus-config
terraform import kubernetes_config_map.grafana_config monitoring/grafana-config

```

#### 3.5 Persistent Volume Claims
```bash
# Check existing PVCs
kubectl get pvc -A

# Import PVCs (adjust names as needed)
terraform import kubernetes_persistent_volume_claim.prometheus_storage monitoring/prometheus-storage
terraform import kubernetes_persistent_volume_claim.grafana_storage monitoring/grafana-storage

```

#### 3.6 Service Accounts and RBAC
```bash
# Import service accounts
terraform import kubernetes_service_account.prometheus monitoring/prometheus
terraform import kubernetes_service_account.backup backup/backup

# Import cluster roles
terraform import kubernetes_cluster_role.prometheus prometheus
terraform import kubernetes_cluster_role.backup backup

# Import cluster role bindings
terraform import kubernetes_cluster_role_binding.prometheus prometheus
terraform import kubernetes_cluster_role_binding.backup backup
```

#### 3.7 Deployments
```bash
terraform import kubernetes_deployment.prometheus monitoring/prometheus
terraform import kubernetes_deployment.grafana monitoring/grafana
terraform import kubernetes_deployment.loki monitoring/loki
terraform import kubernetes_deployment.mylar media/mylar


```

#### 3.8 Services
```bash
terraform import kubernetes_service.prometheus monitoring/prometheus
terraform import kubernetes_service.grafana monitoring/grafana
terraform import kubernetes_service.loki monitoring/loki
terraform import kubernetes_service.mylar media/mylar


```

#### 3.9 Ingresses
```bash
terraform import kubernetes_ingress_v1.prometheus monitoring/prometheus
terraform import kubernetes_ingress_v1.grafana monitoring/grafana
terraform import kubernetes_ingress_v1.loki monitoring/loki
terraform import kubernetes_ingress_v1.mylar media/mylar


```

#### 3.10 CronJobs (Backup jobs)
```bash
# Check existing cronjobs
kubectl get cronjobs -A

# Import backup cronjobs
terraform import kubernetes_cron_job_v1.etcd_backup backup/etcd-backup
terraform import kubernetes_cron_job_v1.data_backup backup/data-backup
terraform import kubernetes_cron_job_v1.backup_cleanup backup/backup-cleanup
```

## Step 4: Verify Import

After importing, run a plan to see what's left:

```bash
terraform plan
```

## Step 5: Handle Remaining Resources

If terraform plan shows resources that need to be created:

1. **Missing resources**: These need to be created with `terraform apply`
2. **Configuration drift**: Adjust Terraform configs to match existing resources
3. **Additional imports**: Some resources might need manual import

## Common Issues and Solutions

### Issue: Resource not found during import
**Solution**: The resource doesn't exist in Kubernetes. Skip the import or create it with Terraform.

### Issue: Configuration drift after import
**Solution**: Either:
- Modify Terraform config to match existing resource
- Update the existing resource to match Terraform config
- Use `lifecycle { ignore_changes = [...] }` for acceptable differences

### Issue: Dependencies not imported
**Solution**: Import dependencies first, then retry.

## Automated Import Script

For convenience, you can also use the automated script:

```bash
# Edit the script first to set correct VM IDs
vim scripts/import/import-all-resources.sh

# Run the automated import
./scripts/import/import-all-resources.sh
```

## Verification Commands

After import, verify everything works:

```bash
# Check Terraform state
terraform state list

# Check Kubernetes resources
kubectl get all -A

# Check Helm releases
helm list -A

# Verify applications are accessible
kubectl get ingress -A
```