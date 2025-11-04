# Scripts Organization

This document describes the complete organization of shell scripts in this project.

## 📂 Directory Structure

```
scripts/
├── backup/              # Backup and restore scripts (14 scripts)
├── deployment/          # Deployment and setup scripts (10 scripts)
├── import/              # Resource import scripts (6 scripts)
├── maintenance/         # Maintenance and operations scripts (8 scripts)
└── troubleshooting/     # Diagnostic and troubleshooting scripts (3 scripts)
```

**Total: 41 scripts organized into 5 categories**

## 📚 Script Categories

### 🚀 Deployment Scripts (`scripts/deployment/`)

Initial deployment and cluster setup:
- **APPLY_HOSTNAME_FIX.sh** - Apply permanent hostname fix configuration
- **deploy-full-stack.sh** - Complete automated deployment
- **deploy-step-by-step.sh** - Guided step-by-step deployment
- **pre-flight-check.sh** - Pre-deployment validation

Kubernetes Cluster Setup:
- **k8s-common-setup.sh** - Common K8s components (used by control plane & workers)
- **k8s-control-plane-setup.sh** - Control plane initialization
- **k8s-worker-setup.sh** - Worker node setup and join

Network & Storage Setup:
- **setup-ingress-dns.sh** - Ingress and DNS configuration
- **setup-nfs-backend.sh** - NFS backend mount for Terraform state
- **setup-nfs-server.sh** - NFS server configuration

**Usage Examples:**
```bash
# Full automated deployment
./scripts/deployment/deploy-full-stack.sh

# Guided deployment
./scripts/deployment/deploy-step-by-step.sh

# Setup NFS backend
sudo ./scripts/deployment/setup-nfs-backend.sh

# Apply hostname fix
./scripts/deployment/APPLY_HOSTNAME_FIX.sh
```

### 💾 Backup Scripts (`scripts/backup/`)

Backup Operations:
- **data-backup.sh** - General data backup
- **etcd-backup.sh** - etcd backup
- **k3s-etcd-backup.sh** - K3s etcd backup
- **manual-backup-comprehensive.sh** - Comprehensive manual backup
- **trigger-manual-backup.sh** - Trigger manual backup job

Restore Operations:
- **restore-etcd.sh** - Restore etcd data
- **restore-grafana.sh** - Restore Grafana data
- **restore-loki.sh** - Restore Loki data
- **restore-mimir.sh** - Restore Mimir data
- **restore-prometheus.sh** - Restore Prometheus data

Testing & Monitoring:
- **test-backup-restoration.sh** - Test backup restoration
- **test-individual-restore.sh** - Test individual component restore
- **backup-cleanup.sh** - Cleanup old backups
- **backup-file-metrics.sh** - Backup file metrics collection

**Usage Examples:**
```bash
# Comprehensive backup
./scripts/backup/manual-backup-comprehensive.sh

# Test restoration
./scripts/backup/test-backup-restoration.sh

# Restore specific component
./scripts/backup/restore-grafana.sh
```

### 📥 Import Scripts (`scripts/import/`)

Resource Discovery:
- **discover-existing-resources.sh** - Discover existing infrastructure resources

Import Operations:
- **import-all-resources.sh** - Import all discovered resources
- **import-critical-resources.sh** - Import only critical resources
- **import-kubernetes-only.sh** - Import only Kubernetes resources
- **import-existing-vms.sh** - Import existing VMs
- **import-existing-vms-safe.sh** - Safe VM import with validation

**Usage Examples:**
```bash
# Discover existing resources
./scripts/import/discover-existing-resources.sh

# Import critical resources
./scripts/import/import-critical-resources.sh

# Import VMs safely
./scripts/import/import-existing-vms-safe.sh
```

### 🔧 Maintenance Scripts (`scripts/maintenance/`)

System Maintenance:
- **check-backend-status.sh** - Check Terraform backend status
- **unmount-nfs-backend.sh** - Unmount NFS backend

NFS Operations:
- **fix-nfs-permissions.sh** - Fix NFS permissions
- **fix-nfs-directory-permissions.sh** - Fix NFS directory permissions
- **test-nfs-permissions.sh** - Test NFS permissions
- **test-backup-connectivity.sh** - Test backup storage connectivity

Monitoring Updates:
- **import-dashboards.sh** - Import Grafana dashboards
- **update-grafana-dashboards.sh** - Update Grafana dashboards

**Usage Examples:**
```bash
# Check backend status
./scripts/maintenance/check-backend-status.sh

# Fix NFS permissions
sudo ./scripts/maintenance/fix-nfs-permissions.sh

# Update dashboards
./scripts/maintenance/update-grafana-dashboards.sh

# Unmount NFS backend
sudo ./scripts/maintenance/unmount-nfs-backend.sh
```

### 🔍 Troubleshooting Scripts (`scripts/troubleshooting/`)

Diagnostic Tools:
- **troubleshoot.sh** - General troubleshooting script
- **diagnose-nfs-access.sh** - Diagnose NFS access issues

Fixes:
- **fix-kubeconfig-secret.sh** - Fix kubeconfig secret issues

**Usage Examples:**
```bash
# General troubleshooting
./scripts/troubleshooting/troubleshoot.sh

# Diagnose NFS issues
./scripts/troubleshooting/diagnose-nfs-access.sh

# Fix kubeconfig
./scripts/troubleshooting/fix-kubeconfig-secret.sh
```

## 🔄 Script Dependencies

### Terraform Configuration References

**k8s-cluster.tf** uses:
- `scripts/deployment/k8s-common-setup.sh`
- `scripts/deployment/k8s-control-plane-setup.sh`
- `scripts/deployment/k8s-worker-setup.sh`

**backend.tf** references:
- `scripts/deployment/setup-nfs-backend.sh`

### Documentation References

**docs/troubleshooting/CONTROL_PLANE_SETUP_FIX.md** references:
- `scripts/deployment/k8s-common-setup.sh`
- `scripts/deployment/k8s-control-plane-setup.sh`

**docs/MACOS_NFS_BACKEND.md** references:
- `scripts/deployment/setup-nfs-backend.sh`
- `scripts/maintenance/unmount-nfs-backend.sh`
- `scripts/maintenance/check-backend-status.sh`

**docs/TERRAFORM_BACKEND.md** references:
- `scripts/deployment/setup-nfs-backend.sh`
- `scripts/maintenance/unmount-nfs-backend.sh`

## 📋 Quick Reference

### By Function

| Function | Scripts |
|----------|---------|
| Initial Setup | `deployment/deploy-*.sh`, `deployment/pre-flight-check.sh` |
| Cluster Setup | `deployment/k8s-*.sh` |
| Backup | `backup/manual-backup-comprehensive.sh`, `backup/trigger-manual-backup.sh` |
| Restore | `backup/restore-*.sh` |
| Import | `import/import-*.sh` |
| Maintenance | `maintenance/*.sh` |
| Troubleshooting | `troubleshooting/*.sh` |

### By Frequency of Use

**Daily/Regular:**
- `backup/manual-backup-comprehensive.sh`
- `maintenance/check-backend-status.sh`
- `maintenance/update-grafana-dashboards.sh`

**One-Time Setup:**
- `deployment/deploy-full-stack.sh`
- `deployment/setup-nfs-backend.sh`
- `deployment/APPLY_HOSTNAME_FIX.sh`
- `import/import-*.sh`

**As Needed:**
- `backup/restore-*.sh`
- `maintenance/fix-*.sh`
- `troubleshooting/*.sh`

## 🎯 Common Workflows

### New Deployment
```bash
# 1. Pre-flight check
./scripts/deployment/pre-flight-check.sh

# 2. Setup NFS backend
sudo ./scripts/deployment/setup-nfs-backend.sh

# 3. Deploy infrastructure
./scripts/deployment/deploy-full-stack.sh
# OR step-by-step
./scripts/deployment/deploy-step-by-step.sh

# 4. Apply hostname fix (if needed)
./scripts/deployment/APPLY_HOSTNAME_FIX.sh
```

### Import Existing Infrastructure
```bash
# 1. Discover resources
./scripts/import/discover-existing-resources.sh

# 2. Import critical resources
./scripts/import/import-critical-resources.sh

# 3. Verify
terraform state list
```

### Backup & Restore
```bash
# Backup
./scripts/backup/manual-backup-comprehensive.sh

# Test backup
./scripts/backup/test-backup-restoration.sh

# Restore if needed
./scripts/backup/restore-grafana.sh
```

### Troubleshooting
```bash
# General troubleshooting
./scripts/troubleshooting/troubleshoot.sh

# Specific issues
./scripts/troubleshooting/diagnose-nfs-access.sh
./scripts/maintenance/test-nfs-permissions.sh
```

## 📝 Recent Organization Changes

### Scripts Moved to Proper Locations (6 scripts):

**To `scripts/deployment/`:**
- ✅ k8s-common-setup.sh (from root)
- ✅ k8s-control-plane-setup.sh (from root)
- ✅ k8s-worker-setup.sh (from root)
- ✅ setup-nfs-backend.sh (from root)

**To `scripts/maintenance/`:**
- ✅ check-backend-status.sh (from root)
- ✅ unmount-nfs-backend.sh (from root)

### Updated References:
- ✅ k8s-cluster.tf (4 references)
- ✅ backend.tf (1 reference)
- ✅ docs/troubleshooting/CONTROL_PLANE_SETUP_FIX.md (4 references)
- ✅ docs/MACOS_NFS_BACKEND.md (8 references)
- ✅ docs/TERRAFORM_BACKEND.md (7 references)

## 🔒 Script Permissions

All scripts should be executable:
```bash
# Make scripts executable (if needed)
chmod +x scripts/*/*.sh
```

**Note:** Scripts requiring root access (NFS operations, system config):
- `deployment/setup-nfs-backend.sh`
- `maintenance/unmount-nfs-backend.sh`
- `maintenance/fix-nfs-*.sh`

## ✅ Organization Benefits

1. **Clear Purpose** - Easy to find scripts by category
2. **Logical Structure** - Similar functions grouped together
3. **Easy Navigation** - Predictable locations
4. **Maintainability** - Simple to add new scripts
5. **Documentation** - Clear references in docs

## 📖 Script Standards

All scripts in this project follow these standards:

1. **Shebang**: `#!/bin/bash`
2. **Error Handling**: Use `set -e` or `set -euo pipefail`
3. **Logging**: Output to stdout/stderr appropriately
4. **Documentation**: Include comments explaining purpose
5. **Naming**: Use kebab-case (e.g., `script-name.sh`)

## 🔄 Maintenance

When adding new scripts:

1. **Deployment scripts** → `scripts/deployment/`
2. **Backup/restore scripts** → `scripts/backup/`
3. **Import scripts** → `scripts/import/`
4. **Maintenance scripts** → `scripts/maintenance/`
5. **Troubleshooting scripts** → `scripts/troubleshooting/`

Update this documentation when adding new scripts!

## 📊 Statistics

```
Total Scripts:           41
  - Deployment:          10 scripts
  - Backup:              14 scripts
  - Import:               6 scripts
  - Maintenance:          8 scripts
  - Troubleshooting:      3 scripts

Scripts Organized:       6 moved to proper locations
Files Updated:           5 (Terraform + docs)
Terraform Validation:    ✅ Passed
```

---

**Last Updated**: November 4, 2025
**Organization Status**: ✅ Complete

