# OPNsense Dashboards - Quick Reference

## Dashboard Access

| Dashboard | URL | Purpose |
|-----------|-----|---------|
| **Firewall Overview** | `http://grafana.home/d/opnsense-firewall` | General firewall activity |
| **Bandwidth Analysis** | `http://grafana.home/d/opnsense-bandwidth` | Traffic and bandwidth usage |
| **Security Analysis** | `http://grafana.home/d/opnsense-security` | Threats and attacks |

## Key Metrics at a Glance

### Firewall Overview Dashboard
- ✅ Total events processed
- 🚫 Blocked connections count
- ✓ Allowed connections count  
- 📊 Block vs Allow ratio
- 🌐 Top blocked IPs
- 🔌 Protocol distribution
- 📡 Traffic by interface

### Bandwidth Dashboard
- 📈 Real-time bandwidth graph
- 💾 Total data transferred
- 📦 Packet rates
- 👥 **Most chatty hosts** (TOP FEATURE)
- 🔝 Top bandwidth consumers
- ⬆️⬇️ Inbound vs Outbound
- 🔌 Top destination ports

### Security Dashboard
- 🚨 Blocks per minute
- ⚠️ Suspicious IPs (>100 blocks)
- 🔐 SSH/RDP brute force attempts
- 🎯 Most attacked ports
- 🔍 Port scan detection
- 📍 Attack sources
- 🕐 Attack timing patterns

## Quick Queries

### Find Chatty Devices
```logql
{application="opnsense"} |~ "filterlog" 
| regexp "filterlog: [^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,(?P<src_ip>[0-9.]+),"
```
→ See "Most Chatty Hosts" table in Bandwidth Dashboard

### Find Who's Being Blocked
```logql
{application="opnsense"} |~ "filterlog" |~ "block" 
| regexp ",(?P<src_ip>[0-9.]+),"
```
→ See "Top Attacking IPs" in Security Dashboard

### Track Bandwidth by Protocol
```logql
sum by (protocol) (rate({application="opnsense"} 
| regexp ",(?P<protocol>tcp|udp|icmp)," [1m])) * 1500
```
→ See "Bandwidth by Protocol" graph

### Monitor SSH Attacks
```logql
{application="opnsense"} |~ "filterlog" |~ "block" 
| regexp ",tcp," | regexp ",22,"
```
→ See "RDP/SSH Attempts" stat

## Common Investigations

### "Who is using all my bandwidth?"
1. Go to **Bandwidth Dashboard**
2. Check **Most Chatty Hosts** table (sorted by packet count)
3. Look for unusual IPs or unexpectedly high traffic

### "Am I under attack?"
1. Go to **Security Dashboard**
2. Check **Blocks (Last 5m)** - Should be <1000
3. Look at **Suspicious IPs** - Should be 0-5
4. Check **Top Attacking IPs** table

### "What's being blocked on my firewall?"
1. Go to **Firewall Dashboard**
2. Check **Top Blocked Source IPs**
3. Review **Recent Blocked Traffic** log stream
4. Check **Protocol Distribution** for patterns

### "Is someone port scanning me?"
1. Go to **Security Dashboard**
2. Check **Potential Port Scanners** panel
3. Look for IPs hitting many different ports
4. Review **Most Targeted Ports**

### "What services are most used?"
1. Go to **Bandwidth Dashboard**
2. Check **Top Destination Ports** table
3. Cross-reference with allowed traffic
4. Common ports:
   - 80/443 = Web (HTTP/HTTPS)
   - 53 = DNS
   - 22 = SSH
   - 3389 = RDP

## Alerting Thresholds

| Alert | Threshold | Action |
|-------|-----------|--------|
| High block rate | >100/sec | Investigate source |
| SSH brute force | >50 attempts/5min | Consider blocking IP |
| Suspicious IP | >200 blocks/5min | Auto-block recommended |
| Port scan | >20 ports/1min | Investigate and block |

## Deployment Commands

```bash
# Apply dashboards
cd /Users/xalg/dev/terraform/epyc2
terraform apply -target=kubernetes_config_map.grafana_dashboards

# Restart Grafana
kubectl rollout restart deployment/grafana -n monitoring

# Verify dashboards loaded
kubectl logs -n monitoring -l app=grafana | grep -i dashboard

# Check if logs are flowing
kubectl logs -n monitoring -l app=syslog-ng --tail=20 -f
```

## Troubleshooting Quick Check

```bash
# 1. Is syslog-ng receiving logs?
kubectl logs -n monitoring -l app=syslog-ng --tail=10

# 2. Is OPNsense sending logs?
# From OPNsense shell:
echo '<134>Test from OPNsense' | nc -u 192.168.0.36 514

# 3. Are logs in Loki?
kubectl exec -n monitoring $(kubectl get pod -n monitoring -l app=loki -o name | head -1) -- \
  wget -qO- 'http://localhost:3100/loki/api/v1/query?query={application="opnsense"}' | jq

# 4. Run full diagnostic
./scripts/troubleshooting/diagnose-syslog.sh
```

## Time Ranges

Choose appropriate time ranges for different use cases:

| Use Case | Recommended Range |
|----------|-------------------|
| Real-time monitoring | Last 15 minutes |
| Daily review | Last 6 hours |
| Weekly summary | Last 24 hours |
| Monthly review | Last 7 days |
| Incident investigation | Custom range |
| Performance baseline | Last 30 days |

## Understanding "Most Chatty Hosts"

The **Most Chatty Hosts** feature identifies devices generating the most network traffic:

### What It Shows
- Top 20 devices by packet count
- Estimated bandwidth per device
- Visual ranking (gradient bars)
- Sorted highest to lowest

### Common Chatty Devices
- **Smart TVs** - Streaming services
- **Gaming consoles** - Downloads, online gaming
- **Workstations** - Video calls, cloud sync
- **NAS devices** - Backups, media serving
- **IoT cameras** - Video uploads
- **Phones/tablets** - Updates, streaming

### Red Flags 🚩
- Unknown IPs with high traffic
- IoT devices with unexpected high usage
- Sudden spikes from normally quiet devices
- External IPs in your top talkers (possible breach)

### Investigation Steps
1. Identify the IP in "Most Chatty Hosts"
2. Check **Top Destination Ports** - What services?
3. Look at **Traffic Direction** - Upload or download?
4. Review **Protocol Distribution** - Normal protocols?
5. Cross-reference with your known devices

## Bandwidth Estimation

**Note:** Bandwidth is estimated using:
```
Bandwidth (bytes) ≈ Packet Count × 1500 (avg MTU)
```

This is an approximation because:
- Actual packet sizes vary (64-1500 bytes)
- Doesn't include all overhead
- Based on firewall logs only

**Use for:** Relative comparisons, trend analysis, identifying heavy users  
**Don't use for:** Exact billing, precise capacity planning

## Performance Tips

### For High-Traffic Networks (>10,000 events/minute)

1. **Adjust query intervals**
   - Change `[1m]` to `[5m]` in queries
   - Reduces query load

2. **Limit displayed results**
   - Top 10 instead of Top 20
   - Shorter time ranges

3. **Increase dashboard refresh interval**
   - 30s or 1m instead of 5s
   - Dashboard settings → Time options

4. **Scale Loki resources**
   ```bash
   kubectl edit deployment loki -n monitoring
   # Increase CPU/memory limits
   ```

## Export and Reporting

### Manual Export
1. Open dashboard
2. Share → Export → Save to file
3. Get JSON for backup/sharing

### Automated Reports
Use Grafana's reporting feature:
1. Install Grafana Image Renderer
2. Schedule reports via UI
3. Email daily/weekly summaries

### API Access
```bash
# Get dashboard JSON
curl -H "Authorization: Bearer $API_KEY" \
  http://grafana.home/api/dashboards/uid/opnsense-firewall
```

## Security Best Practices

1. **Daily Check** - Review dashboards each morning
2. **Alert Tuning** - Set up alerts for your baseline
3. **Blocklist** - Maintain list of known bad IPs
4. **Log Retention** - Keep 30-90 days for forensics
5. **Backup Configs** - Export dashboards monthly
6. **Document Incidents** - Note unusual patterns

## Integration Ideas

### With OPNsense
- Create firewall rules based on findings
- Add persistent blocks for repeat offenders
- Tune IDS/IPS based on attack patterns

### With Home Automation
- n8n workflow: Alert on high traffic
- MQTT: Publish metrics to Home Assistant
- Telegram: Send alerts to your phone

### With Other Tools
- Export to spreadsheet for reporting
- Feed data to SIEM
- Integrate with ticketing system

## Resources

- **Full Documentation:** `docs/monitoring/OPNSENSE_DASHBOARDS.md`
- **OPNsense Setup:** `docs/OPNSENSE_LOGGING.md`
- **Troubleshooting:** `docs/OPNSENSE_TROUBLESHOOTING.md`
- **Diagnostic Script:** `scripts/troubleshooting/diagnose-syslog.sh`

## Quick Links

- Grafana Home: `http://grafana.home`
- Grafana Explore: `http://grafana.home/explore`
- Dashboard List: `http://grafana.home/dashboards`
- Data Sources: `http://grafana.home/datasources`

---

**💡 Pro Tip:** Bookmark all three dashboards in your browser for quick access!

**🔍 Investigation Workflow:**  
Security Dashboard → Identify threat → Firewall Dashboard → Verify pattern → Bandwidth Dashboard → Check impact

