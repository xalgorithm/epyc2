# NetAlertX Network Monitoring Setup

NetAlertX (formerly Pi.Alert) is a network monitoring tool that provides device discovery, change notifications, and network topology mapping for your homelab.

## 🌐 Configuration Overview

### Network Scanning
- **Scan Range**: `192.168.1.0/16` (entire homelab network)
- **Scan Interval**: 5 minutes
- **Scan Methods**: ARP scan, ping scan, nmap discovery
- **Network Interface**: Host network mode for direct network access

### Web Interface
- **URL**: `http://netalertx.home`
- **Port**: 20211
- **Authentication**: None (internal network only)
- **Features**: Device management, notifications, network topology

### Storage
- **Database Volume**: 2GB NFS persistent storage for SQLite database
- **Configuration Volume**: 100MB NFS persistent storage for app.conf
- **Database**: SQLite database for device tracking (persistent)
- **Configuration**: app.conf settings (persistent across pod recreations)
- **Logs**: Container logs for troubleshooting

## 🚀 Deployment

### Quick Deployment
```bash
# Deploy NetAlertX only
./scripts/deploy-netalertx.sh

# Or deploy with full stack
./scripts/deploy-full-stack.sh
```

### Manual Terraform Deployment
```bash
# Deploy NetAlertX resources
terraform apply -target=kubernetes_namespace.netalertx \
               -target=kubernetes_config_map.netalertx_config \
               -target=kubernetes_persistent_volume_claim.netalertx_data \
               -target=kubernetes_deployment.netalertx \
               -target=kubernetes_service.netalertx \
               -target=kubernetes_ingress_v1.netalertx
```

## 🔧 DNS Setup

### Automatic DNS Setup
```bash
./scripts/setup-ingress-dns.sh
```

### Manual DNS Setup
Add to `/etc/hosts`:
```
192.168.1.40 netalertx.home
```

## 📊 Features

### Device Discovery
- **Automatic Detection**: Discovers all devices on 192.168.1.0/16
- **Device Tracking**: Maintains historical device database
- **Change Notifications**: Alerts on new/changed/missing devices
- **Device Classification**: Categorizes devices by type and vendor

### Network Monitoring
- **Real-time Scanning**: Continuous network monitoring
- **Topology Mapping**: Visual network topology
- **Port Scanning**: Service discovery on detected devices
- **DHCP Integration**: Tracks DHCP lease information

### Web Interface
- **Dashboard**: Overview of network status and devices
- **Device Management**: Add/edit/delete device information
- **Notifications**: Configure alerts and notifications
- **Reports**: Generate network reports and statistics

## 🔍 Troubleshooting

### Debug Script
```bash
./scripts/debug-netalertx.sh
```

### Common Issues

#### 1. Pod Not Starting
```bash
# Check pod status
kubectl get pods -n netalertx -l app=netalertx

# Check pod events
kubectl describe pod -n netalertx -l app=netalertx

# Check logs
kubectl logs -n netalertx deployment/netalertx
```

#### 2. Web Interface Not Accessible
```bash
# Check ingress
kubectl get ingress -n netalertx

# Test DNS resolution
ping netalertx.home

# Check service
kubectl get svc -n netalertx
```

#### 3. Network Scanning Not Working
```bash
# Verify host network mode
kubectl get pod -n netalertx -l app=netalertx -o jsonpath='{.items[0].spec.hostNetwork}'

# Check security context
kubectl get pod -n netalertx -l app=netalertx -o jsonpath='{.items[0].spec.containers[0].securityContext}'

# Test network tools
kubectl exec -n netalertx deployment/netalertx -- ping -c 1 192.168.1.1
```

#### 4. Configuration Not Writable
```bash
# Test configuration writability
./scripts/test-netalertx-config.sh

# Check init container logs
kubectl logs -n netalertx deployment/netalertx -c netalertx-init

# Verify file permissions
kubectl exec -n netalertx deployment/netalertx -- ls -la /app/config/app.conf
```

#### 5. Data Not Persisting
```bash
# Check persistent volume claim
kubectl describe pvc netalertx-data -n netalertx

# Check NFS storage
kubectl get storageclass nfs-storage
```

### Log Analysis
```bash
# Follow logs in real-time
kubectl logs -n netalertx deployment/netalertx -f

# Get recent logs
kubectl logs -n netalertx deployment/netalertx --tail=50

# Check for specific errors
kubectl logs -n netalertx deployment/netalertx | grep -i error
```

## ⚙️ Configuration

### Network Configuration
The NetAlertX configuration is stored in a ConfigMap:
```bash
kubectl get configmap netalertx-config -n netalertx -o yaml
```

### Key Configuration Options
- **SCAN_SUBNETS**: `['192.168.1.0/16']`
- **SCAN_CYCLE_MINUTES**: `5`
- **INTERFACE**: `eth0`
- **NMAP_ARGS**: `-sn --host-timeout 10s`
- **ARPSCAN_ARGS**: `-l -g -t 1000`

### Customization
To modify the configuration:
1. Edit `netalertx.tf` configuration
2. Apply changes: `terraform apply -target=kubernetes_config_map.netalertx_config`
3. Restart deployment: `kubectl rollout restart deployment/netalertx -n netalertx`

## 🔒 Security Considerations

### Network Access
- **Host Network**: Required for network scanning capabilities
- **Capabilities**: NET_ADMIN and NET_RAW for network operations
- **Root Access**: Runs as root for network tool access

### Internal Network Only
- **No External Access**: Web interface only accessible internally
- **No Authentication**: Relies on network security
- **Firewall**: Ensure proper firewall rules on cluster nodes

## 📈 Monitoring Integration

### Prometheus Metrics
NetAlertX doesn't expose Prometheus metrics by default, but you can monitor:
- Pod health via Kubernetes metrics
- Resource usage via container metrics
- Network scanning activity via logs

### Grafana Integration
- Monitor NetAlertX pod status in Kubernetes dashboards
- Track resource usage and performance
- Set up log-based alerts via Loki

### Log Integration
- Logs are collected by Promtail
- Available in Grafana via Loki datasource
- Search logs: `{namespace="netalertx"}`

## 🎯 Usage Tips

### Initial Setup
1. **First Scan**: Allow 5-10 minutes for initial network discovery
2. **Device Database**: Devices will populate gradually
3. **False Positives**: Review and categorize unknown devices
4. **Notifications**: Configure alerts for network changes

### Best Practices
- **Regular Review**: Check device list weekly
- **Device Naming**: Add descriptive names for devices
- **Network Segmentation**: Consider scanning specific subnets
- **Backup Database**: Persistent storage ensures data retention

### Performance Optimization
- **Scan Interval**: Adjust based on network size and activity
- **Timeout Settings**: Tune for network responsiveness
- **Resource Limits**: Monitor CPU and memory usage

## ✅ Configuration Persistence

### Fully Persistent Storage
- **Configuration Changes**: All settings modified through web UI are permanent
- **Database Persistence**: Device database and scan history persist across pod recreations
- **Volume Storage**: Both database (2GB) and configuration (100MB) use NFS persistent volumes
- **No Data Loss**: Pod restarts, updates, or cluster maintenance won't lose your settings

### Migration from Non-Persistent Setup
If you have an existing NetAlertX deployment with non-persistent configuration:
```bash
# Migrate to persistent configuration
./scripts/migrate-netalertx-config.sh
```

### Configuration Management
- **Initial Setup**: Configuration template comes from Terraform ConfigMap
- **Runtime Changes**: Web UI modifications are saved to persistent volume
- **Backup**: Configuration is automatically backed up on NFS storage
- **Reset**: Delete PVC to reset to default configuration

## 🔄 Maintenance

### Updates
```bash
# Update NetAlertX image
kubectl set image deployment/netalertx netalertx=jokobsk/netalertx:latest -n netalertx

# Restart deployment
kubectl rollout restart deployment/netalertx -n netalertx
```

### Backup
```bash
# Backup database (stored in persistent volume)
kubectl exec -n netalertx deployment/netalertx -- cp /app/db/pialert.db /app/db/pialert.db.backup

# Backup configuration (stored in persistent volume)
kubectl exec -n netalertx deployment/netalertx -- cp /app/config/app.conf /app/config/app.conf.backup
```

### Cleanup
```bash
# Remove NetAlertX
terraform destroy -target=kubernetes_namespace.netalertx
```

## 📚 Additional Resources

### Documentation
- [NetAlertX GitHub](https://github.com/jokob-sk/NetAlertX)
- [Original Pi.Alert](https://github.com/pucherot/Pi.Alert)

### Support
- Check logs: `kubectl logs -n netalertx deployment/netalertx`
- Debug script: `./scripts/debug-netalertx.sh`
- Community support via GitHub issues

---

NetAlertX provides comprehensive network monitoring for your homelab, scanning the entire 192.168.1.0/16 network and providing detailed device discovery and change tracking capabilities.