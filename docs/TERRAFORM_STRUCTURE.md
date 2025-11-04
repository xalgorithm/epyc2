# Terraform Project Structure

This document describes the organization of the Terraform configuration files for the homelab infrastructure.

## Overview

The Terraform configuration follows best practices with clear separation of concerns and logical grouping of resources.

## File Organization

### Core Configuration Files

These files contain fundamental Terraform configurations:

- **`versions.tf`** - Terraform and provider version requirements
- **`providers.tf`** - Provider configurations (Kubernetes, Helm, Proxmox, etc.)
- **`variables.tf`** - Input variable declarations
- **`outputs.tf`** - Output value declarations
- **`backend.tf`** - Backend configuration (NFS-based state storage)
- **`main.tf`** - Entry point and documentation

### Infrastructure Layer

Files managing physical and virtual infrastructure:

- **`infrastructure-proxmox.tf`** - Proxmox VM definitions and cloud-init configurations
  - VM creation for control plane (bumblebee) and workers (prime, wheeljack)
  - Cloud-init user data
  - VM resource specifications

- **`infrastructure-network.tf`** - Network infrastructure
  - MetalLB load balancer configuration
  - NGINX Ingress Controller deployment
  - Network policies and settings

### Kubernetes Platform Layer

Files managing core Kubernetes cluster and platform services:

- **`kubernetes-cluster.tf`** - Kubernetes cluster bootstrapping
  - Kubeconfig management
  - Control plane setup
  - Worker node configuration
  - Cluster API readiness checks

- **`kubernetes-storage.tf`** - Storage configuration
  - NFS CSI driver deployment
  - Storage class definitions
  - PVC validation and checks

- **`kubernetes-ingress.tf`** - Ingress resource definitions
  - Monitoring service ingresses (Grafana, Prometheus, Loki, Mimir)
  - Application ingresses (Mylar, N8N)

### Monitoring and Observability Layer

Files managing monitoring, logging, and backup:

- **`monitoring.tf`** - Observability stack
  - Prometheus deployment and configuration
  - Grafana deployment and dashboards
  - Loki log aggregation
  - Mimir metrics storage
  - Promtail log collection
  - Node Exporter metrics
  - Kube State Metrics

- **`backup.tf`** - Backup infrastructure
  - ETCD backup CronJobs
  - Data backup CronJobs
  - Backup cleanup jobs
  - Backup metrics collection

- **`opnsense-logging.tf`** - OPNsense router log integration
  - Syslog-ng deployment
  - Log forwarding to Loki
  - Service configuration

### Application Layer

Files managing user-facing applications:

- **`applications-media.tf`** - Media applications
  - Mylar (comic book manager)
  - Media namespace configuration

- **`applications-automation.tf`** - Automation applications
  - N8N workflow automation
  - Automation namespace configuration

## Resource Naming Conventions

### File Naming
- Use lowercase with hyphens
- Group by layer: `infrastructure-*`, `kubernetes-*`, `applications-*`
- Use descriptive names: `monitoring.tf`, `backup.tf`

### Resource Naming
- Use underscores in resource names: `kubernetes_namespace.monitoring`
- Use descriptive, hierarchical names
- Prefix application resources with app name

## Dependencies and Order

Terraform automatically handles most dependencies, but the logical order is:

1. **Infrastructure Layer** - VMs and network
   - Proxmox VMs created
   - MetalLB installed
   - Ingress controller deployed

2. **Kubernetes Platform** - Cluster setup
   - Cluster bootstrapped
   - Storage configured
   - Kubeconfig available

3. **Platform Services** - Core services
   - Monitoring stack deployed
   - Backup jobs configured
   - Logging integration enabled

4. **Applications** - User applications
   - Media applications deployed
   - Automation tools deployed

## Key Resources

### Gating Resources

These resources control deployment flow:

- `null_resource.kubeconfig_ready` - Gates all Kubernetes resources
- `null_resource.cluster_api_ready` - Ensures API server is accessible
- `null_resource.metallb_operational` - Ensures load balancer is ready
- `null_resource.validate_service_data` - Validates NFS storage

### Bootstrap Control

The `bootstrap_cluster` variable controls cluster initialization:

- `true` - Terraform manages full cluster lifecycle
- `false` - External cluster, Terraform manages resources only

## Configuration Variables

All variables are defined in `variables.tf` and organized by category:

- **Cluster Configuration** - Control plane, workers, bootstrap settings
- **Kubernetes Configuration** - Version, network CIDRs
- **SSH Configuration** - Access credentials
- **Network Configuration** - MetalLB, Ingress IPs
- **Ingress Hostnames** - Service domain names
- **Docker Hub Configuration** - Image pull credentials
- **Proxmox Configuration** - API access, VM settings
- **NFS Storage Configuration** - Storage paths
- **Backup Configuration** - Retention, paths

## Outputs

All outputs are centralized in `outputs.tf` and grouped by:

- **Infrastructure** - VM info, cluster details, network config
- **Storage** - NFS and backup configuration
- **Service Endpoints** - URLs and access information
- **Useful Commands** - Common kubectl commands

## Best Practices

1. **Separation of Concerns** - Each file has a single, clear purpose
2. **Logical Grouping** - Related resources grouped together
3. **Clear Naming** - File and resource names are descriptive
4. **Documentation** - Comments explain complex configurations
5. **Dependency Management** - Explicit `depends_on` where needed
6. **Idempotency** - Configurations can be safely re-applied

## Making Changes

### Adding New Infrastructure

1. Add to appropriate layer file (infrastructure-*, kubernetes-*, applications-*)
2. Add required variables to `variables.tf`
3. Add outputs to `outputs.tf`
4. Update this documentation

### Modifying Existing Resources

1. Locate the resource in its layer file
2. Make changes following existing patterns
3. Run `terraform validate` to check syntax
4. Test with `terraform plan`

### Adding New Applications

1. Create new file: `applications-[category].tf`
2. Define namespace, deployment, service, ingress
3. Add outputs to `outputs.tf`
4. Update documentation

## Deployment Commands

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan changes
terraform plan

# Apply changes
terraform apply

# Target specific resource
terraform apply -target=resource.name

# Use helper scripts
./scripts/deployment/deploy-full-stack.sh
```

## Related Documentation

- [Deployment Guide](deployment/DEPLOYMENT-GUIDE.md)
- [Deployment Order](deployment/DEPLOYMENT_ORDER.md)
- [Backend Configuration](TERRAFORM_BACKEND.md)
- [Scripts Organization](SCRIPTS_ORGANIZATION.md)

