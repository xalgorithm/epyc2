# TrueNAS 25.04 Monitoring Setup Guide

Complete guide for monitoring TrueNAS SCALE 25.04 systems with Prometheus, Loki, and Grafana.

## Overview

This setup monitors two TrueNAS machines with:
- **Logs**: Sent to Loki via Promtail syslog endpoint
- **Metrics**: Scraped by Prometheus using TrueNAS built-in exporters
- **Dashboards**: Pre-configured Grafana dashboards for visualization

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  TrueNAS Machines                           │
│  ┌──────────────────────┐  ┌──────────────────────┐        │
│  │   TrueNAS 1          │  │   TrueNAS 2          │        │
│  │   192.168.0.2        │  │   192.168.0.11       │        │
│  │                      │  │                      │        │
│  │  • Node Exporter     │  │  • Node Exporter     │        │
│  │    (Port 9100)       │  │    (Port 9100)       │        │
│  │                      │  │                      │        │
│  │  • Syslog            │  │  • Syslog            │        │
│  │    → 192.168.0.36    │  │    → 192.168.0.36    │        │
│  │                      │  │                      │        │
│  └──────────────────────┘  └──────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                      ↓                    ↓
           ┌──────────────────────────────────────┐
           │     Kubernetes Monitoring Stack      │
           │                                      │
           │  ┌────────────┐  ┌────────────┐     │
           │  │ Prometheus │  │ Promtail   │     │
           │  │            │  │ (Syslog)   │     │
           │  │ Scrapes    │  │ Port 1514  │     │
           │  │ Port 9100  │  └─────┬──────┘     │
           │  └─────┬──────┘        │            │
           │        │               │            │
           │        ↓               ↓            │
           │  ┌────────────┐  ┌────────────┐     │
           │  │   Mimir    │  │    Loki    │     │
           │  └─────┬──────┘  └─────┬──────┘     │
           │        │               │            │
           │        └───────┬───────┘            │
           │                ↓                    │
           │          ┌────────────┐             │
           │          │  Grafana   │             │
           │          │            │             │
           │          └────────────┘             │
           └──────────────────────────────────────┘
```

---

## Part 1: Logs to Loki (Syslog Configuration)

### Step 1: Configure Syslog on TrueNAS

For each TrueNAS machine, configure syslog to send logs to Promtail:

#### Via TrueNAS Web UI:

1. **Login to TrueNAS Web UI**
   - Navigate to: `http://192.168.0.2` (or your TrueNAS IP)

2. **Navigate to System Settings**
   - Go to: **System Settings** → **Advanced**
   - Scroll to: **Syslog** section

3. **Configure Syslog Server**
   ```
   Syslog Server: 192.168.0.36
   Syslog Transport: TCP
   Syslog Level: Info
   Use FQDN for Logging: ☑ (checked)
   Syslog Port: 1514
   Include Audit Logs: ☑ (checked)
   ```

4. **Click Save**

#### Via CLI (Alternative Method):

SSH into each TrueNAS machine and run:

```bash
# Configure syslog
midclt call system.advanced.update '{
  "syslogserver": "192.168.0.36",
  "syslogserver_transport": "TCP",
  "sysloglevel": "INFO",
  "syslog_port": 1514
}'

# Restart syslog service
service syslog-ng restart

# Verify configuration
tail -f /var/log/syslog
```

### Step 2: Test Syslog Connectivity

Test that logs are reaching Loki:

```bash
# From your workstation, query Loki for TrueNAS logs
kubectl exec -n monitoring -it $(kubectl get pod -n monitoring -l app=loki -o name | head -1) -- \
  wget -qO- "http://localhost:3100/loki/api/v1/query?query=%7Bhost%3D~%22truenas.*%22%7D&limit=10"
```

Or via Grafana:
1. Go to: **http://grafana.home/explore**
2. Select: **Loki** datasource
3. Query: `{host=~"truenas.*"}`

---

## Part 2: Metrics to Prometheus (Node Exporter)

TrueNAS SCALE 25.04 has **node_exporter built-in** but disabled by default.

### Step 1: Enable Node Exporter on TrueNAS

#### Option A: Via TrueNAS CLI (Recommended)

SSH into each TrueNAS machine:

```bash
# Check if node_exporter is available
which node_exporter

# If available, create systemd service
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/node_exporter \
  --web.listen-address=:9100 \
  --collector.filesystem.mount-points-exclude="^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+)($|/)" \
  --collector.netclass.ignored-devices="^(veth.*|docker.*|br-.*|lo)$" \
  --collector.netdev.device-exclude="^(veth.*|docker.*|br-.*|lo)$"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# Verify it's running
systemctl status node_exporter
curl http://localhost:9100/metrics | head -20
```

#### Option B: Install via Docker (if not available)

```bash
# Run node_exporter as a container
docker run -d \
  --name=node_exporter \
  --net="host" \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  --restart=unless-stopped \
  quay.io/prometheus/node-exporter:latest \
  --path.rootfs=/host \
  --web.listen-address=:9100
```

#### Option C: Use TrueNAS App (if available in TrueNAS SCALE 25.04)

1. Go to: **Apps** in TrueNAS Web UI
2. Search for: **"Prometheus Node Exporter"** or **"Exportarr"**
3. Install and configure to listen on port 9100

### Step 2: Verify Node Exporter is Working

From your workstation:

```bash
# Test connectivity to node_exporter
curl http://192.168.0.2:9100/metrics | head -20
curl http://192.168.0.11:9100/metrics | head -20

# You should see metrics like:
# node_cpu_seconds_total
# node_memory_MemTotal_bytes
# node_disk_io_time_seconds_total
```

### Step 3: Configure Firewall (if needed)

If you can't reach port 9100, allow it through the firewall:

```bash
# On each TrueNAS machine
iptables -I INPUT -p tcp --dport 9100 -j ACCEPT

# Make it persistent (TrueNAS may reset on reboot)
# Add to /etc/rc.local or use TrueNAS Init/Shutdown Scripts
```

---

## Part 3: Update Prometheus Configuration

The Prometheus configuration has been updated to scrape both TrueNAS machines.

### Scrape Configuration

```yaml
# TrueNAS SCALE metrics scraping
- job_name: 'truenas'
  scrape_interval: 30s
  scrape_timeout: 10s
  static_configs:
    - targets:
        - '192.168.0.2:9100'    # TrueNAS 1
        - '192.168.0.11:9100'   # TrueNAS 2
      labels:
        environment: 'homelab'
        service: 'storage'
```

### Apply Changes

The configuration will be applied automatically via Terraform.

---

## Part 4: Grafana Dashboards

### Pre-Built Dashboard: Node Exporter Full

1. **Import Dashboard**
   - Go to: **http://grafana.home**
   - Click: **Dashboards** → **Import**
   - Enter ID: **1860** (Node Exporter Full)
   - Click: **Load**
   - Select: **Prometheus** as data source
   - Click: **Import**

2. **Filter by TrueNAS**
   - At the top, select: **job = truenas**
   - Select: **instance** for specific TrueNAS machine

### Custom TrueNAS Dashboard

A custom dashboard has been created with TrueNAS-specific metrics:

**Dashboard Panels:**
- CPU Usage
- Memory Usage
- Disk I/O
- Network Traffic
- ZFS Pool Status (if available)
- Temperature Sensors
- Filesystem Usage
- System Load

The dashboard JSON will be created in: `configs/grafana/truenas-dashboard.json`

---

## Part 5: Verification & Testing

### Verify Metrics are Being Collected

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Open in browser: http://localhost:9090/targets
# Look for: job="truenas"
# Both targets should show: UP
```

### Verify Logs are Being Collected

```bash
# Query Loki via kubectl
kubectl exec -n monitoring -it deployment/loki -- \
  wget -qO- 'http://localhost:3100/loki/api/v1/query?query={host=~"truenas.*"}&limit=10'

# Or via Grafana Explore
# URL: http://grafana.home/explore
# Query: {host=~"truenas.*"}
```

### Test Queries in Grafana

Open **Grafana** → **Explore** and try these queries:

#### Prometheus Queries:
```promql
# CPU usage per TrueNAS
100 - (avg by (instance) (irate(node_cpu_seconds_total{job="truenas",mode="idle"}[5m])) * 100)

# Memory usage
100 * (1 - (node_memory_MemAvailable_bytes{job="truenas"} / node_memory_MemTotal_bytes{job="truenas"}))

# Disk usage
100 - ((node_filesystem_avail_bytes{job="truenas",fstype=~"zfs|ext4"} * 100) / node_filesystem_size_bytes{job="truenas",fstype=~"zfs|ext4"})

# Network traffic
rate(node_network_receive_bytes_total{job="truenas",device!~"lo|veth.*"}[5m])
```

#### Loki Queries:
```logql
# All TrueNAS logs
{host=~"truenas.*"}

# ZFS-related logs
{host=~"truenas.*"} |~ "zfs|zpool"

# Error logs
{host=~"truenas.*"} |~ "(?i)error|fail|critical"

# Smart/disk logs
{host=~"truenas.*"} |~ "smart|disk|scsi"
```

---

## Part 6: Advanced Configuration

### ZFS Metrics (Optional)

For detailed ZFS metrics, you may want to install a dedicated ZFS exporter:

```bash
# On each TrueNAS machine
docker run -d \
  --name=zfs_exporter \
  --privileged \
  -p 9134:9134 \
  --restart=unless-stopped \
  --pid=host \
  -v /proc:/host/proc:ro \
  matusnovak/prometheus-zfs
```

Then add to Prometheus:

```yaml
- job_name: 'truenas-zfs'
  static_configs:
    - targets:
        - '192.168.0.2:9134'
        - '192.168.0.11:9134'
```

### SMART Metrics (Optional)

For disk SMART data:

```bash
# Install smartmontools if not present
apt-get install smartmontools

# Run SMART exporter
docker run -d \
  --name=smartctl_exporter \
  --privileged \
  -p 9633:9633 \
  --restart=unless-stopped \
  -v /dev:/dev:ro \
  prometheuscommunity/smartctl-exporter
```

### Custom Alerts

Create alert rules for TrueNAS in Prometheus:

```yaml
groups:
  - name: truenas_alerts
    interval: 30s
    rules:
      - alert: TrueNASHighCPU
        expr: 100 - (avg by (instance) (irate(node_cpu_seconds_total{job="truenas",mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is above 80% (current: {{ $value }}%)"

      - alert: TrueNASHighMemory
        expr: 100 * (1 - (node_memory_MemAvailable_bytes{job="truenas"} / node_memory_MemTotal_bytes{job="truenas"})) > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"

      - alert: TrueNASDiskSpaceLow
        expr: 100 - ((node_filesystem_avail_bytes{job="truenas",fstype="zfs"} * 100) / node_filesystem_size_bytes{job="truenas",fstype="zfs"}) > 85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"

      - alert: TrueNASDown
        expr: up{job="truenas"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "TrueNAS {{ $labels.instance }} is down"
```

---

## Part 7: Troubleshooting

### Metrics Not Appearing

1. **Check node_exporter is running on TrueNAS:**
   ```bash
   ssh root@192.168.0.2
   systemctl status node_exporter
   curl http://localhost:9100/metrics
   ```

2. **Check Prometheus can reach TrueNAS:**
   ```bash
   # From your workstation
   curl http://192.168.0.2:9100/metrics
   curl http://192.168.0.11:9100/metrics
   ```

3. **Check Prometheus targets:**
   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   # Open: http://localhost:9090/targets
   ```

4. **Check Prometheus logs:**
   ```bash
   kubectl logs -n monitoring deployment/prometheus --tail=50
   ```

### Logs Not Appearing

1. **Check syslog configuration on TrueNAS:**
   ```bash
   ssh root@192.168.0.2
   midclt call system.advanced.config | jq .syslogserver
   ```

2. **Check syslog service is running:**
   ```bash
   service syslog-ng status
   tail -f /var/log/syslog
   ```

3. **Test connectivity to Promtail:**
   ```bash
   echo "test message from truenas" | nc 192.168.0.36 1514
   ```

4. **Check Promtail logs:**
   ```bash
   kubectl logs -n monitoring daemonset/promtail --tail=50 | grep truenas
   ```

5. **Query Loki directly:**
   ```bash
   kubectl exec -n monitoring deployment/loki -- \
     wget -qO- 'http://localhost:3100/loki/api/v1/labels'
   ```

### Network/Firewall Issues

1. **Verify ports are open:**
   ```bash
   # Test from Kubernetes node
   nc -zv 192.168.0.2 9100
   nc -zv 192.168.0.36 1514
   ```

2. **Check iptables on TrueNAS:**
   ```bash
   iptables -L -n | grep 9100
   ```

3. **Temporarily disable firewall for testing:**
   ```bash
   # CAUTION: Only for testing!
   iptables -F
   ```

---

## Summary

### Configuration Checklist

- [ ] TrueNAS 1 (192.168.0.2)
  - [ ] Syslog configured → 192.168.0.36:1514
  - [ ] Node exporter running on port 9100
  - [ ] Firewall allows port 9100
  - [ ] Test: `curl http://192.168.0.2:9100/metrics`

- [ ] TrueNAS 2 (192.168.0.11)
  - [ ] Syslog configured → 192.168.0.36:1514
  - [ ] Node exporter running on port 9100
  - [ ] Firewall allows port 9100
  - [ ] Test: `curl http://192.168.0.11:9100/metrics`

- [ ] Prometheus
  - [ ] TrueNAS scrape config added
  - [ ] Configuration applied via Terraform
  - [ ] Targets showing UP in Prometheus

- [ ] Grafana
  - [ ] Node Exporter dashboard imported (ID: 1860)
  - [ ] Custom TrueNAS dashboard created
  - [ ] Metrics visible in dashboards

- [ ] Loki
  - [ ] TrueNAS logs appearing in Grafana Explore
  - [ ] Labels: `{host=~"truenas.*"}`

### Key URLs

- **Grafana**: http://grafana.home
- **Prometheus**: `kubectl port-forward -n monitoring svc/prometheus 9090:9090`
- **Loki Explore**: http://grafana.home/explore
- **TrueNAS 1 Metrics**: http://192.168.0.2:9100/metrics
- **TrueNAS 2 Metrics**: http://192.168.0.11:9100/metrics

### Key Ports

- **9100**: Node Exporter (metrics)
- **1514**: Promtail Syslog (logs)
- **9134**: ZFS Exporter (optional)
- **9633**: SMART Exporter (optional)

---

## Next Steps

1. **Run the setup** (see instructions in this document)
2. **Verify metrics and logs** are flowing
3. **Import Grafana dashboards**
4. **Set up alerts** for critical conditions
5. **Monitor ZFS health** via custom queries
6. **Document specific storage metrics** you want to track

For questions or issues, refer to the troubleshooting section or check:
- Prometheus logs: `kubectl logs -n monitoring deployment/prometheus`
- Loki logs: `kubectl logs -n monitoring deployment/loki`
- Promtail logs: `kubectl logs -n monitoring daemonset/promtail`
