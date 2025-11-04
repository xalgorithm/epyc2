# Documentation

This directory contains comprehensive documentation for the Kubernetes Infrastructure on Proxmox project.

## 📚 Documentation Structure

### 🚀 [Deployment](deployment/)
Complete guides for deploying the infrastructure from scratch.

#### Main Guides
- **[Deployment Guide](deployment/DEPLOYMENT-GUIDE.md)** - Step-by-step deployment instructions
- **[Deployment Order](deployment/DEPLOYMENT_ORDER.md)** - Correct order for resource deployment
- **[Quick Deploy](deployment/QUICK_DEPLOY.md)** - Fast deployment for experienced users
- **[VM Setup](deployment/VM-SETUP.md)** - Virtual machine configuration and setup
- **[VM Configuration](deployment/VM_CONFIGURATION.md)** - Detailed VM settings and options

#### Setup & Configuration
- **[API Token Setup](deployment/API-TOKEN-SETUP.md)** - Proxmox API token configuration
- **[BPG Provider Setup](deployment/BPG-PROVIDER-SETUP.md)** - Alternative Terraform provider setup
- **[Bootstrap Improvements](deployment/BOOTSTRAP-IMPROVEMENTS.md)** - Bootstrap process enhancements
- **[Proxmox Snippets Setup](deployment/PROXMOX_SNIPPETS_SETUP.md)** - Cloud-init snippets configuration
- **[Import Guide](deployment/IMPORT_GUIDE.md)** - Importing existing resources into Terraform

#### Cloud-Init & SSH
- **[Cloud-Init Fixes](deployment/CLOUD-INIT-FIXES.md)** - Common cloud-init troubleshooting
- **[Cloud-Init SSH Fix](deployment/CLOUD_INIT_SSH_FIX.md)** - SSH key configuration in cloud-init
- **[SSH Config Summary](deployment/SSH_CONFIG_SUMMARY.md)** - SSH configuration overview
- **[Permanent Hostname Fix](deployment/PERMANENT_HOSTNAME_FIX.md)** - Preventing hostname collisions
- **[Bootstrap Fix Summary](deployment/BOOTSTRAP_FIX_SUMMARY.md)** - VM bootstrap improvements

### 💾 [Backup](backup/)
Comprehensive backup and recovery documentation.

- **[Backup Guide](backup/BACKUP.md)** - Complete backup system overview and procedures

### 📊 [Monitoring](monitoring/)
Monitoring and observability setup guides.

- **[Grafana Dashboards](monitoring/GRAFANA_DASHBOARDS.md)** - Dashboard configuration and usage

### ⚙️ [Backend & Infrastructure](.)
Backend configuration and infrastructure documentation.

- **[Terraform Backend](TERRAFORM_BACKEND.md)** - Remote state backend configuration
- **[macOS NFS Backend](MACOS_NFS_BACKEND.md)** - NFS backend setup on macOS
- **[OPNsense Logging](OPNSENSE_LOGGING.md)** - Network logging configuration

### 🔧 [Troubleshooting](troubleshooting/)
Common issues and their solutions.

#### Kubernetes Cluster Issues
- **[Hostname Collision Fix](troubleshooting/HOSTNAME_COLLISION_FIX.md)** - Fixing hostname collisions in K8s nodes
- **[Hostname Fix Summary](troubleshooting/HOSTNAME_FIX_SUMMARY.md)** - Complete hostname issue resolution
- **[Hostname Fix Status](troubleshooting/HOSTNAME_FIX_STATUS.md)** - Status of manual hostname fixes
- **[Control Plane Setup Fix](troubleshooting/CONTROL_PLANE_SETUP_FIX.md)** - Control plane initialization issues
- **[Worker Setup Troubleshooting](troubleshooting/WORKER_SETUP_TROUBLESHOOTING.md)** - Worker node join problems

#### Kubernetes Access
- **[Kubeconfig Encoding Fix](troubleshooting/KUBECONFIG_ENCODING_FIX.md)** - Kubernetes config issues
- **[Kubectl Access Fix](troubleshooting/KUBECTL_ACCESS_FIX.md)** - kubectl connectivity problems

#### Storage & NFS
- **[NFS Access Fix](troubleshooting/NFS_ACCESS_FIX.md)** - NFS storage issues
- **[NFS Backup Fix Summary](troubleshooting/NFS_BACKUP_FIX_SUMMARY.md)** - Backup storage fixes
- **[NFS Directory Permissions Fix](troubleshooting/NFS_DIRECTORY_PERMISSIONS_FIX.md)** - Permission issues

#### Proxmox
- **[Proxmox Permissions](troubleshooting/PROXMOX_PERMISSIONS.md)** - API and permission issues

## 🎯 Quick Navigation

### Getting Started
1. Start with the [Deployment Guide](deployment/DEPLOYMENT-GUIDE.md) or [Quick Deploy](deployment/QUICK_DEPLOY.md)
2. Configure [Proxmox Snippets](deployment/PROXMOX_SNIPPETS_SETUP.md) for cloud-init
3. Set up your [API Tokens](deployment/API-TOKEN-SETUP.md)
4. Review [VM Configuration](deployment/VM_CONFIGURATION.md) and deploy [VMs](deployment/VM-SETUP.md)

### Post-Deployment
1. Configure [Backup System](backup/BACKUP.md)
2. Set up [Monitoring Dashboards](monitoring/GRAFANA_DASHBOARDS.md)
3. Review [Troubleshooting Guides](troubleshooting/)

### Common Issues
- **Hostname Collisions**: See [Hostname Collision Fix](troubleshooting/HOSTNAME_COLLISION_FIX.md)
- **Worker Join Failures**: See [Worker Setup Troubleshooting](troubleshooting/WORKER_SETUP_TROUBLESHOOTING.md)
- **Control Plane Issues**: See [Control Plane Setup Fix](troubleshooting/CONTROL_PLANE_SETUP_FIX.md)
- **SSH Problems**: See [Cloud-Init SSH Fix](deployment/CLOUD_INIT_SSH_FIX.md)
- **NFS Issues**: See [NFS Access Fix](troubleshooting/NFS_ACCESS_FIX.md)

### Common Tasks
- **Backup Operations**: See [Backup Guide](backup/BACKUP.md)
- **Monitoring Setup**: See [Grafana Dashboards](monitoring/GRAFANA_DASHBOARDS.md)
- **Issue Resolution**: Check [Troubleshooting](troubleshooting/) section
- **Import Existing Resources**: See [Import Guide](deployment/IMPORT_GUIDE.md)

## 📖 Documentation Standards

All documentation in this project follows these standards:

- **Clear Structure**: Each document has a clear table of contents and sections
- **Step-by-Step Instructions**: Procedures are broken down into actionable steps
- **Code Examples**: All commands and configurations include working examples
- **Troubleshooting**: Common issues and solutions are documented
- **Cross-References**: Related documents are linked for easy navigation

## 🤝 Contributing to Documentation

When adding or updating documentation:

1. **Follow the existing structure** and naming conventions
2. **Include practical examples** and working code snippets
3. **Test all procedures** before documenting them
4. **Update cross-references** when adding new documents
5. **Use clear, concise language** suitable for technical audiences

## 📝 Document Templates

When creating new documentation, use these templates:

### Deployment Guide Template
```markdown
# Component Deployment Guide

## Overview
Brief description of what this deploys.

## Prerequisites
- List of requirements
- Dependencies

## Step-by-Step Deployment
1. First step with commands
2. Second step with verification
3. Continue...

## Verification
How to verify successful deployment.

## Troubleshooting
Common issues and solutions.
```

### Troubleshooting Guide Template
```markdown
# Component Troubleshooting

## Problem Description
Clear description of the issue.

## Symptoms
- Observable symptoms
- Error messages

## Root Cause
Explanation of why this happens.

## Solution
Step-by-step fix procedure.

## Prevention
How to avoid this issue in the future.
```

## 🔍 Finding Information

Use this guide to quickly find what you need:

| I want to... | Go to... |
|--------------|----------|
| Deploy the infrastructure | [Deployment Guide](deployment/DEPLOYMENT-GUIDE.md) or [Quick Deploy](deployment/QUICK_DEPLOY.md) |
| Set up backups | [Backup Guide](backup/BACKUP.md) |
| Configure monitoring | [Grafana Dashboards](monitoring/GRAFANA_DASHBOARDS.md) |
| Fix hostname collisions | [Hostname Collision Fix](troubleshooting/HOSTNAME_COLLISION_FIX.md) |
| Prevent future hostname issues | [Permanent Hostname Fix](deployment/PERMANENT_HOSTNAME_FIX.md) |
| Fix worker join problems | [Worker Setup Troubleshooting](troubleshooting/WORKER_SETUP_TROUBLESHOOTING.md) |
| Fix control plane issues | [Control Plane Setup Fix](troubleshooting/CONTROL_PLANE_SETUP_FIX.md) |
| Fix NFS issues | [NFS Access Fix](troubleshooting/NFS_ACCESS_FIX.md) |
| Fix kubectl access | [Kubectl Access Fix](troubleshooting/KUBECTL_ACCESS_FIX.md) |
| Import existing resources | [Import Guide](deployment/IMPORT_GUIDE.md) |
| Configure cloud-init | [Proxmox Snippets Setup](deployment/PROXMOX_SNIPPETS_SETUP.md) |
| Fix SSH issues | [Cloud-Init SSH Fix](deployment/CLOUD_INIT_SSH_FIX.md) |

---

**Need help?** Check the troubleshooting section or create an issue in the project repository.