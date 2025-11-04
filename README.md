# Kubernetes Infrastructure on Proxmox

A comprehensive Infrastructure as Code (IaC) solution for deploying a production-ready Kubernetes cluster on Proxmox with monitoring, backup, and network scanning capabilities.

## 🏗️ Architecture Overview

This project deploys a complete Kubernetes infrastructure stack including:

- **Kubernetes Cluster**: K3s-based cluster with control plane and worker nodes
- **Load Balancing**: MetalLB for bare-metal load balancing
- **Monitoring Stack**: Prometheus, Grafana, Loki, and Mimir for comprehensive observability
- **Log Aggregation**: Syslog receiver for OPNsense and external device logs
- **Backup System**: Automated backup solution with NFS storage
- **Ingress**: Nginx ingress controller with host-based routing
- **Automation**: N8N workflow automation platform

## 🚀 Quick Start

### Prerequisites

- Proxmox VE 7.0+ with API access
- Terraform 1.0+
- SSH key pair for VM access
- NFS server for backup storage (optional)

### 1. Clone and Configure

```bash
git clone <repository-url>
cd kubernetes-proxmox-infrastructure
cp terraform.tfvars.example terraform.tfvars
```

### 2. Configure Variables

Edit `terraform.tfvars` with your environment settings:

```hcl
# Proxmox Configuration
proxmox_api_url      = "https://your-proxmox:8006/api2/json"
proxmox_api_token_id = "your-token-id"
proxmox_api_token_secret = "your-token-secret"

# VM Configuration
ssh_public_key_path  = "~/.ssh/id_ed25519.pub"
ssh_private_key_path = "~/.ssh/id_ed25519"

# Network Configuration
vm_network_bridge = "vmbr0"
vm_network_vlan   = 100

# NFS Backup Configuration (optional)
nfs_server_ip   = "192.168.1.100"
nfs_backup_path = "/data/kubernetes/backups"
```

### 3. Deploy Infrastructure

```bash
# Pre-flight checks
./scripts/deployment/pre-flight-check.sh

# Deploy full stack
./scripts/deployment/deploy-full-stack.sh
```

## 📁 Project Structure

```
├── docs/                          # Documentation
│   ├── deployment/               # Deployment guides
│   ├── backup/                   # Backup documentation
│   ├── monitoring/               # Monitoring setup
│   └── troubleshooting/          # Troubleshooting guides
├── scripts/                      # Automation scripts
│   ├── deployment/               # Deployment scripts
│   ├── backup/                   # Backup and restore scripts
│   ├── maintenance/              # Maintenance scripts
│   └── troubleshooting/          # Troubleshooting scripts
├── configs/                      # Configuration files
│   ├── grafana/                  # Grafana dashboards
│   ├── prometheus/               # Prometheus configs
│   └── backup/                   # Backup configurations
├── *.tf                          # Terraform configuration files
└── terraform.tfvars              # Environment variables
```

## 🔧 Components

### Infrastructure (Terraform)

- **`main.tf`**: Main Terraform configuration
- **`proxmox-vms.tf`**: VM definitions and provisioning
- **`k8s-cluster.tf`**: Kubernetes cluster setup
- **`metallb.tf`**: Load balancer configuration
- **`observability.tf`**: Monitoring stack deployment

- **`backup.tf`**: Backup system configuration
- **`ingress.tf`**: Ingress controller setup

### Key Features

#### 🔍 Monitoring & Observability
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation and analysis
- **Mimir**: Long-term metrics storage


#### 💾 Backup & Recovery
- **Automated Backups**: Scheduled ETCD and application data backups
- **Manual Backup Triggers**: On-demand backup capabilities
- **Restoration Testing**: Comprehensive restore validation
- **NFS Storage**: Centralized backup storage with redundancy

#### 🌐 Networking
- **MetalLB**: Layer 2 load balancing for bare-metal
- **Traefik Ingress**: HTTP/HTTPS routing with automatic SSL
- **Network Policies**: Secure inter-pod communication

## 📖 Documentation

### Deployment
- [Deployment Guide](docs/deployment/DEPLOYMENT-GUIDE.md)
- [VM Setup](docs/deployment/VM-SETUP.md)
- [API Token Setup](docs/deployment/API-TOKEN-SETUP.md)

### Backup & Recovery
- [Backup Guide](docs/backup/BACKUP_GUIDE.md)
- [Manual Backup Guide](docs/backup/MANUAL_BACKUP_GUIDE.md)
- [Backup Dashboard Guide](docs/backup/BACKUP_DASHBOARD_GUIDE.md)

### Monitoring
- [Grafana Dashboards](docs/monitoring/GRAFANA_DASHBOARDS.md)

### Troubleshooting

- [NFS Access Fix](docs/troubleshooting/NFS_ACCESS_FIX.md)
- [Kubeconfig Issues](docs/troubleshooting/KUBECONFIG_ENCODING_FIX.md)

## 🛠️ Common Operations

### Deployment

```bash
# Full stack deployment
./scripts/deployment/deploy-full-stack.sh

# Step-by-step deployment
./scripts/deployment/deploy-step-by-step.sh

# Pre-flight checks
./scripts/deployment/pre-flight-check.sh
```

### Backup Operations

```bash
# Manual backup (all components)
./scripts/backup/trigger-manual-backup.sh

# Test backup restoration
./scripts/backup/test-backup-restoration.sh dry-run

# Restore specific component
./scripts/backup/test-individual-restore.sh grafana
```

### Maintenance

```bash
# Check NFS permissions
./scripts/maintenance/test-nfs-permissions.sh

# Update Grafana dashboards
./scripts/maintenance/update-grafana-dashboards.sh


```

### Troubleshooting

```bash
# Diagnose NFS access issues
./scripts/troubleshooting/diagnose-nfs-access.sh



# Fix kubeconfig secret encoding
./scripts/troubleshooting/fix-kubeconfig-secret.sh
```

## 🔐 Security Considerations

- **SSH Key Authentication**: Password authentication disabled by default
- **Network Segmentation**: VLANs and network policies for isolation
- **Secret Management**: Kubernetes secrets for sensitive data
- **Backup Encryption**: Consider encrypting backup data at rest
- **Access Control**: RBAC policies for service accounts

## 📊 Monitoring & Alerting

### Default Dashboards
- **Kubernetes Cluster Overview**: Node and pod metrics
- **Backup Monitoring**: Backup status and performance

- **Application Metrics**: Component-specific dashboards

### Key Metrics
- Cluster resource utilization
- Backup success/failure rates
- Network device discovery status
- Application performance metrics

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation**: Check the `docs/` directory for detailed guides
- **Issues**: Report bugs and feature requests via GitHub issues
- **Troubleshooting**: Use the troubleshooting scripts in `scripts/troubleshooting/`

## 🏷️ Version

Current version: 1.0.0

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and updates.

---

**Note**: This infrastructure is designed for production use but should be thoroughly tested in your environment before deployment. Always follow your organization's security and operational guidelines.