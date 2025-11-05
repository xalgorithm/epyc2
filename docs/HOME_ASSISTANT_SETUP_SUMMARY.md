# Home Assistant Integration - Setup Summary

## ✅ What Was Configured

### 1. Terraform Variables Added
**File**: `variables.tf`

Added 4 new variables for Home Assistant integration:
- `home_assistant_enabled` - Enable/disable the integration
- `home_assistant_ip` - IP address (default: 192.168.0.31)
- `home_assistant_port` - Web port (default: 8123)  
- `home_assistant_api_token` - API token for authentication (sensitive)

### 2. Prometheus Configuration Updated
**File**: `configs/prometheus/prometheus.yml`

Added new scrape job:
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
```

### 3. Grafana Dashboard Created
**File**: `configs/grafana/home-assistant-dashboard.json`

Comprehensive dashboard with 12 panels:
- ✅ Home Assistant status
- 📊 Total entities, sensors, switches count
- 🌡️ Temperature sensors (all rooms)
- 💧 Humidity sensors
- ⚡ Power consumption tracking
- 🔋 Energy usage (kWh)
- 🔌 Switch states table
- 🔋 Battery levels for wireless devices
- 💡 Light/Illuminance sensors
- 🤖 Automation trigger counts

### 4. Documentation Created

- **docs/HOME_ASSISTANT_INTEGRATION.md** - Complete integration guide (7000+ words)
- **docs/HOME_ASSISTANT_QUICK_START.md** - Quick 5-minute setup guide
- **terraform.tfvars.example** - Updated with Home Assistant variables

### 5. Monitoring Configuration Applied

- ✅ Prometheus ConfigMap updated
- ✅ Grafana Dashboards ConfigMap updated
- ✅ Prometheus deployment restarted
- ✅ Grafana deployment restarted

## 📋 Next Steps - Complete These in Home Assistant

### Step 1: Enable Prometheus Integration

1. **Edit your Home Assistant `configuration.yaml`:**

```yaml
# Add this to configuration.yaml
prometheus:
  namespace: homeassistant
```

2. **Restart Home Assistant:**
   - Go to: **Settings** → **System** → **Restart**

### Step 2: Verify Metrics Endpoint

Test that the Prometheus endpoint is working:

```bash
curl -s http://192.168.0.31:8123/api/prometheus | head -n 20
```

You should see output like:
```
# TYPE homeassistant_sensor_state gauge
homeassistant_sensor_temperature_celsius{domain="sensor",entity="sensor.living_room",friendly_name="Living Room"} 22.5
```

### Step 3: Check Prometheus Target

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Open in browser: http://localhost:9090/targets
# Look for: home-assistant job (should be UP)
```

### Step 4: Access Your Dashboard

```bash
# Direct link to Home Assistant dashboard
open http://grafana.home/d/home-assistant-overview
```

Or navigate in Grafana:
- **Dashboards** → **Browse** → **Home Assistant Overview**

## 🔍 Verification Commands

```bash
# 1. Check Prometheus configuration
kubectl get configmap prometheus-config -n monitoring -o yaml | grep -A 10 "home-assistant"

# 2. Check Prometheus target status
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Browse to: http://localhost:9090/targets

# 3. Query Home Assistant metrics
# In Prometheus UI (http://localhost:9090/graph):
up{job="home-assistant"}
homeassistant_sensor_temperature_celsius
homeassistant_sensor_power_w

# 4. Check Grafana dashboard exists
kubectl get configmap grafana-dashboards -n monitoring -o json | jq '.data | keys'
```

## 📊 Available Metrics

Once Home Assistant is configured, you'll see metrics like:

```promql
# System
up{job="home-assistant"}
homeassistant_entity_available

# Sensors
homeassistant_sensor_temperature_celsius
homeassistant_sensor_humidity_percent
homeassistant_sensor_battery_percent
homeassistant_sensor_power_w
homeassistant_sensor_energy_kwh
homeassistant_sensor_illuminance_lx

# Devices
homeassistant_switch_state
homeassistant_light_state

# Automations
homeassistant_automation_triggered_count
```

## 🔧 Optional: Add API Token (If Needed)

Most Home Assistant setups don't require authentication for the `/api/prometheus` endpoint on the local network. However, if yours does:

### Generate Token in Home Assistant

1. Go to: **Profile** → **Security** → **Long-Lived Access Tokens**
2. Click **"Create Token"**
3. Name: `Kubernetes Monitoring`
4. Copy the token

### Update terraform.tfvars

```hcl
home_assistant_api_token = "eyJ0eXAiOiJKV1QiLCJhbGc..."  # Your token here
```

### Uncomment Auth in Prometheus Config

Edit `configs/prometheus/prometheus.yml`:

```yaml
  - job_name: 'home-assistant'
    # ... other settings ...
    authorization:  # Uncomment these lines
      type: Bearer
      credentials: YOUR_TOKEN_HERE  # Replace with actual token
```

Then reapply:
```bash
terraform apply -target=kubernetes_config_map.prometheus_config
kubectl rollout restart deployment/prometheus -n monitoring
```

## 🎯 Dashboard Features

The Home Assistant dashboard will show:

1. **Status Overview (Top Row)**
   - Connection status (UP/DOWN)
   - Total entities count
   - Total sensors count
   - Total switches count

2. **Environmental Monitoring**
   - Real-time temperature graphs for all sensors
   - Humidity levels across rooms
   - Light levels (illuminance)

3. **Energy Management**
   - Power consumption in Watts (real-time)
   - Energy usage in kWh (cumulative)
   - Per-device power tracking

4. **Device Management**
   - Switch states table (On/Off)
   - Battery levels with thresholds (warns below 20%)
   - Entity availability

5. **Automation Insights**
   - Automation trigger counts
   - Most active automations
   - Automation execution trends

## 🚨 Troubleshooting

### Target Shows as DOWN

**Check connectivity:**
```bash
# From Prometheus pod
PROM_POD=$(kubectl get pod -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n monitoring $PROM_POD -- wget -qO- http://192.168.0.31:8123/api/prometheus | head
```

**Verify Home Assistant:**
- Ensure `prometheus:` is in configuration.yaml
- Restart Home Assistant
- Check logs: **Settings** → **System** → **Logs**

### No Metrics Showing

**Verify metrics exist:**
```bash
# Query Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Browse: http://localhost:9090/graph
# Query: {job="home-assistant"}
```

**Check entity states:**
- Ensure you have entities in Home Assistant
- Verify entity states are numeric (for sensors)

### Dashboard Shows "No Data"

1. **Check time range**: Set to "Last 6 hours"
2. **Verify metrics**: Run queries in Prometheus directly
3. **Check labels**: Metric names depend on your Home Assistant entities

## 📚 Documentation

For complete details, see:
- **Full Guide**: [docs/HOME_ASSISTANT_INTEGRATION.md](docs/HOME_ASSISTANT_INTEGRATION.md)
- **Quick Start**: [docs/HOME_ASSISTANT_QUICK_START.md](docs/HOME_ASSISTANT_QUICK_START.md)

## 🎉 What's Monitoring Now

With this integration complete, your monitoring stack now includes:

- ✅ **Kubernetes** - Cluster, pods, nodes, resources
- ✅ **Proxmox** - Virtualization platform
- ✅ **OPNsense** - Firewall logs and metrics
- ✅ **Home Assistant** - Smart home metrics ← NEW!

All unified in Grafana with comprehensive dashboards! 🚀

---

**Next**: Complete the Home Assistant configuration steps above to start seeing data!

