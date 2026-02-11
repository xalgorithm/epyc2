# Terraform Infrastructure

This directory contains all Terraform configuration for the homelab Kubernetes infrastructure.

## Directory Structure

All Terraform files are organized at the root level with clear naming conventions:

```
terraform/
├── Core Configuration
│   ├── main.tf                          # Main configuration
│   ├── providers.tf                     # Provider configurations
│   ├── versions.tf                      # Version constraints
│   ├── backend.tf                       # Backend configuration
│   ├── variables.tf                     # Variable definitions
│   ├── outputs.tf                       # Output definitions
│   ├── terraform.tfvars                 # Variable values (gitignored)
│   └── terraform.tfvars.example         # Example variable values
│
├── Infrastructure Layer
│   ├── infrastructure-proxmox.tf        # Proxmox VM definitions
│   ├── infrastructure-network.tf        # MetalLB and networking
│   ├── infrastructure-rebellion.tf      # Rebellion cluster VMs
│   └── infrastructure-work.tf           # Work VM configuration
│
├── Kubernetes Platform
│   ├── kubernetes-cluster.tf            # Main cluster setup
│   ├── kubernetes-rebellion-cluster.tf  # Rebellion cluster setup
│   ├── kubernetes-storage.tf            # NFS storage configuration
│   ├── kubernetes-ingress.tf            # Ingress resources
│   ├── kubernetes-rebellion-metallb.tf  # Rebellion MetalLB
│   └── kubernetes-rebellion-monitoring.tf # Rebellion monitoring
│
├── Platform Services
│   ├── monitoring.tf                    # Prometheus, Grafana, Loki, Mimir
│   ├── monitoring-proxmox.tf            # Proxmox monitoring integration
│   ├── backup.tf                        # Backup system and CronJobs
│   └── opnsense-logging.tf             # OPNsense log integration
│
└── Applications
    ├── applications-immich.tf           # Immich photo management
    ├── applications-media.tf            # Media applications
    ├── applications-automation.tf       # Automation tools (N8N)
    └── applications-nest.tf             # Nest thermostat integration
```

## Naming Conventions

Files are organized by prefix for easy identification:

- **`infrastructure-*`**: Base infrastructure (VMs, networking)
- **`kubernetes-*`**: Kubernetes clusters and platform
- **`monitoring-*`**: Monitoring and observability
- **`applications-*`**: Application deployments
- **`backup.tf`**: Backup and restore system
- **`opnsense-logging.tf`**: External log integration

## Usage

### Initialize Terraform

```bash
cd terraform
terraform init
```

### Plan Changes

```bash
terraform plan
```

### Apply Changes

```bash
terraform apply
```

### Validate Configuration

```bash
terraform validate
```

## Configuration Files

- **terraform.tfvars**: Contains actual values for variables (not committed to git)
- **terraform.tfvars.example**: Template showing required variables

## External Dependencies

- **../configs/**: Configuration files for applications (Grafana dashboards, Prometheus configs, etc.)
- **../scripts/**: Backup and maintenance scripts referenced by resources

## Notes

- All file paths use `${path.root}/../` to reference configs and scripts at the workspace root
- Files are organized with clear naming prefixes for easy navigation
- State is managed locally (can be migrated to remote backend if needed)
- Resources share a single state file for simplified management
