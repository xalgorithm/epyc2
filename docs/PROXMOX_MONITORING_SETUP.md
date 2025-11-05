# Proxmox VE Monitoring Setup

## Overview

This configuration deploys a Proxmox VE exporter to collect metrics from your Proxmox hypervisor and make them available in Prometheus/Grafana.

## Architecture

```
Proxmox VE (192.168.0.7:8006)
    │
    └──> Proxmox Exporter (pod in monitoring namespace)
         │
         └──> Prometheus (scrapes every 60s)
              │
              └──> Mimir (long-term storage)
                   │
                   └──> Grafana (visualization)
```

## What's Deployed

### 1. Proxmox Exporter
- **Image**: `prompve/prometheus-pve-exporter:latest`
- **Port**: 9221
- **Metrics Path**: `/pve`
- **Scrape Interval**: 60 seconds

### 2. Kubernetes Resources
- **Deployment**: `proxmox-exporter` (1 replica)
- **Service**: `proxmox-exporter` (ClusterIP)
- **ConfigMap**: `proxmox-exporter-config` (configuration)
- **Secret**: `proxmox-exporter-secret` (credentials)

### 3. Prometheus Configuration
Added scrape job for Proxmox metrics

## Metrics Available

The exporter provides metrics like:

```promql
# CPU Usage
pve_cpu_usage_ratio
pve_cpu_usage_limit

# Memory
pve_memory_usage_bytes
pve_memory_size_bytes

# Disk
pve_disk_usage_bytes
pve_disk_size_bytes

# Guest/VM Info
pve_guest_info
pve_vm_cpu_usage
pve_vm_memory_usage_bytes

# Cluster Status
pve_up
pve_node_info
pve_cluster_info
```

## Configuration

### Required Variables

The following Terraform variables are used (already configured in your `terraform.tfvars`):

```hcl
proxmox_api_url      = "https://192.168.0.7:8006/api2/json"
proxmox_user         = "root@pam"
proxmox_password     = "your-password"  # Or use API token
proxmox_tls_insecure = true  # Set to false if you have valid SSL
```

### Alternative: Using API Token

For better security, use an API token instead of password:

1. **Create API Token in Proxmox**:
   - Go to: **Datacenter** → **Permissions** → **API Tokens**
   - Click **Add**
   - User: `root@pam`
   - Token ID: `monitoring`
   - Privilege Separation: **Unchecked** (for read-only monitoring)
   - Click **Add**

2. **Update** `monitoring-proxmox.tf` to use token authentication (future enhancement)

## Deployment

### Apply Configuration

```bash
# Deploy Proxmox exporter
terraform apply

# Wait for exporter to be ready
kubectl rollout status deployment/proxmox-exporter -n monitoring

# Restart Prometheus to pick up new scrape config
kubectl rollout restart deployment/prometheus -n monitoring
```

### Verification

1. **Check Exporter Pod**:
   ```bash
   kubectl get pods -n monitoring -l app=proxmox-exporter
   ```

2. **Check Exporter Logs**:
   ```bash
   kubectl logs -n monitoring -l app=proxmox-exporter
   ```

3. **Test Exporter Endpoint**:
   ```bash
   kubectl port-forward -n monitoring svc/proxmox-exporter 9221:9221
   curl http://localhost:9221/pve?target=192.168.0.7
   ```

4. **Check Prometheus Target**:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   # Open: http://localhost:9090/targets
   # Find: proxmox job (should be UP)
   ```

5. **Query Metrics in Prometheus**:
   ```promql
   # Check if exporter is up
   up{job="proxmox"}
   
   # CPU usage
   pve_cpu_usage_ratio * 100
   
   # Memory usage
   (pve_memory_usage_bytes / pve_memory_size_bytes) * 100
   
   # All Proxmox metrics
   {job="proxmox"}
   ```

## Grafana Dashboard

The Proxmox dashboard (`proxmox-dashboard.json`) will now display data:

```bash
open http://grafana.home/d/proxmox-ve-monitoring
```

Dashboard panels include:
- CPU Usage
- Memory Usage
- Disk Usage
- VM/Container Status
- Node Information
- Cluster Health

## Troubleshooting

### Exporter Pod Crashes

**Check logs**:
```bash
kubectl logs -n monitoring -l app=proxmox-exporter --tail=50
```

**Common issues**:
- Invalid Proxmox credentials
- Network connectivity to Proxmox
- SSL certificate issues (set `proxmox_tls_insecure = true`)

### Target is DOWN in Prometheus

1. **Check exporter is running**:
   ```bash
   kubectl get pods -n monitoring -l app=proxmox-exporter
   ```

2. **Test exporter endpoint**:
   ```bash
   kubectl port-forward -n monitoring svc/proxmox-exporter 9221:9221
   curl http://localhost:9221/pve
   ```

3. **Check Prometheus logs**:
   ```bash
   kubectl logs -n monitoring -l app=prometheus --tail=100 | grep proxmox
   ```

### Authentication Errors

**Error**: `401 Unauthorized` or `403 Forbidden`

**Solutions**:
- Verify `proxmox_user` and `proxmox_password` in `terraform.tfvars`
- Ensure user has PVEAuditor role (for read-only monitoring)
- Check Proxmox logs: `/var/log/pve/tasks/`

### SSL/TLS Errors

**Error**: `certificate verify failed`

**Solution**: Set in `terraform.tfvars`:
```hcl
proxmox_tls_insecure = true
```

Or configure proper SSL certificates in Proxmox.

### No Data in Dashboard

1. **Verify metrics exist**:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   # Query: {job="proxmox"}
   ```

2. **Check time range**: Dashboard should show last 1 hour

3. **Check metric names**: Proxmox exporter metric names start with `pve_`

## Metrics Reference

### Node Metrics

```promql
# CPU
pve_cpu_usage_ratio              # 0.0 to 1.0
pve_cpu_usage_limit              # Number of CPU cores

# Memory
pve_memory_usage_bytes           # Used memory
pve_memory_size_bytes            # Total memory

# Disk
pve_disk_usage_bytes             # Used disk
pve_disk_size_bytes              # Total disk

# Status
pve_up                           # 1 if node is up, 0 otherwise
pve_node_info                    # Node information labels
```

### VM/Container Metrics

```promql
# Guest Info
pve_guest_info{name="vm-name"}   # VM information

# CPU
pve_vm_cpu_usage                 # VM CPU usage percentage

# Memory
pve_vm_memory_usage_bytes        # VM memory usage

# Disk
pve_vm_disk_read_bytes           # VM disk reads
pve_vm_disk_write_bytes          # VM disk writes

# Network
pve_vm_net_in_bytes              # VM network in
pve_vm_net_out_bytes             # VM network out
```

## Performance Tuning

### Adjust Scrape Interval

If you have many VMs/containers, you may want to reduce scrape frequency:

Edit `configs/prometheus/prometheus.yml`:
```yaml
  - job_name: 'proxmox'
    scrape_interval: 120s  # Changed from 60s
    scrape_timeout: 60s    # Changed from 30s
```

### Resource Limits

Adjust in `monitoring-proxmox.tf`:
```hcl
resources {
  requests = {
    cpu    = "200m"    # Increased from 100m
    memory = "256Mi"   # Increased from 128Mi
  }
  limits = {
    cpu    = "500m"    # Increased from 200m
    memory = "512Mi"   # Increased from 256Mi
  }
}
```

## Security Best Practices

1. **Use API Tokens**: Prefer API tokens over passwords
2. **Read-Only Access**: Use PVEAuditor role for monitoring
3. **Network Segmentation**: Proxmox exporter only needs API access (8006)
4. **SSL/TLS**: Use valid certificates when possible
5. **Secret Management**: Credentials stored in Kubernetes secrets

## Additional Resources

- [Proxmox VE Exporter GitHub](https://github.com/prometheus-pve/prometheus-pve-exporter)
- [Proxmox API Documentation](https://pve.proxmox.com/wiki/Proxmox_VE_API)
- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)

## Summary

After deployment:
- ✅ Proxmox exporter running in Kubernetes
- ✅ Prometheus scraping Proxmox metrics every 60 seconds
- ✅ Metrics stored in Mimir for long-term retention
- ✅ Grafana dashboard displaying Proxmox VE data

Your Proxmox monitoring is now fully operational! 🚀

