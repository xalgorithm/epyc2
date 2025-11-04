# OPNsense Syslog Troubleshooting Guide

## Quick Status Check

Your syslog-ng receiver is **working correctly**:
- ✅ Pod is running
- ✅ LoadBalancer IP: `192.168.0.36`
- ✅ Receiving messages from within cluster
- ✅ Receiving messages from external sources

## OPNsense Configuration Steps

### 1. Configure Remote Logging

**Web Interface:** `System` → `Settings` → `Logging / targets`

Click **Add** and configure:

```
Enabled:      ☑ Yes
Transport:    UDP(4)
Applications: ☑ Firewall, ☑ System (select what you want)
Levels:       ☑ Informational and above
Hostname:     192.168.0.36
Port:         514
Certificate:  (empty for UDP)
Facility:     local0
Program:      (empty)
Description:  Kubernetes Loki
```

### 2. Test from OPNsense

SSH to OPNsense or use web shell:

```bash
# Test 1: Using logger
logger -p local0.info -t opnsense-test "Test message to kubernetes"

# Test 2: Using netcat
echo '<134>1 '$(date -u +%Y-%m-%dT%H:%M:%SZ)' opnsense test - - - Test message' | nc -u 192.168.0.36 514

# Test 3: Check connectivity
nc -zvu 192.168.0.36 514
```

### 3. Verify Receipt in Kubernetes

```bash
# Watch logs in real-time
kubectl logs -n monitoring -l app=syslog-ng -f

# Check last 20 messages
kubectl logs -n monitoring -l app=syslog-ng --tail=20

# Search for specific messages
kubectl logs -n monitoring -l app=syslog-ng | grep opnsense
```

## Troubleshooting Checklist

### Issue: No messages appearing

- [ ] **Step 1**: Verify syslog-ng is running
  ```bash
  kubectl get pods -n monitoring -l app=syslog-ng
  ```

- [ ] **Step 2**: Check LoadBalancer IP is assigned
  ```bash
  kubectl get svc syslog-ng -n monitoring
  ```
  Should show: `EXTERNAL-IP: 192.168.0.36`

- [ ] **Step 3**: Test from your workstation
  ```bash
  echo '<134>Test from workstation' | nc -u 192.168.0.36 514
  kubectl logs -n monitoring -l app=syslog-ng --tail=5
  ```

- [ ] **Step 4**: Check OPNsense configuration
  - Is remote logging enabled?
  - Is the correct IP configured (192.168.0.36)?
  - Are applications selected (Firewall, System, etc.)?

- [ ] **Step 5**: Check OPNsense firewall rules
  ```bash
  # From OPNsense shell
  pfctl -sr | grep 514
  ```

- [ ] **Step 6**: Verify OPNsense syslog-ng config
  ```bash
  # From OPNsense shell
  ls -la /usr/local/etc/syslog-ng.d/
  cat /usr/local/etc/syslog-ng.d/99-remote.conf
  ```

- [ ] **Step 7**: Restart OPNsense syslog service
  ```bash
  # From OPNsense shell or web interface: Services → Logging
  service syslog-ng restart
  ```

### Issue: Messages received but not in Loki

- [ ] **Check Loki is running**
  ```bash
  kubectl get pods -n monitoring -l app=loki
  ```

- [ ] **Test Loki from syslog-ng pod**
  ```bash
  POD=$(kubectl get pod -n monitoring -l app=syslog-ng -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n monitoring $POD -- wget -qO- http://loki.monitoring.svc.cluster.local:3100/ready
  ```

- [ ] **Query Loki directly**
  ```bash
  LOKI_POD=$(kubectl get pod -n monitoring -l app=loki -o name | head -1)
  kubectl exec -n monitoring $LOKI_POD -- \
    wget -qO- 'http://localhost:3100/loki/api/v1/query?query={application="opnsense"}' | jq
  ```

- [ ] **Check syslog-ng logs for HTTP errors**
  ```bash
  kubectl logs -n monitoring -l app=syslog-ng | grep -i "error\|failed"
  ```

## OPNsense Firewall Configuration

### Check Outbound Rules

1. Go to: `Firewall` → `Rules` → `LAN` (or your OPNsense interface)
2. Ensure there's a rule allowing outbound traffic
3. Default "Allow all" should work, but verify

### Check Floating Rules

1. Go to: `Firewall` → `Rules` → `Floating`
2. Ensure no rules block UDP/514 outbound

### Test Firewall

From OPNsense shell:
```bash
# Test UDP connectivity
nc -zvu 192.168.0.36 514

# Check routing
traceroute 192.168.0.36

# Test actual syslog send
echo '<134>Firewall test' | nc -u 192.168.0.36 514
```

## OPNsense Syslog Service

### Check Service Status

```bash
# Check if syslog-ng is running
service syslog-ng status

# View process
ps aux | grep syslog-ng

# Check configuration syntax
syslog-ng --syntax-only
```

### Restart Service

**Via Web Interface:**
- Go to: `System` → `Settings` → `Logging`
- Click **Apply**

**Via Shell:**
```bash
service syslog-ng restart
```

### View Configuration

```bash
# Main config
cat /usr/local/etc/syslog-ng.conf

# Remote targets
cat /usr/local/etc/syslog-ng.d/99-remote.conf

# Check if our target exists
grep -r "192.168.0.36" /usr/local/etc/syslog-ng.d/
```

## Monitoring in Grafana

Once logs are flowing:

### 1. Explore Logs

Go to Grafana: `http://grafana.home` → `Explore`

```logql
# All OPNsense logs
{application="opnsense"}

# Firewall logs only
{application="opnsense"} |~ "filterlog"

# Recent blocks
{application="opnsense"} |~ "block"

# Specific IP
{application="opnsense"} |~ "192.168.1.x"
```

### 2. Create Dashboard

Example panels:

**Log Rate:**
```logql
sum(rate({application="opnsense"}[1m]))
```

**Firewall Blocks:**
```logql
sum(rate({application="opnsense"} |~ "block"[5m]))
```

**Error Count:**
```logql
count_over_time({application="opnsense"} |~ "error|critical"[5m])
```

## Common Log Formats

### Firewall Log
```
filterlog: 5,,,1000000103,igb0,match,block,in,4,0x0,,64,12345,0,none,6,tcp,60,192.168.1.100,8.8.8.8,54321,443,0,S,1234567890,,64240,,mss
```

### System Log
```
opnsense syslogd[12345]: kernel boot file is /boot/kernel/kernel
```

### DHCP Log
```
dhcpd: DHCPACK on 192.168.1.50 to aa:bb:cc:dd:ee:ff via igb1
```

## Performance Tuning

### If High Log Volume

Adjust syslog-ng resources in Terraform:

```hcl
resources {
  requests = {
    cpu    = "200m"
    memory = "256Mi"
  }
  limits = {
    cpu    = "1000m"
    memory = "1Gi"
  }
}
```

### Filter Logs in OPNsense

Only send important logs:
- Levels: Warning and above (instead of Informational)
- Applications: Only Firewall (instead of All)

## Useful Commands

```bash
# Real-time log monitoring
kubectl logs -n monitoring -l app=syslog-ng -f

# Count messages received
kubectl logs -n monitoring -l app=syslog-ng | wc -l

# Search for errors
kubectl logs -n monitoring -l app=syslog-ng | grep -i error

# Check service endpoints
kubectl get endpoints syslog-ng -n monitoring

# Describe service (for troubleshooting)
kubectl describe svc syslog-ng -n monitoring

# Get pod IP
kubectl get pod -n monitoring -l app=syslog-ng -o wide

# Test from another pod
kubectl run test --image=busybox -n monitoring --rm -it -- \
  sh -c "echo '<134>Test' | nc -u syslog-ng.monitoring.svc.cluster.local 514"
```

## Debug Mode

Enable verbose logging in syslog-ng:

Edit `opnsense-logging.tf` and add to options:
```
log_level(debug);
```

Then apply:
```bash
terraform apply -target=kubernetes_config_map.syslog_ng_config
kubectl rollout restart deployment/syslog-ng -n monitoring
```

## Expected Behavior

**Normal Operation:**
1. OPNsense generates logs
2. OPNsense syslog-ng forwards to 192.168.0.36:514
3. Kubernetes MetalLB routes to syslog-ng pod
4. syslog-ng receives and logs to stdout
5. syslog-ng forwards to Loki
6. Logs visible in Grafana

**Log Flow:**
```
OPNsense → 192.168.0.36:514 → MetalLB → syslog-ng pod → stdout & Loki → Grafana
```

## Getting Help

If still not working:

1. Run diagnostic script:
   ```bash
   ./scripts/troubleshooting/diagnose-syslog.sh
   ```

2. Collect information:
   ```bash
   # Kubernetes side
   kubectl get pods,svc -n monitoring -l app=syslog-ng
   kubectl logs -n monitoring -l app=syslog-ng --tail=50
   kubectl describe svc syslog-ng -n monitoring
   
   # From OPNsense shell
   service syslog-ng status
   cat /usr/local/etc/syslog-ng.d/99-remote.conf
   netstat -an | grep 514
   ```

3. Share the output for further assistance

## References

- [OPNsense Logging Documentation](https://docs.opnsense.org/manual/logging.html)
- [Syslog-ng Documentation](https://www.syslog-ng.com/technical-documents/)
- [Grafana Loki Documentation](https://grafana.com/docs/loki/)
- See also: `docs/OPNSENSE_LOGGING.md`

