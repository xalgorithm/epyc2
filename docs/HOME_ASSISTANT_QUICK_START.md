# Home Assistant Integration - Quick Start

## 5-Minute Setup

### 1. Enable Prometheus in Home Assistant

Edit `configuration.yaml`:
```yaml
prometheus:
  namespace: homeassistant
```

Restart Home Assistant.

### 2. Verify Endpoint

```bash
curl http://192.168.0.31:8123/api/prometheus | head -n 10
```

You should see Prometheus-formatted metrics.

### 3. Configure Terraform

Edit `terraform.tfvars`:
```hcl
home_assistant_enabled = true
home_assistant_ip      = "192.168.0.31"
```

### 4. Apply Configuration

```bash
terraform apply
kubectl rollout restart deployment/prometheus -n monitoring
```

### 5. Access Dashboard

```bash
open http://grafana.home/d/home-assistant-overview
```

## Verification

```bash
# Check Prometheus target
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open: http://localhost:9090/targets
# Find: home-assistant (should be UP)

# Query metrics in Prometheus
# Open: http://localhost:9090/graph
# Query: up{job="home-assistant"}
```

## Common Metrics

```promql
# Check Home Assistant is up
up{job="home-assistant"}

# Temperature sensors
homeassistant_sensor_temperature_celsius

# Power consumption
homeassistant_sensor_power_w

# Switch states
homeassistant_switch_state

# Battery levels
homeassistant_sensor_battery_percent
```

## Troubleshooting

| Issue | Quick Fix |
|-------|-----------|
| Target DOWN | Check Home Assistant is running and accessible |
| No metrics | Verify `prometheus:` in configuration.yaml |
| 401 Error | Add authentication to Prometheus config |
| No data in Grafana | Check time range, verify metrics exist in Prometheus |

## Need Help?

See full documentation: [docs/HOME_ASSISTANT_INTEGRATION.md](HOME_ASSISTANT_INTEGRATION.md)

