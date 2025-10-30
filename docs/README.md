# Documentation

This directory contains comprehensive documentation for the Kubernetes Infrastructure on Proxmox project.

## 📚 Documentation Structure

### 🚀 [Deployment](deployment/)
Complete guides for deploying the infrastructure from scratch.

- **[Deployment Guide](deployment/DEPLOYMENT-GUIDE.md)** - Step-by-step deployment instructions
- **[VM Setup](deployment/VM-SETUP.md)** - Virtual machine configuration and setup
- **[API Token Setup](deployment/API-TOKEN-SETUP.md)** - Proxmox API token configuration
- **[BPG Provider Setup](deployment/BPG-PROVIDER-SETUP.md)** - Alternative Terraform provider setup
- **[Cloud-Init Fixes](deployment/CLOUD-INIT-FIXES.md)** - Common cloud-init troubleshooting

### 💾 [Backup](backup/)
Comprehensive backup and recovery documentation.

- **[Backup Guide](backup/BACKUP_GUIDE.md)** - Complete backup system overview
- **[Manual Backup Guide](backup/MANUAL_BACKUP_GUIDE.md)** - Manual backup procedures
- **[Backup Dashboard Guide](backup/BACKUP_DASHBOARD_GUIDE.md)** - Monitoring backup status

### 📊 [Monitoring](monitoring/)
Monitoring and observability setup guides.

- **[Grafana Dashboards](monitoring/GRAFANA_DASHBOARDS.md)** - Dashboard configuration and usage

### 🔧 [Troubleshooting](troubleshooting/)
Common issues and their solutions.

- **[NetAlertX Setup](troubleshooting/NETALERTX_SETUP.md)** - Network monitoring troubleshooting
- **[NFS Access Fix](troubleshooting/NFS_ACCESS_FIX.md)** - NFS storage issues
- **[NFS Backup Fix Summary](troubleshooting/NFS_BACKUP_FIX_SUMMARY.md)** - Backup storage fixes
- **[NFS Directory Permissions Fix](troubleshooting/NFS_DIRECTORY_PERMISSIONS_FIX.md)** - Permission issues
- **[Kubeconfig Encoding Fix](troubleshooting/KUBECONFIG_ENCODING_FIX.md)** - Kubernetes config issues
- **[Kubectl Access Fix](troubleshooting/KUBECTL_ACCESS_FIX.md)** - kubectl connectivity problems

## 🎯 Quick Navigation

### Getting Started
1. Start with the [Deployment Guide](deployment/DEPLOYMENT-GUIDE.md)
2. Configure your [API Tokens](deployment/API-TOKEN-SETUP.md)
3. Set up [VMs](deployment/VM-SETUP.md)

### Post-Deployment
1. Configure [Backup System](backup/BACKUP_GUIDE.md)
2. Set up [Monitoring Dashboards](monitoring/GRAFANA_DASHBOARDS.md)
3. Review [Troubleshooting Guides](troubleshooting/)

### Common Tasks
- **Backup Operations**: See [Backup Guide](backup/BACKUP_GUIDE.md)
- **Monitoring Setup**: See [Grafana Dashboards](monitoring/GRAFANA_DASHBOARDS.md)
- **Issue Resolution**: Check [Troubleshooting](troubleshooting/) section

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
| Deploy the infrastructure | [Deployment Guide](deployment/DEPLOYMENT-GUIDE.md) |
| Set up backups | [Backup Guide](backup/BACKUP_GUIDE.md) |
| Configure monitoring | [Grafana Dashboards](monitoring/GRAFANA_DASHBOARDS.md) |
| Fix NFS issues | [NFS Troubleshooting](troubleshooting/NFS_ACCESS_FIX.md) |
| Resolve NetAlertX problems | [NetAlertX Setup](troubleshooting/NETALERTX_SETUP.md) |
| Fix kubectl access | [Kubectl Access Fix](troubleshooting/KUBECTL_ACCESS_FIX.md) |

---

**Need help?** Check the troubleshooting section or create an issue in the project repository.