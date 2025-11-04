# Documentation Organization

This document describes the complete organization of documentation files in this project.

## 📂 Directory Structure

```
epyc2/
├── docs/                                    # All documentation
│   ├── deployment/                          # Deployment guides
│   ├── troubleshooting/                     # Troubleshooting & fixes
│   ├── backup/                              # Backup documentation
│   ├── monitoring/                          # Monitoring setup
│   └── *.md                                 # Infrastructure docs
├── scripts/                                 # Helper scripts
│   ├── deployment/                          # Deployment scripts
│   ├── backup/                              # Backup scripts
│   ├── maintenance/                         # Maintenance scripts
│   ├── import/                              # Import scripts
│   └── troubleshooting/                     # Troubleshooting scripts
├── configs/                                 # Configuration files
│   ├── grafana/                             # Grafana dashboards
│   └── prometheus/                          # Prometheus configs
└── *.md                                     # Project-level docs
```

## 📚 Documentation Categories

### 🚀 Deployment Documentation (`docs/deployment/`)

Main deployment guides and configuration:
- **DEPLOYMENT-GUIDE.md** - Complete step-by-step deployment
- **DEPLOYMENT_ORDER.md** - Resource deployment order
- **QUICK_DEPLOY.md** - Fast deployment guide
- **VM-SETUP.md** - VM configuration guide
- **VM_CONFIGURATION.md** - Detailed VM settings

Setup & Configuration:
- **API-TOKEN-SETUP.md** - Proxmox API tokens
- **BPG-PROVIDER-SETUP.md** - Alternative provider
- **BOOTSTRAP-IMPROVEMENTS.md** - Bootstrap enhancements
- **BOOTSTRAP_FIX_SUMMARY.md** - Bootstrap fixes
- **PROXMOX_SNIPPETS_SETUP.md** - Cloud-init snippets
- **IMPORT_GUIDE.md** - Import existing resources

Cloud-Init & SSH:
- **CLOUD-INIT-FIXES.md** - Cloud-init troubleshooting
- **CLOUD_INIT_SSH_FIX.md** - SSH key configuration
- **SSH_CONFIG_SUMMARY.md** - SSH configuration
- **PERMANENT_HOSTNAME_FIX.md** - Hostname configuration

### 🔧 Troubleshooting Documentation (`docs/troubleshooting/`)

Kubernetes Cluster Issues:
- **HOSTNAME_COLLISION_FIX.md** - Hostname collision complete guide
- **HOSTNAME_FIX_SUMMARY.md** - Hostname issue resolution summary
- **HOSTNAME_FIX_STATUS.md** - Manual hostname fix status
- **CONTROL_PLANE_SETUP_FIX.md** - Control plane initialization
- **WORKER_SETUP_TROUBLESHOOTING.md** - Worker node join issues

Kubernetes Access:
- **KUBECONFIG_ENCODING_FIX.md** - Kubeconfig issues
- **KUBECTL_ACCESS_FIX.md** - kubectl connectivity

Storage & NFS:
- **NFS_ACCESS_FIX.md** - NFS storage issues
- **NFS_BACKUP_FIX_SUMMARY.md** - NFS backup storage
- **NFS_DIRECTORY_PERMISSIONS_FIX.md** - NFS permissions

Proxmox:
- **PROXMOX_PERMISSIONS.md** - API and permission issues

### 💾 Backup Documentation (`docs/backup/`)

- **BACKUP.md** - Complete backup system guide

### 📊 Monitoring Documentation (`docs/monitoring/`)

- **GRAFANA_DASHBOARDS.md** - Dashboard configuration

### ⚙️ Infrastructure Documentation (`docs/`)

Root-level infrastructure docs:
- **README.md** - Documentation index
- **TERRAFORM_BACKEND.md** - Remote state backend
- **MACOS_NFS_BACKEND.md** - NFS backend on macOS
- **OPNSENSE_LOGGING.md** - Network logging

## 📄 Project-Level Documentation (Root)

These files remain in the project root:
- **README.md** - Project overview and quick start
- **CHANGELOG.md** - Version history and changes
- **CONTRIBUTING.md** - Contribution guidelines
- **PROJECT_SUMMARY.md** - Project summary
- **SECURITY_CLEANUP_SUMMARY.md** - Security improvements
- **LICENSE** - Project license

## 🛠️ Scripts Organization

### Deployment Scripts (`scripts/deployment/`)
- **APPLY_HOSTNAME_FIX.sh** - Apply hostname fix configuration
- **deploy-full-stack.sh** - Full deployment automation
- **deploy-step-by-step.sh** - Guided deployment
- **pre-flight-check.sh** - Pre-deployment validation
- **setup-ingress-dns.sh** - Ingress DNS configuration
- **setup-nfs-server.sh** - NFS server setup

### Backup Scripts (`scripts/backup/`)
- Backup automation and restoration scripts
- Manual backup triggers
- Backup verification

### Maintenance Scripts (`scripts/maintenance/`)
- System maintenance utilities
- Dashboard updates
- Health checks

### Import Scripts (`scripts/import/`)
- Resource discovery
- Import automation
- Critical resource imports

### Troubleshooting Scripts (`scripts/troubleshooting/`)
- Diagnostic tools
- Issue resolution helpers

## 🔍 Quick Reference

### Finding Documentation

| Topic | Location |
|-------|----------|
| Deployment guides | `docs/deployment/` |
| Troubleshooting | `docs/troubleshooting/` |
| Backup procedures | `docs/backup/` |
| Monitoring setup | `docs/monitoring/` |
| Infrastructure config | `docs/*.md` |
| Project info | Root `*.md` files |

### Common Documentation Paths

```bash
# Deployment
docs/deployment/DEPLOYMENT-GUIDE.md
docs/deployment/QUICK_DEPLOY.md
docs/deployment/PERMANENT_HOSTNAME_FIX.md

# Troubleshooting
docs/troubleshooting/HOSTNAME_COLLISION_FIX.md
docs/troubleshooting/WORKER_SETUP_TROUBLESHOOTING.md
docs/troubleshooting/CONTROL_PLANE_SETUP_FIX.md

# Scripts
scripts/deployment/APPLY_HOSTNAME_FIX.sh
scripts/backup/manual-backup-comprehensive.sh
```

## 📋 Documentation Standards

All documentation follows these standards:

1. **Clear Structure** - TOC and sections
2. **Step-by-Step** - Actionable instructions
3. **Code Examples** - Working commands
4. **Cross-References** - Linked documents
5. **Troubleshooting** - Common issues included

## 🎯 Navigation

Start here:
1. **[docs/README.md](docs/README.md)** - Main documentation index
2. **[docs/deployment/DEPLOYMENT-GUIDE.md](docs/deployment/DEPLOYMENT-GUIDE.md)** - Begin deployment
3. **[docs/troubleshooting/](docs/troubleshooting/)** - Resolve issues

## 📝 Recent Organization Changes

### Files Moved to `docs/deployment/`:
- BOOTSTRAP_FIX_SUMMARY.md
- CLOUD_INIT_SSH_FIX.md
- IMPORT_GUIDE.md
- PERMANENT_HOSTNAME_FIX.md
- PROXMOX_SNIPPETS_SETUP.md
- QUICK_DEPLOY.md
- SSH_CONFIG_SUMMARY.md
- VM_CONFIGURATION.md

### Files Moved to `docs/troubleshooting/`:
- CONTROL_PLANE_SETUP_FIX.md
- HOSTNAME_COLLISION_FIX.md
- HOSTNAME_FIX_STATUS.md
- HOSTNAME_FIX_SUMMARY.md
- WORKER_SETUP_TROUBLESHOOTING.md

### Scripts Moved to `scripts/deployment/`:
- APPLY_HOSTNAME_FIX.sh

### Files Remaining in Root:
- CHANGELOG.md (project history)
- CONTRIBUTING.md (contribution guide)
- PROJECT_SUMMARY.md (overview)
- README.md (main entry point)
- SECURITY_CLEANUP_SUMMARY.md (security changes)
- LICENSE (license file)

## ✅ Organization Benefits

1. **Easy Navigation** - Logical folder structure
2. **Clear Purpose** - Each directory has specific content
3. **Quick Access** - Fast lookup of information
4. **Maintainability** - Easy to add new documentation
5. **Consistency** - Predictable organization

## 🔄 Maintenance

When adding new documentation:

1. **Deployment docs** → `docs/deployment/`
2. **Troubleshooting guides** → `docs/troubleshooting/`
3. **Backup procedures** → `docs/backup/`
4. **Monitoring guides** → `docs/monitoring/`
5. **Infrastructure config** → `docs/` (root)
6. **Project-level info** → Project root

Update `docs/README.md` when adding new files!

---

**Last Updated**: November 4, 2025
**Organization Status**: ✅ Complete

