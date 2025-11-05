# Home Assistant Integration Guide

This guide explains how to integrate Home Assistant with your Kubernetes observability stack to collect metrics and logs from your smart home setup.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Configuration Steps](#configuration-steps)
4. [Terraform Variables](#terraform-variables)
5. [Home Assistant Configuration](#home-assistant-configuration)
6. [Verification](#verification)
7. [Grafana Dashboard](#grafana-dashboard)
8. [Troubleshooting](#troubleshooting)

## Overview

The Home Assistant integration provides:

- **Prometheus Metrics**: Collects entity states, sensors, switches, and automation data
- **Grafana Dashboard**: Comprehensive visualization of your smart home
- **Real-time Monitoring**: Track temperature, humidity, power consumption, and more
- **Automation Insights**: Monitor automation triggers and execution

### Architecture

```
Home Assistant (192.168.0.31:8123)
    │
    └──> /api/prometheus (metrics endpoint)
         │
         └──> Prometheus (scrapes every 30s)
              │
              └──> Mimir (long-term storage)
                   │
                   └──> Grafana (visualization)
```

## Prerequisites

Before configuring the integration, ensure:

1. **Home Assistant** is running and accessible at `192.168.0.31:8123`
2. **Prometheus integration** is enabled in Home Assistant
3. **Network connectivity** between Kubernetes cluster and Home Assistant
4. **Long-Lived Access Token** generated (for API access, if needed)

## Configuration Steps

### Step 1: Enable Prometheus in Home Assistant

1. Edit your Home Assistant `configuration.yaml`:

```yaml
# configuration.yaml
prometheus:
  namespace: homeassistant
```

2. Optionally, filter specific entities:

```yaml
prometheus:
  namespace: homeassistant
  filter:
    include_domains:
      - sensor
      - switch
      - light
      - binary_sensor
      - climate
      - automation
    include_entities:
      - sensor.living_room_temperature
      - sensor.power_consumption
```

3. Restart Home Assistant to apply changes

4. Verify Prometheus endpoint is accessible:
   ```bash
   curl -s http://192.168.0.31:8123/api/prometheus | head -n 20
   ```

   You should see metrics in Prometheus format:
   ```
   # TYPE homeassistant_sensor_state gauge
   homeassistant_sensor_temperature_celsius{domain="sensor",entity="sensor.living_room",friendly_name="Living Room"} 22.5
   ```

### Step 2: Configure Terraform Variables

1. Edit `terraform.tfvars`:

```hcl
# Home Assistant Integration
home_assistant_enabled   = true
home_assistant_ip        = "192.168.0.31"
home_assistant_port      = 8123
home_assistant_api_token = "your-long-lived-access-token-here"
```

2. Generate a Long-Lived Access Token in Home Assistant:
   - Go to: **Profile** → **Security** → **Long-Lived Access Tokens**
   - Click **"Create Token"**
   - Name: `Kubernetes Monitoring`
   - Copy the token and add to `terraform.tfvars`

**Note**: The API token is currently optional. The Prometheus endpoint typically doesn't require authentication for local network access. If your Home Assistant requires authentication for the `/api/prometheus` endpoint, see [Advanced Configuration](#advanced-configuration) below.

### Step 3: Apply Terraform Configuration

```bash
# Apply the changes
terraform apply

# Verify Prometheus configuration
kubectl get configmap prometheus-config -n monitoring -o yaml | grep -A 10 "home-assistant"
```

### Step 4: Restart Prometheus

```bash
# Restart Prometheus to pick up new configuration
kubectl rollout restart deployment/prometheus -n monitoring

# Wait for Prometheus to be ready
kubectl rollout status deployment/prometheus -n monitoring
```

## Terraform Variables

The following variables control Home Assistant integration:

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `home_assistant_enabled` | bool | `true` | Enable/disable Home Assistant monitoring |
| `home_assistant_ip` | string | `192.168.0.31` | IP address of Home Assistant |
| `home_assistant_port` | number | `8123` | Home Assistant web port |
| `home_assistant_api_token` | string (sensitive) | `""` | Long-Lived Access Token for API |

## Verification

### Check Prometheus Scraping

1. **Port-forward Prometheus**:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   ```

2. **Open Prometheus UI**: http://localhost:9090

3. **Check targets**:
   - Navigate to: **Status** → **Targets**
   - Find: `home-assistant` job
   - Status should be: **UP** (green)

4. **Query Home Assistant metrics**:
   ```promql
   # Check if metrics are being scraped
   up{job="home-assistant"}
   
   # View all Home Assistant metrics
   {job="home-assistant"}
   
   # Check specific sensors
   homeassistant_sensor_temperature_celsius
   homeassistant_sensor_humidity_percent
   homeassistant_sensor_power_w
   ```

### Common Metrics

Here are some common Home Assistant metrics available:

```promql
# Entity availability
homeassistant_entity_available

# Sensor states
homeassistant_sensor_state
homeassistant_sensor_temperature_celsius
homeassistant_sensor_humidity_percent
homeassistant_sensor_battery_percent
homeassistant_sensor_power_w
homeassistant_sensor_energy_kwh
homeassistant_sensor_illuminance_lx

# Switch states
homeassistant_switch_state

# Automation triggers
homeassistant_automation_triggered_count

# Light states
homeassistant_light_state
```

## Grafana Dashboard

The Home Assistant dashboard provides comprehensive visualization of your smart home.

### Accessing the Dashboard

```bash
# Direct link
open http://grafana.home/d/home-assistant-overview
```

Or navigate in Grafana:
- **Dashboards** → **Browse** → **Home Assistant Overview**

### Dashboard Features

The dashboard includes:

1. **Status Overview**
   - Home Assistant connection status
   - Total entities count
   - Total sensors count
   - Total switches count

2. **Environmental Monitoring**
   - Temperature sensors (all rooms)
   - Humidity sensors
   - Light/Illuminance sensors

3. **Energy Monitoring**
   - Real-time power consumption
   - Energy usage over time (kWh)
   - Per-device power tracking

4. **Device Status**
   - Switch states table (On/Off)
   - Battery levels for wireless devices
   - Entity availability

5. **Automation Insights**
   - Automation trigger counts
   - Most active automations

### Customizing the Dashboard

The dashboard will automatically display all metrics from Home Assistant. To customize:

1. **Edit in Grafana**:
   - Open dashboard
   - Click **Dashboard settings** (gear icon)
   - **Save As** to create your own copy
   - Edit panels as needed

2. **Add new panels**:
   - Click **Add panel**
   - Choose visualization type
   - Use PromQL queries like: `homeassistant_sensor_state{friendly_name="Your Device"}`

## Advanced Configuration

### Enabling API Token Authentication

If your Home Assistant requires authentication for the Prometheus endpoint:

1. Edit `configs/prometheus/prometheus.yml`:

```yaml
  - job_name: 'home-assistant'
    scrape_interval: 30s
    scrape_timeout: 10s
    metrics_path: '/api/prometheus'
    scheme: http
    static_configs:
      - targets: ['192.168.0.31:8123']
        labels:
          instance: 'home-assistant'
          environment: 'homelab'
    # Uncomment and configure authentication
    authorization:
      type: Bearer
      credentials: YOUR_TOKEN_HERE  # Replace with actual token
```

2. **Better approach - Use Kubernetes Secret**:

Create a secret for the token:
```bash
kubectl create secret generic home-assistant-token \
  --from-literal=token="YOUR_LONG_LIVED_TOKEN" \
  -n monitoring
```

Then modify the Prometheus deployment to use the secret as an environment variable.

### Filtering Metrics

If you have many entities and want to reduce metric cardinality:

```yaml
# In Home Assistant configuration.yaml
prometheus:
  namespace: homeassistant
  filter:
    include_domains:
      - sensor
      - switch
    exclude_entities:
      - sensor.time
      - sensor.date
  component_config_glob:
    sensor.*_timestamp:
      override_metric: exclude
```

### Increasing Scrape Interval

For systems with many entities, you might want to reduce scrape frequency:

```yaml
  - job_name: 'home-assistant'
    scrape_interval: 60s  # Changed from 30s
    scrape_timeout: 15s   # Changed from 10s
```

## Troubleshooting

### Prometheus Target is Down

**Symptom**: Home Assistant target shows as DOWN in Prometheus

**Solutions**:

1. **Check network connectivity**:
   ```bash
   # From a Prometheus pod
   kubectl exec -n monitoring $(kubectl get pod -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}') -- wget -qO- http://192.168.0.31:8123/api/prometheus | head
   ```

2. **Verify Home Assistant Prometheus integration**:
   - Check `configuration.yaml` has `prometheus:` section
   - Restart Home Assistant
   - Check Home Assistant logs: **Settings** → **System** → **Logs**

3. **Check firewall rules**:
   ```bash
   # Test from your local machine
   curl -s http://192.168.0.31:8123/api/prometheus | head -n 20
   ```

### No Metrics Displayed

**Symptom**: Target is UP but no metrics in Prometheus

**Solutions**:

1. **Check metric names**:
   ```bash
   # Query Prometheus directly
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   # Browse to: http://localhost:9090/graph
   # Try: {job="home-assistant"}
   ```

2. **Verify Home Assistant entities**:
   - Ensure you have entities in Home Assistant
   - Check entity states are numeric for sensor data

3. **Check Prometheus logs**:
   ```bash
   kubectl logs -n monitoring -l app=prometheus --tail=100 | grep home-assistant
   ```

### Authentication Errors

**Symptom**: `401 Unauthorized` errors in Prometheus logs

**Solution**:
- Add `authorization` section to Prometheus config (see [Advanced Configuration](#advanced-configuration))
- Or disable authentication requirement in Home Assistant for Prometheus endpoint

### Dashboard Shows "No Data"

**Solutions**:

1. **Check time range**: Ensure dashboard time range covers when data exists

2. **Verify metric names**: Home Assistant metric names depend on your entity configuration
   ```promql
   # Find all available metrics
   {job="home-assistant"}
   ```

3. **Check query syntax**: Edit panel and verify PromQL query returns data

### High Cardinality Warning

**Symptom**: Prometheus performance degraded, high memory usage

**Cause**: Too many unique metric labels (entity_id, friendly_name, etc.)

**Solutions**:

1. **Filter entities** in Home Assistant `prometheus:` configuration
2. **Increase Prometheus resources**:
   ```bash
   # Edit monitoring.tf - increase memory/CPU limits
   ```
3. **Use relabel configs** to drop unnecessary labels

## Metrics Reference

### Common Queries

```promql
# Current temperature (average)
avg(homeassistant_sensor_temperature_celsius)

# Total power consumption
sum(homeassistant_sensor_power_w)

# Battery-powered devices below 20%
homeassistant_sensor_battery_percent < 20

# Switches that are ON
homeassistant_switch_state == 1

# Most triggered automations (last 24h)
topk(5, increase(homeassistant_automation_triggered_count[24h]))
```

### Alerting Examples

Create Prometheus alerts for Home Assistant:

```yaml
# prometheus-rules.yml
groups:
  - name: home_assistant
    interval: 30s
    rules:
      - alert: HomeAssistantDown
        expr: up{job="home-assistant"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Home Assistant is down"
          description: "Home Assistant has been unreachable for 5 minutes"

      - alert: LowBattery
        expr: homeassistant_sensor_battery_percent < 20
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Device {{ $labels.friendly_name }} battery low"
          description: "Battery level is {{ $value }}%"

      - alert: HighTemperature
        expr: homeassistant_sensor_temperature_celsius > 30
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "High temperature in {{ $labels.friendly_name }}"
          description: "Temperature is {{ $value }}°C"
```

## Additional Resources

- [Home Assistant Prometheus Integration](https://www.home-assistant.io/integrations/prometheus/)
- [Prometheus Query Language (PromQL)](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/best-practices/)

## Support

If you encounter issues:

1. Check Home Assistant logs: **Settings** → **System** → **Logs**
2. Check Prometheus logs: `kubectl logs -n monitoring -l app=prometheus`
3. Verify network connectivity between cluster and Home Assistant
4. Ensure Prometheus integration is enabled in Home Assistant

For more help, see the main project documentation or create an issue.

