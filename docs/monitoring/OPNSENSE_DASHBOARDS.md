# OPNsense Grafana Dashboards

Comprehensive Grafana dashboards for monitoring OPNsense firewall activity, bandwidth usage, and security threats.

## Overview

Three specialized dashboards provide complete visibility into your OPNsense firewall:

1. **OPNsense Firewall Overview** - General firewall activity and traffic patterns
2. **OPNsense Bandwidth & Traffic Analysis** - Bandwidth consumption and network usage
3. **OPNsense Security & Threat Analysis** - Security events, threats, and attack patterns

## Prerequisites

- OPNsense configured to send logs to syslog-ng (see `docs/OPNSENSE_LOGGING.md`)
- Logs flowing into Loki with `application="opnsense"` label
- Grafana deployed and accessible

## Dashboard 1: OPNsense Firewall Overview

**UID:** `opnsense-firewall`  
**Access:** `http://grafana.home/d/opnsense-firewall`

### Panels

#### Summary Statistics (Top Row)
- **Total Firewall Events** - All firewall log entries in the selected time range
- **Blocked Connections** - Total number of blocked connection attempts
- **Allowed Connections** - Total number of allowed connections
- **Event Rate** - Real-time events per second

#### Visualizations
- **Firewall Actions Over Time** - Time series showing blocks vs allows
- **Firewall Action Distribution** - Pie chart of block/pass ratio
- **Top Blocked Source IPs** - Table of most frequently blocked source addresses
- **Top Blocked Destination IPs** - Table of most targeted destinations
- **Protocol Distribution** - Breakdown by TCP/UDP/ICMP/other protocols
- **Traffic by Interface** - Activity per network interface
- **Recent Blocked Traffic** - Live log stream of blocked connections

### Use Cases
- Monitor overall firewall health
- Identify suspicious source IPs
- Understand traffic patterns
- Quick security posture assessment

## Dashboard 2: OPNsense Bandwidth & Traffic Analysis

**UID:** `opnsense-bandwidth`  
**Access:** `http://grafana.home/d/opnsense-bandwidth`

### Panels

#### Bandwidth Metrics (Top Row)
- **Estimated Total Traffic** - Total data transferred (estimated from packet count × average packet size)
- **Total Packets** - Raw packet count
- **Avg Packet Rate** - Packets per second averaged over time

#### Visualizations
- **Bandwidth Usage Over Time** - Time series graph showing:
  - Total bandwidth
  - Allowed traffic bandwidth
  - Blocked traffic bandwidth
- **Bandwidth by Protocol** - Time series by TCP/UDP/ICMP
- **Top Bandwidth Users (Source)** - Pie chart of heaviest consumers
- **Most Chatty Hosts** - Table showing:
  - Source IP addresses
  - Packet count
  - Estimated bandwidth usage
  - Color-coded by volume
- **Traffic Direction** - Inbound vs Outbound comparison
- **Top Destination Ports** - Most frequently accessed ports

### Key Features

#### Bandwidth Calculation
Since OPNsense filterlog doesn't include exact byte counts, bandwidth is estimated using:
```
Bandwidth ≈ Packet Count × 1500 bytes (average MTU)
```

This provides a reasonable approximation for traffic analysis.

#### Most Chatty Hosts Analysis
The "Most Chatty Hosts" table identifies network devices generating the most traffic:
- **Top 20 hosts** by packet count
- **Estimated bandwidth** for each host
- **Visual indicators** (gradient gauges) showing relative activity
- Sorted by packet count (highest first)

**Example Use Cases:**
- Identify bandwidth hogs
- Detect unexpected high-volume traffic
- Monitor IoT device activity
- Track streaming/download activity

### Use Cases
- Bandwidth capacity planning
- Identify bandwidth-heavy applications
- Detect abnormal traffic patterns
- Network performance analysis
- Find chatty devices on your network

## Dashboard 3: OPNsense Security & Threat Analysis

**UID:** `opnsense-security`  
**Access:** `http://grafana.home/d/opnsense-security`

### Panels

#### Security Metrics (Top Row)
- **Blocks (Last 5m)** - Recent block count
- **Suspicious IPs** - Sources with >100 blocks (potential attackers)
- **RDP/SSH Attempts** - Brute force login attempts in last hour
- **Unique Blocked IPs** - Distinct attacking IPs

#### Threat Visualizations
- **Block Rate by Type** - Time series showing:
  - Total blocks
  - SSH/RDP blocks
  - Web traffic blocks
- **Top Attacking Source IPs** - Table of most aggressive attackers
- **Most Targeted Ports** - Services under attack
- **Potential Port Scanners** - IPs probing multiple ports
- **Blocked Protocols Distribution** - Pie chart of blocked protocol types
- **Recent High-Risk Port Blocks** - Live log of SSH/RDP/Telnet/SMB attempts
- **Block Activity Heatmap** - Visual pattern of attack timing

### Security Insights

#### High-Risk Port Monitoring
Tracks attempts on commonly attacked services:
- **Port 22** - SSH
- **Port 3389** - RDP (Remote Desktop)
- **Port 23** - Telnet
- **Port 445** - SMB (File sharing)
- **Port 135/139** - Windows RPC/NetBIOS

#### Suspicious IP Detection
Automatically identifies potentially malicious IPs:
- **>100 blocks in 5 minutes** - Likely automated attack
- **Multiple port probes** - Port scanning activity
- **Repeated SSH/RDP attempts** - Brute force attacks

### Use Cases
- Identify active threats
- Monitor for brute force attacks
- Detect port scanning activity
- Security incident response
- Compliance reporting
- Threat intelligence gathering

## Common Queries

### LogQL Examples

All dashboards use Loki's LogQL query language. Here are common patterns:

#### Basic Queries
```logql
# All OPNsense logs
{application="opnsense"}

# Only firewall logs
{application="opnsense"} |~ "filterlog"

# Blocked traffic
{application="opnsense"} |~ "filterlog" |~ "block"

# Allowed traffic
{application="opnsense"} |~ "filterlog" |~ "pass"
```

#### Advanced Filtering
```logql
# Extract source IP
{application="opnsense"} |~ "filterlog" 
| regexp "filterlog: [^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,(?P<src_ip>[0-9.]+),"

# Filter by protocol
{application="opnsense"} |~ "filterlog" 
| regexp ",(?P<protocol>tcp|udp|icmp),"

# Filter by port
{application="opnsense"} |~ "filterlog" 
| regexp ",(?P<port>22|3389|443),"

# Combine filters (SSH attempts)
{application="opnsense"} |~ "filterlog" |~ "block"
| regexp ",tcp,"
| regexp ",22,"
```

#### Rate Calculations
```logql
# Events per second
sum(rate({application="opnsense"} |~ "filterlog" [1m]))

# Blocks per minute
sum(rate({application="opnsense"} |~ "filterlog" |~ "block" [1m]))

# Bandwidth estimation (packets/sec × 1500 bytes)
sum(rate({application="opnsense"} |~ "filterlog" [1m])) * 1500
```

#### Aggregations
```logql
# Count by action
sum by (action) (count_over_time({application="opnsense"} 
| regexp ",(?P<action>block|pass)," [$__range]))

# Top IPs
topk(10, sum by (src_ip) (count_over_time({application="opnsense"} 
| regexp "filterlog: [^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,(?P<src_ip>[0-9.]+)," [$__range])))
```

## OPNsense Filterlog Format

Understanding the filterlog CSV format helps customize dashboards:

```
filterlog: rule_num,sub_rule,anchor,tracker,interface,reason,action,direction,ip_version,tos,ecn,ttl,id,offset,flags,protocol_id,protocol,length,src_ip,dst_ip,src_port,dst_port,data_length,tcp_flags,...
```

### Key Fields
- **Position 5:** `interface` (e.g., igb0, igb1)
- **Position 6:** `action` (block, pass)
- **Position 7:** `direction` (in, out)
- **Position 16:** `protocol` (tcp, udp, icmp)
- **Position 17:** `length` (packet size)
- **Position 18:** `src_ip` (source IP)
- **Position 19:** `dst_ip` (destination IP)
- **Position 20:** `src_port` (source port)
- **Position 21:** `dst_port` (destination port)

## Customization

### Adding Custom Panels

1. **Open dashboard** in Grafana
2. **Click "Add Panel"**
3. **Select Loki** as data source
4. **Write LogQL query**
5. **Choose visualization** type
6. **Save dashboard**

### Example: Custom Panel for Your Local Subnet

Track traffic from/to your internal network (e.g., 192.168.1.0/24):

```logql
# Outbound from your network
{application="opnsense"} |~ "filterlog"
| regexp "filterlog: [^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,192\\.168\\.1\\.[0-9]+,"

# Inbound to your network
{application="opnsense"} |~ "filterlog"
| regexp "filterlog: [^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,192\\.168\\.1\\.[0-9]+,"
```

### Variables

Add dashboard variables for dynamic filtering:

1. **Interface Variable**
   ```logql
   label_values({application="opnsense"}, interface)
   ```

2. **Action Variable**
   ```
   Options: block, pass
   ```

3. **Time Range Variable**
   ```
   Options: 5m, 15m, 1h, 6h, 24h, 7d
   ```

## Performance Optimization

### For High-Traffic Networks

If you have high log volumes (>1000 events/sec):

1. **Increase time interval** in rate queries:
   ```logql
   # Instead of [1m], use [5m]
   sum(rate({application="opnsense"} [5m]))
   ```

2. **Limit result sets**:
   ```logql
   # Use topk/bottomk
   topk(20, ...) instead of showing all
   ```

3. **Adjust dashboard refresh**:
   - Settings → Time options → Auto refresh
   - Use 30s or 1m instead of 5s

4. **Filter at source**:
   ```logql
   # Filter early in query
   {application="opnsense"} |~ "filterlog" |~ "block"
   # Instead of filtering after
   ```

### Loki Configuration

For optimal performance, ensure Loki has adequate resources:

```yaml
limits_config:
  max_query_series: 10000
  max_query_range: 7d
  query_timeout: 5m
```

## Alerting

### Recommended Alerts

Create Grafana alerts for security events:

#### 1. High Block Rate
```logql
sum(rate({application="opnsense"} |~ "block" [5m])) > 100
```
**Condition:** Alert if >100 blocks/sec  
**Severity:** Warning

#### 2. Brute Force Attempts
```logql
sum(count_over_time({application="opnsense"} |~ "block" 
| regexp ",(?P<port>22|3389)," [5m])) > 50
```
**Condition:** Alert if >50 SSH/RDP attempts in 5 minutes  
**Severity:** High

#### 3. Suspicious IP
```logql
count(count by (src_ip) (count_over_time({application="opnsense"} 
|~ "block" [5m])) > 200) > 0
```
**Condition:** Alert if any IP has >200 blocks in 5 minutes  
**Severity:** Critical

#### 4. Port Scan Detection
```logql
# Alert on IPs hitting many different ports
count by (src_ip) (count_over_time({application="opnsense"} 
|~ "block" | regexp ",(?P<dst_port>[0-9]+)," [1m])) > 20
```
**Condition:** Alert if any IP hits >20 different ports in 1 minute  
**Severity:** High

### Setting Up Alerts

1. **Open panel** you want to alert on
2. **Click Alert** tab
3. **Create alert rule**
4. **Set conditions** (query, threshold, evaluation interval)
5. **Add notification channel** (email, Slack, Discord, webhook)
6. **Save alert**

## Deployment

### Apply Dashboards

The dashboards are automatically deployed with Terraform:

```bash
cd /Users/xalg/dev/terraform/epyc2

# Plan to review changes
terraform plan -target=kubernetes_config_map.grafana_dashboards

# Apply
terraform apply -target=kubernetes_config_map.grafana_dashboards

# Restart Grafana to load new dashboards
kubectl rollout restart deployment/grafana -n monitoring
```

### Access Dashboards

After deployment, access via:

- **Grafana Home:** `http://grafana.home`
- **Browse Dashboards:** `http://grafana.home/dashboards`
- **Search:** Type "OPNsense" in dashboard search

Or direct URLs:
- Firewall: `http://grafana.home/d/opnsense-firewall`
- Bandwidth: `http://grafana.home/d/opnsense-bandwidth`
- Security: `http://grafana.home/d/opnsense-security`

## Troubleshooting

### Dashboards Show No Data

1. **Verify logs are flowing:**
   ```bash
   kubectl logs -n monitoring -l app=syslog-ng --tail=20
   ```

2. **Check Loki has data:**
   ```bash
   # Query Loki directly
   kubectl exec -n monitoring $(kubectl get pod -n monitoring -l app=loki -o name | head -1) -- \
     wget -qO- 'http://localhost:3100/loki/api/v1/query?query={application="opnsense"}' | jq
   ```

3. **Test in Grafana Explore:**
   - Go to Explore
   - Select Loki datasource
   - Run: `{application="opnsense"} |~ "filterlog"`
   - Should show logs

4. **Check time range:**
   - Ensure dashboard time range includes when logs exist
   - Try "Last 24 hours"

### Dashboards Load Slowly

1. **Reduce query time range**
2. **Increase query interval** ([1m] → [5m])
3. **Limit result sets** (use topk/limit)
4. **Check Loki resources:**
   ```bash
   kubectl top pod -n monitoring -l app=loki
   ```

### Metrics Seem Incorrect

**Bandwidth Estimates:**
- Remember: Bandwidth is estimated (packet count × 1500)
- Actual may vary based on packet sizes
- Use as relative measurement, not absolute

**Packet Counts:**
- Only includes firewall-processed packets
- May not match interface statistics
- Excludes bypassed/offloaded traffic

## Integration with Other Tools

### Export Data

Export metrics for external analysis:

```bash
# Export to CSV via Grafana API
curl -H "Authorization: Bearer $GRAFANA_API_KEY" \
  'http://grafana.home/api/ds/query' \
  -d '{"queries":[{"expr":"{application=\"opnsense\"}","refId":"A"}]}'
```

### Automation

Use Grafana API for automated reporting:

```python
import requests

# Get dashboard snapshot
url = "http://grafana.home/api/dashboards/uid/opnsense-firewall"
headers = {"Authorization": f"Bearer {api_key}"}
response = requests.get(url, headers=headers)
dashboard_data = response.json()
```

### n8n Workflows

Create automated workflows triggered by events:
1. Configure Grafana webhook alert
2. Point to n8n webhook node
3. Process alert and take action (email, notification, etc.)

## Best Practices

1. **Regular Review** - Check dashboards daily for unusual activity
2. **Baseline Normal** - Understand your typical traffic patterns
3. **Alert Tuning** - Adjust alert thresholds to reduce noise
4. **Documentation** - Document security incidents discovered
5. **Retention** - Keep logs for compliance/forensics (30-90 days)
6. **Backup Dashboards** - Export dashboard JSON regularly

## Additional Resources

- **OPNsense Logging Guide:** `docs/OPNSENSE_LOGGING.md`
- **Troubleshooting:** `docs/OPNSENSE_TROUBLESHOOTING.md`
- **Loki Query Language:** [LogQL Documentation](https://grafana.com/docs/loki/latest/logql/)
- **Grafana Dashboards:** [Grafana Documentation](https://grafana.com/docs/grafana/latest/dashboards/)

## Support

For issues or questions:
1. Check syslog-ng logs: `kubectl logs -n monitoring -l app=syslog-ng`
2. Run diagnostic: `./scripts/troubleshooting/diagnose-syslog.sh`
3. Review documentation in `docs/` directory

---

**Dashboard Version:** 1.0  
**Last Updated:** November 4, 2025  
**Compatible With:** OPNsense 23.x+, Grafana 9.x+, Loki 2.x+

