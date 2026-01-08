# Fix Home Assistant Authentication Issue

## Problem Identified

**Status**: Home Assistant is returning `401 Unauthorized` when Prometheus tries to scrape metrics.

**Root Cause**: The Home Assistant Prometheus endpoint requires authentication, but Prometheus is currently configured without authentication.

## Solution Overview

We need to:
1. Generate a Long-Lived Access Token in Home Assistant
2. Store the token as a Kubernetes Secret  
3. Update Prometheus configuration to use Bearer token authentication
4. Update Prometheus deployment to mount the secret
5. Restart Prometheus to apply changes

---

## Step 1: Generate Home Assistant Access Token

### Instructions:

1. **Open Home Assistant** in your browser:
   ```
   http://192.168.0.31:8123
   ```

2. **Login** with your credentials

3. **Access your Profile**:
   - Click on your username/avatar in the bottom left corner
   - Or navigate to: `http://192.168.0.31:8123/profile`

4. **Scroll down to the "Security" section**

5. **Create a Long-Lived Access Token**:
   - Under "Long-Lived Access Tokens", click **"CREATE TOKEN"**
   - Name: `Kubernetes Prometheus Monitoring`
   - Click **"OK"**

6. **Copy the Token**:
   - A long token will appear (looks like: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`)
   - **⚠️ CRITICAL**: Copy this token immediately!
   - You cannot retrieve it again after closing the dialog
   - Store it temporarily in a secure location

---

## Step 2: Create Kubernetes Secret

Once you have the token, run these commands:

### Method 1: Interactive (Recommended)

```bash
# This will prompt you to paste the token
kubectl create secret generic home-assistant-token \
  --from-literal=token="YOUR_LONG_LIVED_TOKEN_HERE" \
  -n monitoring
```

**Replace `YOUR_LONG_LIVED_TOKEN_HERE` with your actual token!**

### Method 2: From File

```bash
# Save token to a file first
echo "YOUR_LONG_LIVED_TOKEN_HERE" > /tmp/ha-token.txt

# Create secret from file
kubectl create secret generic home-assistant-token \
  --from-file=token=/tmp/ha-token.txt \
  -n monitoring

# Remove the temp file for security
rm /tmp/ha-token.txt
```

### Verify Secret Creation

```bash
# Check if secret exists
kubectl get secret home-assistant-token -n monitoring

# Should output:
# NAME                      TYPE     DATA   AGE
# home-assistant-token      Opaque   1      5s
```

---

## Step 3: Update Prometheus Configuration

The Prometheus configuration needs to be updated to use the Bearer token.

### Edit prometheus.yml:

Open `/Users/xalg/dev/terraform/epyc2/configs/prometheus/prometheus.yml` and find the `home-assistant` job (around line 115).

**Change FROM:**
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
    # Uncomment if you need authentication (most HA setups require this)
    # authorization:
    #   type: Bearer
    #   credentials: ${HOME_ASSISTANT_TOKEN}
```

**Change TO:**
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
    authorization:
      type: Bearer
      credentials_file: /etc/prometheus/secrets/ha-token
```

---

## Step 4: Update Prometheus Deployment

The Prometheus deployment needs to mount the secret as a file.

### Edit monitoring.tf:

Find the Prometheus deployment (search for `resource "kubernetes_deployment" "prometheus"`).

Add the following sections:

#### A. Add Volume Mount (in the container section):

Find the `prometheus` container and add this volume mount:

```hcl
          volume_mount {
            name       = "ha-token"
            mount_path = "/etc/prometheus/secrets"
            read_only  = true
          }
```

#### B. Add Volume (in the spec section):

Find the `volume` blocks and add:

```hcl
        volume {
          name = "ha-token"
          secret {
            secret_name = "home-assistant-token"
            items {
              key  = "token"
              path = "ha-token"
            }
          }
        }
```

---

## Step 5: Apply Changes

### Apply Terraform Configuration:

```bash
cd /Users/xalg/dev/terraform/epyc2

# Apply configuration updates
terraform apply \
  -target=kubernetes_config_map.prometheus_config \
  -target=kubernetes_deployment.prometheus \
  -auto-approve
```

### Wait for Prometheus to Restart:

```bash
# Watch the rollout
kubectl rollout status deployment/prometheus -n monitoring

# Should show:
# deployment "prometheus" successfully rolled out
```

---

## Step 6: Verify the Fix

### Check Prometheus Target Status:

```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

Then open: http://localhost:9090/targets

Find the `home-assistant` target - it should show **Status: UP** (green)

### Test Metrics Query:

In Prometheus UI (http://localhost:9090):

```promql
# Check if Home Assistant is up
up{job="home-assistant"}

# Should return: 1

# Query Home Assistant metrics
{job="home-assistant"}

# Should return all available metrics
```

### Check in Grafana:

1. Open Grafana: http://grafana.home
2. Go to **Explore**
3. Select **Prometheus** datasource
4. Run query:
   ```promql
   homeassistant_sensor_state
   ```
5. Should see data!

### View Dashboard:

1. In Grafana, go to **Dashboards** → **Browse**
2. Search for "Home Assistant"
3. Open **Home Assistant Overview** dashboard
4. Data should now populate!

---

## Alternative: Disable Authentication (Not Recommended)

If you prefer not to use authentication (only safe on trusted local networks):

### In Home Assistant configuration.yaml:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 192.168.0.0/24      # Your local network
    - 10.244.0.0/16       # Kubernetes pod network
    - 10.96.0.0/12        # Kubernetes service network

prometheus:
  namespace: homeassistant
  # No authentication required for trusted networks
```

Then restart Home Assistant. Prometheus will then be able to scrape without a token.

**⚠️ Warning**: This is less secure and not recommended for production environments.

---

## Troubleshooting

### Secret Not Found

```bash
# Check if secret exists
kubectl get secret -n monitoring | grep home-assistant

# If missing, recreate it (Step 2)
```

### Still Getting 401 Error

```bash
# Test authentication manually
HA_TOKEN=$(kubectl get secret home-assistant-token -n monitoring -o jsonpath='{.data.token}' | base64 -d)

# Test with curl
curl -H "Authorization: Bearer $HA_TOKEN" http://192.168.0.31:8123/api/prometheus | head
```

### Prometheus Pod Won't Start

```bash
# Check logs
kubectl logs -n monitoring -l app=prometheus --tail=100

# Common issues:
# - Secret not found: Recreate secret
# - Config syntax error: Check prometheus.yml syntax
# - Volume mount error: Verify volume configuration
```

### Token Expired or Invalid

Long-Lived Access Tokens don't expire automatically, but if you see authentication errors:

1. Delete the old token in Home Assistant (Profile → Security)
2. Create a new token
3. Update the Kubernetes secret:
   ```bash
   kubectl delete secret home-assistant-token -n monitoring
   # Then recreate with new token (Step 2)
   ```

---

## Quick Commands Reference

```bash
# Create secret (replace TOKEN)
kubectl create secret generic home-assistant-token \
  --from-literal=token="YOUR_TOKEN_HERE" \
  -n monitoring

# View secret (base64 encoded)
kubectl get secret home-assistant-token -n monitoring -o yaml

# Decode token to verify
kubectl get secret home-assistant-token -n monitoring \
  -o jsonpath='{.data.token}' | base64 -d

# Delete secret (to recreate)
kubectl delete secret home-assistant-token -n monitoring

# Test from Prometheus pod
PROM_POD=$(kubectl get pod -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n monitoring $PROM_POD -- cat /etc/prometheus/secrets/ha-token

# Restart Prometheus
kubectl rollout restart deployment/prometheus -n monitoring

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open: http://localhost:9090/targets
```

---

## Next Steps After Fix

Once Home Assistant data is flowing:

1. **Review Dashboard**: Check the Home Assistant Overview dashboard
2. **Customize**: Edit panels to show your specific sensors
3. **Create Alerts**: Set up alerts for important metrics (low battery, high temp, etc.)
4. **Add Panels**: Create custom panels for your specific Home Assistant entities

---

*Last Updated: January 2026*

