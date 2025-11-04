# OPNsense Log Integration Guide

This guide explains how to integrate OPNsense firewall/router logs into your Kubernetes observability stack (Loki + Grafana).

## Overview

The setup uses:
- **syslog-ng** running in Kubernetes to receive logs
- **Loki** to store and index logs
- **Grafana** to visualize and query logs
- **MetalLB** to provide a static IP for the syslog receiver

## Architecture

```
OPNsense Router
     │
     │ (syslog/514 UDP/TCP)
     ↓
syslog-ng Service (192.168.0.36:514)
     │
     │ (HTTP)
     ↓
Loki (monitoring namespace)
     │
     │ (Query)
     ↓
Grafana Dashboards
```

## Prerequisites

1. **OPNsense** router accessible on your network
2. **Kubernetes cluster** with monitoring stack deployed
3. **MetalLB** configured with available IP in pool (192.168.0.36)
4. **Loki** deployed and running

## Step 1: Deploy Syslog Receiver

The Terraform configuration (`opnsense-logging.tf`) automatically creates:
- syslog-ng ConfigMap with forwarding rules
- syslog-ng Deployment
- LoadBalancer Service on 192.168.0.36:514 (UDP/TCP)

Deploy with:

```bash
terraform apply
```

## Step 2: Configure OPNsense

### Enable Remote Logging

1. **Login to OPNsense** web interface
2. Navigate to **System → Settings → Logging / Targets**
3. Click **Add** to create a new remote log target

### Configuration Details

| Setting | Value |
|---------|-------|
| **Enabled** | ✓ Checked |
| **Transport** | UDP(4) or TCP(6) |
| **Hostname** | `192.168.0.36` |
| **Port** | `514` |
| **Facility** | `Any` or specific (e.g., `local0`) |
| **Level** | `Informational` (or as needed) |
| **Program** | Leave empty or specify `opnsense` |
| **Description** | `Kubernetes Logging Stack` |

### Recommended Settings

```
Transport:    UDP(4)         # Fast, lossy but acceptable for logs
Hostname:     192.168.0.36
Port:         514
Facility:     Any
Level:        Informational
Certificate:  (none)
Description:  Kubernetes Loki
```

### What to Log

You can select specific log types:
- ✅ **Firewall** - Connection logs, blocks, allows
- ✅ **System** - System events, services
- ✅ **Web Proxy** (if enabled)
- ✅ **DHCP/DNS** - Client activity
- ✅ **VPN** (if configured)

Click **Save** to apply.

## Step 3: Verify Log Collection

### Check syslog-ng is Running

```bash
kubectl get pods -n monitoring -l app=syslog-ng
kubectl get svc syslog-ng -n monitoring
```

Expected output:
```
NAME                         READY   STATUS    RESTARTS   AGE
syslog-ng-xxxx-xxxx          1/1     Running   0          5m

NAME        TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
syslog-ng   LoadBalancer   10.96.xxx.xxx   192.168.0.36    514:xxxxx/UDP,514:xxxxx/TCP
```

### Check Logs are Arriving

```bash
# View syslog-ng logs
kubectl logs -n monitoring -l app=syslog-ng --tail=50

# Query Loki for OPNsense logs
kubectl exec -n monitoring -it $(kubectl get pod -n monitoring -l app=loki -o name | head -1) -- \
  wget -qO- 'http://localhost:3100/loki/api/v1/query?query={application="opnsense"}' | jq
```

### Test from OPNsense

From OPNsense command line (Diagnostics → Command Prompt):

```bash
# Test UDP
echo "test message from opnsense" | nc -u -w1 192.168.0.36 514

# Test TCP
echo "test message from opnsense" | nc -w1 192.168.0.36 514
```

## Step 4: Create Grafana Dashboards

### Access Grafana

Navigate to: `http://grafana.home`

### Explore OPNsense Logs

1. Go to **Explore** (compass icon)
2. Select **Loki** as data source
3. Use LogQL queries:

```logql
# All OPNsense logs
{application="opnsense"}

# Firewall blocks
{application="opnsense"} |~ "block"

# Recent denied connections
{application="opnsense"} |~ "Deny"

# Specific source IP
{application="opnsense"} |~ "192.168.0.x"

# Filter by severity
{application="opnsense"} |~ "error|warning"
```

### Create Dashboard Panels

Example queries for panels:

**1. Log Rate (logs per minute)**
```logql
sum(rate({application="opnsense"}[1m]))
```

**2. Top Blocked IPs**
```logql
{application="opnsense"} |~ "block"
  | regexp "SRC=(?P<src_ip>[0-9.]+)"
  | unwrap src_ip
```

**3. Firewall Action Distribution**
```logql
sum by (action) (
  count_over_time({application="opnsense"}[5m])
)
```

**4. Error and Warning Logs**
```logql
{application="opnsense"} |~ "error|warning|critical"
```

### Sample Dashboard JSON

Save this as a dashboard:

```json
{
  "dashboard": {
    "title": "OPNsense Firewall Logs",
    "panels": [
      {
        "title": "Log Volume",
        "targets": [
          {
            "expr": "sum(rate({application=\"opnsense\"}[1m]))"
          }
        ]
      },
      {
        "title": "Recent Firewall Events",
        "targets": [
          {
            "expr": "{application=\"opnsense\"} |~ \"filterlog\""
          }
        ]
      }
    ]
  }
}
```

## Step 5: Set Up Alerts (Optional)

### Grafana Alerting

Create alerts for important events:

**High Block Rate Alert**
```logql
sum(rate({application="opnsense"} |~ "block"[5m])) > 100
```

**Critical Errors**
```logql
count_over_time({application="opnsense"} |~ "critical|emergency"[5m]) > 0
```

### Alert Channels

Configure notification channels:
- Email
- Slack
- Discord
- Webhook (for n8n automation)

## Troubleshooting

### No Logs Appearing

1. **Check syslog-ng pod status:**
   ```bash
   kubectl get pods -n monitoring -l app=syslog-ng
   kubectl logs -n monitoring -l app=syslog-ng
   ```

2. **Verify service has external IP:**
   ```bash
   kubectl get svc syslog-ng -n monitoring
   ```

3. **Test network connectivity from OPNsense:**
   ```bash
   # From OPNsense shell
   nc -vz 192.168.0.36 514
   ```

4. **Check firewall rules:**
   - Ensure no firewall rules blocking UDP/TCP 514
   - Verify OPNsense can reach 192.168.0.36

### Logs Not Reaching Loki

1. **Check Loki is running:**
   ```bash
   kubectl get pods -n monitoring -l app=loki
   ```

2. **Check syslog-ng can reach Loki:**
   ```bash
   kubectl exec -n monitoring -l app=syslog-ng -- \
     wget -qO- http://loki.monitoring.svc.cluster.local:3100/ready
   ```

3. **Review syslog-ng configuration:**
   ```bash
   kubectl get configmap syslog-ng-config -n monitoring -o yaml
   ```

### High Memory Usage

If syslog-ng uses too much memory:

1. **Adjust buffer settings** in ConfigMap:
   ```
   log_fifo_size(10000)
   ```

2. **Increase resource limits:**
   ```bash
   kubectl edit deployment syslog-ng -n monitoring
   ```

## Log Format Examples

### Firewall Log Entry
```
filterlog: 5,,,1000000103,igb0,match,block,in,4,0x0,,64,12345,0,none,6,tcp,60,192.168.1.100,8.8.8.8,54321,443,0,S,1234567890,,64240,,mss
```

### System Log Entry
```
opnsense syslogd[12345]: kernel boot file is /boot/kernel/kernel
```

### DHCP Log Entry
```
dhcpd: DHCPACK on 192.168.1.50 to aa:bb:cc:dd:ee:ff via igb1
```

## Advanced Configuration

### Filter Specific Log Types

Modify the syslog-ng ConfigMap to filter logs:

```bash
kubectl edit configmap syslog-ng-config -n monitoring
```

Add filters:
```
filter f_firewall {
  message("filterlog");
};

filter f_dhcp {
  program("dhcpd");
};

log {
  source(s_opnsense);
  filter(f_firewall);
  destination(d_loki);
};
```

### Add Additional Labels

Enhance Loki labels for better filtering:

```
body('$(format-json 
  --scope rfc5424 
  --key streams 
  --pair label="{\\"job\\":\\"syslog\\",\\"host\\":\\"$HOST\\",\\"application\\":\\"opnsense\\",\\"facility\\":\\"$FACILITY\\",\\"severity\\":\\"$LEVEL\\"}" 
  --pair entries="[{\\"ts\\":\\"$ISODATE\\",\\"line\\":\\"$MESSAGE\\"}]"
)')
```

### Use TLS for Secure Transport

For production, consider using TLS:

1. Generate certificates
2. Configure OPNsense with TLS transport
3. Update syslog-ng to use TLS

## Performance Considerations

### Log Volume

OPNsense can generate significant log volume:
- **Low activity**: ~1-10 MB/day
- **Medium activity**: ~50-100 MB/day  
- **High activity**: ~500+ MB/day

### Retention

Configure Loki retention in `observability.tf`:
```hcl
limits_config:
  retention_period: 30d  # Adjust as needed
```

### Storage

Ensure adequate storage for Loki:
- 50Gi minimum for 30-day retention
- Scale based on log volume

## Security Best Practices

1. **Restrict Access**: Only allow OPNsense IP to send logs
2. **Use TLS**: Encrypt logs in transit (production)
3. **Rotate Logs**: Configure retention policies
4. **Monitor**: Alert on unexpected log volumes
5. **Backup**: Regular backups of critical logs

## Useful Commands

```bash
# View all OPNsense logs in real-time
kubectl logs -n monitoring -l app=syslog-ng -f

# Check syslog service
kubectl describe svc syslog-ng -n monitoring

# Restart syslog-ng
kubectl rollout restart deployment/syslog-ng -n monitoring

# Scale syslog-ng
kubectl scale deployment/syslog-ng -n monitoring --replicas=2

# View ConfigMap
kubectl get configmap syslog-ng-config -n monitoring -o yaml
```

## Resources

- [OPNsense Logging Documentation](https://docs.opnsense.org/manual/logging.html)
- [Loki LogQL Documentation](https://grafana.com/docs/loki/latest/logql/)
- [syslog-ng Documentation](https://www.syslog-ng.com/technical-documents/)
- [Grafana Explore](http://grafana.home/explore)

## Quick Start Checklist

- [ ] Deploy Terraform configuration
- [ ] Verify syslog-ng pod is running
- [ ] Confirm LoadBalancer has IP 192.168.0.36
- [ ] Configure OPNsense remote logging
- [ ] Test with sample log message
- [ ] Query logs in Grafana Explore
- [ ] Create firewall dashboard
- [ ] Set up alerts for critical events

---

**Need Help?**

Check logs:
```bash
kubectl logs -n monitoring -l app=syslog-ng --tail=100
```

Verify configuration:
```bash
terraform output opnsense_logging_info
```

