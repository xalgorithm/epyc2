# Rebellion Cluster Monitoring Architecture

This document describes the monitoring architecture for the Rebellion Kubernetes cluster and its integration with the main cluster's observability stack.

## Overview

The Rebellion cluster implements a distributed monitoring architecture with cross-cluster federation, allowing centralized visibility while maintaining cluster autonomy.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│             Main Cluster (Bumblebee)                │
│                                                     │
│  ┌──────────┐    ┌────────┐    ┌──────────┐      │
│  │ Grafana  │◄───│ Mimir  │◄───│Prometheus│      │
│  │ :3000    │    │ :9009  │    │  :9090   │      │
│  └──────────┘    └────────┘    └──────────┘      │
│        │              │               ▲            │
└────────┼──────────────┼───────────────┼───────────┘
         │              │               │
         │(dashboards)  │(remote_write) │(scrape)
         │              │               │
┌────────▼──────────────▼───────────────┼───────────┐
│           Rebellion Cluster           │           │
│                                       │           │
│  ┌──────────────┐    ┌───────────────▼──┐       │
│  │   Promtail   │    │   Prometheus     │       │
│  │  DaemonSet   │    │   (federation)   │       │
│  └──────┬───────┘    └──────────────────┘       │
│         │(push logs)                             │
│         │                                        │
│  ┌──────▼───────┐   ┌──────────────┐           │
│  │ Loki (Main)  │   │ node-exporter │           │
│  │              │   │  DaemonSet    │           │
│  └──────────────┘   └───────────────┘           │
│                                                  │
│  Luke (40), Leia (41), Han (42)                 │
└──────────────────────────────────────────────────┘
```

## Components

### 1. Node Exporters

**Deployment:** DaemonSet on all rebellion nodes  
**Port:** 9100  
**Purpose:** Exposes hardware and OS metrics

**Metrics Collected:**
- CPU usage, load average
- Memory usage and swap
- Disk space and I/O
- Network traffic and errors
- System uptime

**Configuration:**
```yaml
# Located at: flux/rebellion/monitoring/node-exporter.yaml
# Deployed as DaemonSet with hostNetwork: true
```

**Verification:**
```bash
export KUBECONFIG=~/.kube/configs/rebellion-config

# Check node-exporter pods
kubectl get pods -n monitoring -l app=node-exporter

# Test metrics endpoint (from a node)
ssh xalg@192.168.0.40 "curl -s localhost:9100/metrics | head"
```

### 2. Prometheus (Rebellion)

**Deployment:** StatefulSet in rebellion cluster  
**Port:** 9090  
**Purpose:** Local metrics collection and federation

**Scrape Targets:**
- Node exporters on all three nodes
- Kubernetes API server
- Kubelet/cAdvisor metrics
- Istio control plane and gateways
- Application pods with annotations

**Remote Write:**
- Pushes all metrics to main cluster's Mimir
- Retention: 7 days local, long-term in Mimir

**Configuration:**
```yaml
# Located at: flux/rebellion/monitoring/prometheus.yaml
# Remote write to: http://192.168.0.35:9009/api/v1/push
```

**Access:**
```bash
# Port-forward to access Prometheus UI
export KUBECONFIG=~/.kube/configs/rebellion-config
kubectl port-forward -n monitoring svc/prometheus-rebellion 9090:9090

# Open http://localhost:9090
```

### 3. Promtail

**Deployment:** DaemonSet on all rebellion nodes  
**Purpose:** Ships logs to main cluster's Loki

**Log Sources:**
- Container logs from /var/log/pods
- Systemd journal
- Node system logs

**Configuration:**
```yaml
# Located at: flux/rebellion/monitoring/promtail.yaml
# Ships to: http://192.168.0.35:3100/loki/api/v1/push
```

**Verification:**
```bash
# Check Promtail pods
kubectl get pods -n monitoring -l app=promtail

# Check Promtail logs
kubectl logs -n monitoring -l app=promtail --tail=50
```

### 4. Grafana Dashboards

Two dashboards are added to the main cluster's Grafana:

#### Rebellion Cluster Overview
**File:** `configs/grafana/rebellion-cluster-dashboard.json`

**Panels:**
- Cluster nodes status
- CPU usage by node
- Memory usage by node
- Disk usage by node
- Network traffic
- Pod count by namespace
- Pod status distribution

**Access:** http://grafana.home → Dashboards → "Rebellion Cluster Overview"

#### Rebellion Istio Gateway Metrics
**File:** `configs/grafana/rebellion-istio-dashboard.json`

**Panels:**
- Gateway request rate
- Gateway success rate
- Response time percentiles (P50, P90, P99)
- Errors by status code
- Gateway bandwidth
- Active connections

**Access:** http://grafana.home → Dashboards → "Rebellion Istio Gateway Metrics"

## Cross-Cluster Federation

### Metrics Flow

1. **Node Exporters** expose metrics on each node
2. **Prometheus (rebellion)** scrapes all local targets
3. **Remote Write** pushes metrics to main cluster's **Mimir**
4. **Prometheus (main)** can also directly scrape rebellion nodes
5. **Grafana (main)** queries from Mimir for all metrics

### Logs Flow

1. **Promtail** reads container logs on each node
2. **Push** sends logs to main cluster's **Loki**
3. **Grafana (main)** queries Loki with `{cluster="rebellion"}` filter

### Labels

All metrics and logs from rebellion cluster include:
- `cluster="rebellion"`
- `environment="production"`
- `node_name=<luke|leia|han>`

## Querying

### PromQL Queries

**Rebellion node CPU usage:**
```promql
100 - (avg by (instance) (irate(node_cpu_seconds_total{cluster="rebellion",mode="idle"}[5m])) * 100)
```

**Rebellion pod count:**
```promql
count by (namespace) (kube_pod_info{cluster="rebellion"})
```

**Istio request rate:**
```promql
sum(rate(istio_requests_total{cluster="rebellion"}[5m])) by (destination_service_name)
```

### LogQL Queries

**All rebellion logs:**
```logql
{cluster="rebellion"}
```

**Rebellion errors:**
```logql
{cluster="rebellion"} |= "error" or "Error" or "ERROR"
```

**Specific namespace logs:**
```logql
{cluster="rebellion",namespace="istio-system"}
```

## Alerting

### Recommended Alerts

Create these alerts in Prometheus or Alertmanager:

**Node Down:**
```yaml
- alert: RebellionNodeDown
  expr: up{cluster="rebellion",job="rebellion-nodes"} == 0
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Rebellion node {{ $labels.instance }} is down"
```

**High CPU:**
```yaml
- alert: RebellionHighCPU
  expr: |
    100 - (avg by (instance) (irate(node_cpu_seconds_total{cluster="rebellion",mode="idle"}[5m])) * 100) > 90
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "High CPU on {{ $labels.instance }}"
```

**High Memory:**
```yaml
- alert: RebellionHighMemory
  expr: |
    100 - ((node_memory_MemAvailable_bytes{cluster="rebellion"} / node_memory_MemTotal_bytes{cluster="rebellion"}) * 100) > 90
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "High memory on {{ $labels.instance }}"
```

**Istio Gateway Errors:**
```yaml
- alert: RebellionGatewayErrors
  expr: |
    sum(rate(istio_requests_total{cluster="rebellion",response_code=~"5.."}[5m])) > 10
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High error rate on Istio Gateway"
```

## Maintenance

### Prometheus Retention

Local Prometheus retention is 7 days. To adjust:

```yaml
# Edit flux/rebellion/monitoring/prometheus.yaml
args:
  - '--storage.tsdb.retention.time=14d'  # Change from 7d to 14d
```

### Scaling

**Prometheus:**
```bash
# Increase resources
kubectl -n monitoring patch deployment prometheus-rebellion -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"prometheus","resources":{"limits":{"memory":"8Gi"}}}]}}}}'
```

**Node Exporter:**
Automatically scales with nodes (DaemonSet)

**Promtail:**
Automatically scales with nodes (DaemonSet)

### Backup

Prometheus data is stored in ephemeral storage. Long-term data is in Mimir on the main cluster.

To backup Prometheus configuration:
```bash
kubectl get configmap -n monitoring prometheus-rebellion-config -o yaml > prometheus-backup.yaml
```

## Troubleshooting

### No Metrics from Rebellion Nodes

1. **Check node-exporter:**
```bash
kubectl get pods -n monitoring -l app=node-exporter
kubectl logs -n monitoring -l app=node-exporter
```

2. **Test metrics endpoint:**
```bash
ssh xalg@192.168.0.40 "curl localhost:9100/metrics"
```

3. **Check Prometheus scraping:**
```bash
kubectl port-forward -n monitoring svc/prometheus-rebellion 9090:9090
# Visit http://localhost:9090/targets
```

### No Logs in Loki

1. **Check Promtail pods:**
```bash
kubectl get pods -n monitoring -l app=promtail
kubectl logs -n monitoring -l app=promtail
```

2. **Check Loki endpoint:**
```bash
# From rebellion cluster
kubectl run test --rm -it --image=curlimages/curl -- \
  curl -v http://192.168.0.35:3100/ready
```

3. **Check network connectivity:**
```bash
# Ensure main cluster ingress is accessible
ping 192.168.0.35
```

### Dashboards Not Showing Data

1. **Check data source in Grafana:**
   - Open Grafana → Configuration → Data Sources
   - Verify Mimir/Prometheus connection

2. **Check time range:**
   - Ensure dashboard time range includes recent data

3. **Check labels:**
   - Verify `cluster="rebellion"` label exists in metrics

### High Cardinality

If metrics storage grows too large:

1. **Add metric relabeling:**
```yaml
# In prometheus.yaml, add to scrape configs:
metric_relabel_configs:
  - source_labels: [__name__]
    regex: 'unwanted_metric_.*'
    action: drop
```

2. **Reduce scrape frequency:**
```yaml
scrape_interval: 30s  # Increase from 15s
```

## Best Practices

1. **Use consistent labels:** Always include `cluster="rebellion"`
2. **Monitor the monitors:** Set up alerts for Prometheus/Promtail health
3. **Regular reviews:** Review dashboard queries and optimize
4. **Capacity planning:** Monitor growth trends for storage and resources
5. **Documentation:** Document custom metrics and dashboards

## Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Istio Observability](https://istio.io/latest/docs/tasks/observability/)

