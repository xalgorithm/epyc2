# Deploy OPNsense Grafana Dashboards

## Quick Deploy Guide

### Step 1: Apply Terraform Configuration

```bash
cd /Users/xalg/dev/terraform/epyc2

# Review what will change
terraform plan -target=kubernetes_config_map.grafana_dashboards

# Apply the changes
terraform apply -target=kubernetes_config_map.grafana_dashboards
```

### Step 2: Restart Grafana

```bash
# Restart Grafana to load new dashboards
kubectl rollout restart deployment/grafana -n monitoring

# Wait for it to be ready
kubectl rollout status deployment/grafana -n monitoring
```

### Step 3: Access Your Dashboards

Open your browser and go to: **http://grafana.home**

Or use direct links:
- **Firewall Overview:** http://grafana.home/d/opnsense-firewall
- **Bandwidth Analysis:** http://grafana.home/d/opnsense-bandwidth  
- **Security Analysis:** http://grafana.home/d/opnsense-security

## What You'll See

### Dashboard 1: Firewall Overview
- Total events, blocks, and allows
- Real-time firewall activity graphs
- Top blocked IPs
- Protocol distribution
- Recent blocked traffic logs

### Dashboard 2: Bandwidth & Traffic Analysis ⭐
- **Most Chatty Hosts** - See who's using the most bandwidth!
- Total bandwidth graphs
- Bandwidth by protocol
- Top bandwidth consumers
- Inbound vs Outbound traffic
- Top destination ports

### Dashboard 3: Security & Threat Analysis
- Active threats detection
- Brute force attempt monitoring
- Port scan detection
- Top attacking IPs
- Attack timing patterns

## Verify Everything Works

```bash
# Check if logs are flowing
kubectl logs -n monitoring -l app=syslog-ng --tail=10

# Should see logs like:
# [2025-11-04T22:46:58+00:00] 10.244.1.1: <134>Test message from opnsense
```

If no logs appear, ensure OPNsense is configured correctly:
1. Go to OPNsense: **System → Settings → Logging / targets**
2. Verify remote logging to `192.168.0.36:514` is enabled
3. Test: `echo '<134>Test' | nc -u 192.168.0.36 514`

## What to Look At First

### Find Your Bandwidth Hogs
1. Open **Bandwidth Dashboard**
2. Scroll to **"Most Chatty Hosts"** table
3. See which devices are generating the most traffic
4. Identify any unexpected high-usage devices

### Check Security Status
1. Open **Security Dashboard**
2. Look at **"Blocks (Last 5m)"** - Should be relatively low
3. Check **"Suspicious IPs"** - Should be 0 or very few
4. Review **"Top Attacking IPs"** - These are trying to get in!

### Monitor Firewall Activity
1. Open **Firewall Dashboard**
2. Check **Block vs Allow ratio** - Should favor "Allow"
3. Review **"Recent Blocked Traffic"** - Live feed of blocks
4. Look at **"Protocol Distribution"** - Understand your traffic

## Troubleshooting

### Dashboards show "No Data"

```bash
# Check OPNsense is sending logs
kubectl logs -n monitoring -l app=syslog-ng --tail=20

# If empty, test from OPNsense:
echo '<134>Test from OPNsense' | nc -u 192.168.0.36 514

# Then check again:
kubectl logs -n monitoring -l app=syslog-ng --tail=5
```

### Dashboards load slowly

- Try a shorter time range (Last 1 hour instead of Last 24 hours)
- This is normal for high-traffic networks
- See performance tuning in docs

## Next Steps

1. ✅ **Bookmark dashboards** in your browser
2. ✅ **Review daily** to understand normal patterns  
3. ✅ **Set up alerts** for unusual activity (optional)
4. ✅ **Check "Most Chatty Hosts"** weekly to identify bandwidth issues

## Documentation

- **📘 Full Guide:** `docs/monitoring/OPNSENSE_DASHBOARDS.md`
- **📋 Quick Reference:** `docs/monitoring/OPNSENSE_QUICK_REFERENCE.md`
- **🔧 Setup Guide:** `docs/OPNSENSE_LOGGING.md`
- **🐛 Troubleshooting:** `docs/OPNSENSE_TROUBLESHOOTING.md`

## Questions?

Run the diagnostic script:
```bash
./scripts/troubleshooting/diagnose-syslog.sh
```

---

**🎉 Enjoy your new OPNsense visibility!**

**Pro Tips:**
- Check dashboards daily for security awareness
- Use "Most Chatty Hosts" to identify bandwidth problems
- Watch for unusual spikes in the Security dashboard
- Review blocked IPs regularly - you might be surprised who's trying to get in!

