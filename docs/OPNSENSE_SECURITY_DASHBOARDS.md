# OPNsense Security Dashboards - Implementation Guide

## Overview

This guide provides sophisticated, security-focused dashboards and queries for comprehensive OPNsense monitoring in Grafana using Loki.

## Dashboard 1: Threat Intelligence Dashboard

**Purpose**: Real-time threat detection, attack pattern analysis, and brute-force monitoring

### Key Panels:

#### 1. Threat Block Rate (Time Series)
**Query**:
```logql
# Total blocks
sum(rate({application="opnsense"} |= "filterlog" |= "block" [1m]))

# Inbound blocks
sum(rate({application="opnsense"} |= "filterlog" |= "block" |= "in" [1m]))

# Outbound blocks  
sum(rate({application="opnsense"} |= "filterlog" |= "block" |= "out" [1m]))
```
**Visualization**: Time series with legend showing mean, max, last values

#### 2. Total Threats Blocked (Stat Panel)
**Query**:
```logql
sum(count_over_time({application="opnsense"} |= "filterlog" |= "block" [$__range]))
```
**Thresholds**: Green < 1000, Yellow < 5000, Red >= 5000

#### 3. Failed Authentication Attempts (Stat Panel)
**Query**:
```logql
sum(count_over_time({application="opnsense", facility="auth"} |= "fail" [$__range]))
```
**Thresholds**: Green < 10, Orange < 50, Red >= 50

#### 4. SSH Brute Force Detection (Stat Panel)
**Query**:
```logql
sum(count_over_time({application="opnsense"} |= "sshd" |= "Failed" [$__range]))
```
**Thresholds**: Green < 5, Yellow < 20, Red >= 20

#### 5. Top Attacking IPs (Table)
**Query**:
```logql
{application="opnsense"} |= "filterlog" |= "block" 
| regexp `(?P<src_ip>\d+\.\d+\.\d+\.\d+)` 
| line_format "{{.src_ip}}"
```
**Features**: 
- Color-coded by attack count
- Sorted descending
- Limited to top 20

#### 6. Blocked Traffic by Protocol (Pie Chart)
**Queries**:
```logql
# TCP
{application="opnsense"} |= "filterlog" |= "block" |= "tcp"

# UDP
{application="opnsense"} |= "filterlog" |= "block" |= "udp"

# ICMP
{application="opnsense"} |= "filterlog" |= "block" |= "icmp"
```
**Visualization**: Donut chart with percentages

#### 7. Most Attacked Ports (Bar Chart)
**Query**:
```logql
sum by (port) (count_over_time({application="opnsense"} |= "filterlog" |= "block" 
| regexp `:(?P<port>\d+)` [5m]))
```
**Visualization**: Bar chart showing port attack frequency

#### 8. Real-Time Threat Stream (Logs)
**Query**:
```logql
{application="opnsense"} |= "filterlog" |= "block" 
| line_format "🚫 {{.line}}"
```
**Features**: Live streaming with emoji indicators

#### 9. Common Attack Vectors (Time Series)
**Queries**:
```logql
# SSH attacks (port 22)
sum(rate({application="opnsense"} |= "filterlog" |= "block" |~ ":22" [1m]))

# Telnet attacks (port 23)
sum(rate({application="opnsense"} |= "filterlog" |= "block" |~ ":23" [1m]))

# RDP attacks (port 3389)
sum(rate({application="opnsense"} |= "filterlog" |= "block" |~ ":3389" [1m]))

# SMB attacks (port 445)
sum(rate({application="opnsense"} |= "filterlog" |= "block" |~ ":445" [1m]))

# SQL attacks (port 1433)
sum(rate({application="opnsense"} |= "filterlog" |= "block" |~ ":1433" [1m]))
```

#### 10. SSH Brute Force Activity (Logs)
**Query**:
```logql
{application="opnsense"} |= "sshd" |= "Failed" 
| line_format "⚠️ SSH Attack: {{.line}}"
```

---

## Dashboard 2: Network Anomalies & Traffic Analysis

**Purpose**: Detect unusual patterns, bandwidth anomalies, and geographic threats

### Key Panels:

#### 1. Traffic Volume Anomaly Detection (Time Series)
**Queries**:
```logql
# Total traffic rate
sum(rate({application="opnsense"} |= "filterlog" [1m]))

# Blocked vs passed ratio
sum(rate({application="opnsense"} |= "filterlog" |= "block" [1m])) 
/ 
sum(rate({application="opnsense"} |= "filterlog" [1m]))
```
**Features**: Show when block ratio exceeds normal thresholds

#### 2. Unusual Port Activity (Heatmap)
**Query**:
```logql
sum by (port, hour) (
  count_over_time({application="opnsense"} |= "filterlog" 
  | regexp `:(?P<port>\d+)` [1h])
)
```
**Visualization**: Heatmap showing port activity by hour

#### 3. Connection State Distribution (Pie Chart)
**Queries**:
```logql
{application="opnsense"} |= "filterlog" |= "pass"
{application="opnsense"} |= "filterlog" |= "block"
{application="opnsense"} |= "filterlog" |= "reject"
```

#### 4. Top Bandwidth Consumers (Bar Gauge)
**Query**:
```logql
topk(10, 
  sum by (src_ip) (
    rate({application="opnsense"} |= "filterlog" 
    | regexp `(?P<src_ip>\d+\.\d+\.\d+\.\d+)` [5m])
  )
)
```

#### 5. Outbound Connection Analysis (Table)
**Query**:
```logql
{application="opnsense"} |= "filterlog" |= "out" != "192.168."
| regexp `(?P<dst_ip>\d+\.\d+\.\d+\.\d+):(?P<dst_port>\d+)`
```
**Features**: Track connections to external IPs

#### 6. DNS Query Volume (Time Series)
**Query**:
```logql
sum(rate({application="opnsense"} |= "unbound" [1m]))
```

#### 7. Traffic Pattern Changes (Time Series)
**Query**:
```logql
# Compare current hour to previous hour
sum(rate({application="opnsense"} |= "filterlog" [1h] offset 1h))
```

#### 8. Unusual Protocol Usage (Table)
**Query**:
```logql
{application="opnsense"} |= "filterlog" 
!= "tcp" != "udp" != "icmp"
| regexp `(?P<protocol>[a-z]+)`
```

---

## Dashboard 3: Access Control & Authentication Security

**Purpose**: Monitor VPN, SSH, and authentication security

### Key Panels:

#### 1. Authentication Success/Failure Ratio (Gauge)
**Queries**:
```logql
# Successes
sum(count_over_time({application="opnsense", facility="auth"} 
|= "Accepted" [$__range]))

# Failures
sum(count_over_time({application="opnsense", facility="auth"} 
|= "Failed" [$__range]))
```
**Visualization**: Gauge showing failure percentage

#### 2. SSH Login Attempts by User (Table)
**Query**:
```logql
{application="opnsense"} |= "sshd" 
| regexp `for (?P<user>\w+) from (?P<ip>\d+\.\d+\.\d+\.\d+)`
```
**Features**: Show username, IP, success/failure

#### 3. Root Access Attempts (Stat Panel)
**Query**:
```logql
sum(count_over_time({application="opnsense"} 
|= "sshd" |= "root" [$__range]))
```
**Thresholds**: Any value > 0 should be RED (critical)

#### 4. VPN Connection Activity (Time Series)
**Query**:
```logql
sum(rate({application="opnsense"} |= "openvpn" [1m]))
```

#### 5. Failed Login Sources (Geomap)
**Query**:
```logql
{application="opnsense"} |= "Failed" 
| regexp `from (?P<ip>\d+\.\d+\.\d+\.\d+)`
```
**Features**: Plot on world map (requires GeoIP)

#### 6. Account Lockout Events (Logs)
**Query**:
```logql
{application="opnsense"} |= "locked" | or "suspended"
| line_format "🔒 {{.line}}"
```

#### 7. Privilege Escalation Attempts (Logs)
**Query**:
```logql
{application="opnsense"} |= "sudo" |= "DENIED"
| line_format "⛔ Privilege Escalation: {{.line}}"
```

#### 8. Multi-Factor Authentication (MFA) Activity
**Query**:
```logql
{application="opnsense"} |= "2fa" | or "mfa" | or "otp"
```

---

## Dashboard 4: Deep Packet Inspection & Protocol Analysis

**Purpose**: Advanced protocol analysis and application layer security

### Key Panels:

#### 1. HTTP/HTTPS Traffic Analysis (Time Series)
**Queries**:
```logql
# Port 80 (HTTP)
sum(rate({application="opnsense"} |= "filterlog" |~ ":80" [1m]))

# Port 443 (HTTPS)
sum(rate({application="opnsense"} |= "filterlog" |~ ":443" [1m]))
```

#### 2. Application Protocol Distribution (Sankey Diagram)
**Query**:
```logql
{application="opnsense"} |= "filterlog"
| regexp `(?P<protocol>tcp|udp):(?P<port>\d+)`
```
**Features**: Flow from protocol → port → action

#### 3. TLS/SSL Certificate Errors (Logs)
**Query**:
```logql
{application="opnsense"} |= "ssl" |= "error" | or "certificate"
```

#### 4. ICMP Flood Detection (Time Series)
**Query**:
```logql
sum(rate({application="opnsense"} |= "icmp" [1m]))
```
**Threshold**: Alert if > 100/sec

#### 5. SYN Flood Detection (Time Series)
**Query**:
```logql
sum(rate({application="opnsense"} |= "tcp" |= "SYN" [1m]))
```

#### 6. DNS Amplification Attack Detection (Stat)
**Query**:
```logql
sum(count_over_time({application="opnsense"} |= "udp" |~ ":53" 
|= "block" [$__range]))
```

#### 7. Fragmented Packet Analysis (Time Series)
**Query**:
```logql
sum(rate({application="opnsense"} |= "fragment" [1m]))
```

#### 8. Protocol Anomalies (Logs)
**Query**:
```logql
{application="opnsense"} |= "invalid" | or "malformed" | or "bad"
| line_format "⚠️ Protocol Anomaly: {{.line}}"
```

---

## Dashboard 5: Compliance & Audit Trail

**Purpose**: Security compliance monitoring and audit logging

### Key Panels:

#### 1. Firewall Rule Changes (Table)
**Query**:
```logql
{application="opnsense"} |= "firewall" |= "rule" 
|~ "(add|delete|modify)"
```

#### 2. Configuration Changes (Logs)
**Query**:
```logql
{application="opnsense"} |= "config" |= "change"
| line_format "⚙️ Config Change: {{.line}}"
```

#### 3. Administrative Actions (Table)
**Query**:
```logql
{application="opnsense"} |= "admin" | or "root" 
| regexp `(?P<action>add|delete|modify|restart)`
```

#### 4. Compliance Violations (Stat)
**Query**:
```logql
sum(count_over_time({application="opnsense"} 
|= "violation" | or "policy" [$__range]))
```

#### 5. Security Event Timeline (Time Series)
**Queries**:
```logql
sum by (severity) (
  rate({application="opnsense"} [1m])
)
```

---

## Advanced Query Patterns

### 1. Detect Port Scanning
```logql
sum by (src_ip) (
  count_over_time({application="opnsense"} |= "block" [5m])
) > 50
```

### 2. Identify Persistent Attackers
```logql
topk(10,
  sum by (src_ip) (
    count_over_time({application="opnsense"} |= "block" [24h])
  )
) > 1000
```

### 3. Unusual Time-Based Access
```logql
{application="opnsense"} |= "Accepted"
| regexp `(?P<hour>\d\d):\d\d:\d\d`
| hour < "06" or hour > "22"
```

### 4. Bandwidth Spike Detection
```logql
rate({application="opnsense"} |= "filterlog" [1m])
> on() 
(avg_over_time(rate({application="opnsense"} |= "filterlog" [1m])[1h:]) * 3)
```

### 5. Geographic Threat Correlation
```logql
{application="opnsense"} |= "block"
| regexp `from (?P<ip>\d+\.\d+\.\d+\.\d+)`
| geoip(ip)
```

### 6. Zero-Day Attack Pattern
```logql
{application="opnsense"} |= "block"
| regexp `:(?P<port>\d+)`
| port > "50000"
```

### 7. Botnet Detection
```logql
count by (src_ip) (
  count_over_time({application="opnsense"} |= "block" [1m])
) > 10
```

### 8. Data Exfiltration Detection
```logql
{application="opnsense"} |= "out" 
| regexp `(?P<bytes>\d+) bytes`
| bytes > "10000000"
```

---

## Alert Rules

### Critical Alerts

#### 1. Brute Force Attack
```yaml
- alert: SSHBruteForceAttack
  expr: sum(rate({application="opnsense"} |= "sshd" |= "Failed" [5m])) > 5
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "SSH brute force attack detected"
```

#### 2. Port Scan Detected
```yaml
- alert: PortScanDetected
  expr: sum by (src_ip) (count_over_time({application="opnsense"} |= "block" [5m])) > 50
  for: 1m
  labels:
    severity: warning
  annotations:
    summary: "Port scan from {{$labels.src_ip}}"
```

#### 3. Root Login Attempt
```yaml
- alert: RootLoginAttempt
  expr: count_over_time({application="opnsense"} |= "root" |= "Failed" [5m]) > 0
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "Root login attempt detected"
```

#### 4. Unusual Outbound Traffic
```yaml
- alert: UnusualOutboundTraffic
  expr: rate({application="opnsense"} |= "out" [5m]) > 1000
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Unusual outbound traffic pattern"
```

---

## Best Practices

### 1. Dashboard Refresh Rates
- Real-time monitoring: 10-30 seconds
- Historical analysis: 1-5 minutes
- Compliance reports: Manual refresh

### 2. Time Range Recommendations
- Security monitoring: Last 6-12 hours
- Threat hunting: Last 24-48 hours
- Forensics: Custom range as needed

### 3. Query Optimization
- Use specific label matchers
- Limit time ranges when possible
- Use `split_queries_by_interval` for large ranges
- Cache frequently used queries

### 4. Alert Tuning
- Start with high thresholds
- Adjust based on baseline activity
- Use time-based conditions (office hours vs after-hours)
- Implement alert fatigue prevention

---

## Implementation Steps

1. **Configure OPNsense Syslog**:
   - Go to System → Settings → Logging / Targets
   - Add remote syslog: 192.168.0.36:1514 (TCP)
   - Enable all log categories

2. **Import Dashboards to Grafana**:
   - The dashboards are auto-provisioned via Terraform
   - Access at: http://grafana.home

3. **Customize for Your Environment**:
   - Adjust IP ranges in queries
   - Modify thresholds based on your traffic
   - Add custom labels and annotations

4. **Set Up Alerts**:
   - Configure notification channels
   - Create alert rules based on examples
   - Test alert delivery

5. **Regular Review**:
   - Weekly: Review top threats
   - Monthly: Analyze patterns and trends
   - Quarterly: Audit and optimize rules

---

## Troubleshooting

### No Data in Dashboards
1. Verify OPNsense is sending logs: `kubectl logs -n monitoring -l app=promtail | grep opnsense`
2. Check Loki ingestion: `kubectl logs -n monitoring -l app=loki`
3. Test query in Explore: `{application="opnsense"}`

### Slow Query Performance
1. Reduce time range
2. Add more specific label filters
3. Increase Loki resources if needed
4. Use query splitting for large ranges

### Missing Log Fields
1. Verify syslog format matches queries
2. Check regex patterns in queries
3. Adjust label extractors as needed

---

## Additional Resources

- **LogQL Documentation**: https://grafana.com/docs/loki/latest/logql/
- **OPNsense Logging**: https://docs.opnsense.org/manual/logging.html
- **Grafana Dashboards**: https://grafana.com/grafana/dashboards/

---

*Created: January 2026*
*Version: 1.0*

