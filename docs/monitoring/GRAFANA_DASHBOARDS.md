# Comprehensive Grafana Dashboards

This document describes the comprehensive Kubernetes monitoring and log analysis dashboards included in your Grafana deployment.

## 📊 Dashboard Overview

### 🏠 Original Dashboards
- **Homelab Dashboard** - General homelab infrastructure overview
- **Prometheus Dashboard** - Prometheus metrics and operational status
- **Loki Logs Dashboard** - Basic log viewing and search
- **Mimir Dashboard** - Long-term metrics storage and queries
- **Node Exporter Dashboard** - System-level metrics (CPU, memory, disk, network)
- **Proxmox Dashboard** - Virtualization platform monitoring
- **Backup Dashboard** - Backup system status and job monitoring

### 🚀 New Kubernetes Dashboards

#### 1. Kubernetes Cluster Overview
**Purpose**: High-level cluster health and resource utilization
**Key Metrics**:
- Cluster-wide CPU and memory usage
- Total nodes, pods, deployments, and services
- Resource utilization trends
- Overall cluster health status

**Use Cases**:
- Quick cluster health assessment
- Capacity planning
- Resource utilization monitoring

#### 2. Kubernetes Pods & Workloads
**Purpose**: Detailed pod status and workload monitoring
**Key Features**:
- Pod status table with health indicators
- Memory and CPU usage by namespace
- Resource consumption trends
- Workload distribution analysis

**Use Cases**:
- Pod troubleshooting
- Namespace resource analysis
- Workload performance monitoring

#### 3. Kubernetes Logs Analysis
**Purpose**: Comprehensive log analysis and troubleshooting
**Key Features**:
- Log volume by namespace
- Error/warning/info log level analysis
- Top pods by log volume
- Interactive log filtering by namespace and pod
- Real-time error and warning log streams

**Use Cases**:
- Application troubleshooting
- Error pattern analysis
- Log volume monitoring
- Security incident investigation

#### 4. Kubernetes Resource Monitoring
**Purpose**: Detailed resource usage and performance monitoring
**Key Features**:
- Pod resource usage table with CPU/memory percentages
- Persistent volume capacity monitoring
- Pod restart count tracking
- Network I/O by pod (RX/TX)
- Disk I/O by pod (read/write)

**Use Cases**:
- Performance optimization
- Resource bottleneck identification
- I/O performance analysis
- Capacity planning

#### 5. Kubernetes Events & Alerts
**Purpose**: System events monitoring and health alerting
**Key Features**:
- Kubernetes events table with filtering
- Unhealthy pods and nodes count
- Unavailable replicas monitoring
- Pod restart alerts
- Critical system log analysis

**Use Cases**:
- System health monitoring
- Proactive issue detection
- Event correlation analysis
- Infrastructure alerting

## 🎯 Dashboard Features

### Interactive Elements
- **Time Range Selection**: All dashboards support custom time ranges
- **Variable Filtering**: Namespace and pod filtering where applicable
- **Drill-down Capabilities**: Click through from overview to detailed views
- **Real-time Updates**: Live data refresh for monitoring

### Visual Indicators
- **Color-coded Status**: Green/yellow/red indicators for health status
- **Gradient Gauges**: Resource usage visualization
- **Trend Analysis**: Time-series graphs for pattern identification
- **Alert Highlighting**: Critical issues prominently displayed

## 🔧 Usage Guide

### Getting Started
1. Access Grafana at `http://grafana.home` (admin/admin)
2. Start with **Kubernetes Cluster Overview** for general health
3. Use **Kubernetes Logs Analysis** for troubleshooting
4. Monitor performance with **Kubernetes Resource Monitoring**

### Troubleshooting Workflow
1. **Cluster Overview** → Check overall health
2. **Events & Alerts** → Identify system issues
3. **Logs Analysis** → Investigate error patterns
4. **Resource Monitoring** → Check performance bottlenecks
5. **Pods & Workloads** → Examine specific workloads

### Best Practices
- **Regular Monitoring**: Check cluster overview daily
- **Proactive Alerting**: Monitor events and alerts dashboard
- **Log Analysis**: Use log filtering for efficient troubleshooting
- **Resource Planning**: Track resource usage trends
- **Performance Optimization**: Monitor I/O and restart patterns

## 📈 Metrics Collected

### Cluster Metrics
- Node status and resource usage
- Pod status and lifecycle events
- Deployment and service health
- Network and storage performance

### Application Metrics
- Container resource consumption
- Application-specific metrics (via annotations)
- Custom metrics from applications
- Service-level indicators

### Log Data
- Application logs from all pods
- System logs from Kubernetes components
- Error and warning log aggregation
- Log volume and pattern analysis

## 🚀 Deployment Integration

### Terraform Integration
- Dashboards are automatically deployed with the stack
- Configuration stored in `configs/` directory
- Updates applied via Terraform configuration
- Persistent across stack recreation

### Update Process
```bash
# Update dashboards only
./scripts/update-grafana-dashboards.sh

# Full stack redeployment (includes dashboard updates)
./scripts/deploy-full-stack.sh
```

### Customization
- Dashboard JSON files in `configs/` directory
- Modify dashboards through Grafana UI
- Export and save changes to Terraform configuration
- Version control dashboard configurations

## 🔍 Monitoring Capabilities

### Real-time Monitoring
- Live metrics and log streaming
- Instant alert notifications
- Real-time resource usage tracking
- Dynamic threshold monitoring

### Historical Analysis
- Long-term trend analysis via Mimir
- Log retention and historical search
- Performance pattern identification
- Capacity planning data

### Alerting Integration
- Prometheus alerting rules
- Grafana alert notifications
- Log-based alerting via Loki
- Custom alert conditions

## 📚 Additional Resources

### Documentation
- `DEPLOYMENT_ORDER.md` - Deployment sequence and dependencies
- `README.md` - General project overview
- Individual dashboard JSON files for customization

### Scripts
- `./scripts/update-grafana-dashboards.sh` - Update dashboards
- `./scripts/fix-loki-access.sh` - Loki troubleshooting
- `./scripts/setup-ingress-dns.sh` - DNS configuration

### Support
- Check pod logs: `kubectl logs -n monitoring deployment/grafana`
- Verify metrics: `kubectl get svc -n monitoring`
- Test connectivity: `curl http://grafana.home/api/health`

---

**Note**: These dashboards provide comprehensive monitoring for Kubernetes environments and are designed to work seamlessly with the deployed Prometheus, Loki, and Mimir stack.