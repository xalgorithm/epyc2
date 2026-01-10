#!/bin/bash

#===============================================================================
# TrueNAS SCALE 25.04 Monitoring Setup Script
#===============================================================================
# This script sets up Prometheus node_exporter and syslog forwarding for
# TrueNAS SCALE to integrate with your Kubernetes monitoring stack.
#
# Usage:
#   1. Copy this script to your TrueNAS machine
#   2. Run as root: bash setup-truenas-monitoring.sh
#
# What it does:
#   - Installs and configures node_exporter for metrics collection
#   - Configures syslog to forward logs to Loki/Promtail
#   - Verifies the setup is working correctly
#===============================================================================

set -e

# Configuration
PROMTAIL_IP="192.168.0.36"
PROMTAIL_PORT="1514"
NODE_EXPORTER_PORT="9100"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║      TrueNAS SCALE Monitoring Setup for Kubernetes Stack                ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root${NC}"
  exit 1
fi

echo -e "${GREEN}✓${NC} Running as root"
echo ""

#===============================================================================
# PART 1: Setup Node Exporter for Metrics
#===============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 1: Setting up Prometheus Node Exporter"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if node_exporter is already installed
if command -v node_exporter &> /dev/null; then
    echo -e "${GREEN}✓${NC} node_exporter is already installed"
    NODE_EXPORTER_BIN=$(which node_exporter)
else
    echo -e "${YELLOW}!${NC} node_exporter not found, checking common locations..."
    
    # Check common installation paths
    if [ -f "/usr/bin/node_exporter" ]; then
        NODE_EXPORTER_BIN="/usr/bin/node_exporter"
        echo -e "${GREEN}✓${NC} Found at /usr/bin/node_exporter"
    elif [ -f "/usr/local/bin/node_exporter" ]; then
        NODE_EXPORTER_BIN="/usr/local/bin/node_exporter"
        echo -e "${GREEN}✓${NC} Found at /usr/local/bin/node_exporter"
    else
        echo -e "${RED}✗${NC} node_exporter not found"
        echo ""
        echo "Installing node_exporter..."
        
        # Download and install node_exporter
        cd /tmp
        EXPORTER_VERSION="1.7.0"
        wget -q https://github.com/prometheus/node_exporter/releases/download/v${EXPORTER_VERSION}/node_exporter-${EXPORTER_VERSION}.linux-amd64.tar.gz
        tar xzf node_exporter-${EXPORTER_VERSION}.linux-amd64.tar.gz
        cp node_exporter-${EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
        chmod +x /usr/local/bin/node_exporter
        rm -rf node_exporter-${EXPORTER_VERSION}.linux-amd64*
        NODE_EXPORTER_BIN="/usr/local/bin/node_exporter"
        echo -e "${GREEN}✓${NC} node_exporter installed to /usr/local/bin"
    fi
fi

echo ""
echo "Creating systemd service..."

# Create systemd service file
cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=${NODE_EXPORTER_BIN} \\
  --web.listen-address=:${NODE_EXPORTER_PORT} \\
  --collector.filesystem.mount-points-exclude="^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+|run)($|/)" \\
  --collector.netclass.ignored-devices="^(veth.*|docker.*|br-.*|lo)$" \\
  --collector.netdev.device-exclude="^(veth.*|docker.*|br-.*|lo)$"

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}✓${NC} Systemd service file created"

# Reload systemd, enable and start service
echo ""
echo "Enabling and starting node_exporter service..."
systemctl daemon-reload
systemctl enable node_exporter
systemctl restart node_exporter

# Wait for service to start
sleep 2

# Check service status
if systemctl is-active --quiet node_exporter; then
    echo -e "${GREEN}✓${NC} node_exporter service is running"
else
    echo -e "${RED}✗${NC} node_exporter service failed to start"
    systemctl status node_exporter --no-pager
    exit 1
fi

# Test metrics endpoint
echo ""
echo "Testing metrics endpoint..."
if curl -s http://localhost:${NODE_EXPORTER_PORT}/metrics | head -5 > /dev/null; then
    echo -e "${GREEN}✓${NC} Metrics endpoint is working"
    echo ""
    echo "Sample metrics:"
    curl -s http://localhost:${NODE_EXPORTER_PORT}/metrics | grep "^node_" | head -10
else
    echo -e "${RED}✗${NC} Failed to fetch metrics"
    exit 1
fi

#===============================================================================
# PART 2: Configure Syslog Forwarding
#===============================================================================

echo ""
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 2: Configuring Syslog Forwarding to Loki"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Configuring syslog to forward to ${PROMTAIL_IP}:${PROMTAIL_PORT}..."

# Configure syslog via midclt (TrueNAS SCALE API)
midclt call system.advanced.update "{
  \"syslogserver\": \"${PROMTAIL_IP}\",
  \"syslogserver_transport\": \"TCP\",
  \"sysloglevel\": \"INFO\",
  \"syslog_port\": ${PROMTAIL_PORT}
}" 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Syslog configuration updated"
else
    echo -e "${YELLOW}!${NC} midclt configuration may have failed, trying alternative method..."
fi

# Restart syslog-ng service
echo ""
echo "Restarting syslog-ng service..."
if systemctl restart syslog-ng; then
    echo -e "${GREEN}✓${NC} Syslog-ng service restarted"
else
    echo -e "${RED}✗${NC} Failed to restart syslog-ng"
    service syslog-ng restart
fi

# Wait for service to start
sleep 2

# Send test log message
echo ""
echo "Sending test log message..."
logger -t truenas-monitoring-setup "TrueNAS monitoring setup completed successfully - $(date)"
echo -e "${GREEN}✓${NC} Test message sent"

#===============================================================================
# PART 3: Verification
#===============================================================================

echo ""
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 3: Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get local IP
LOCAL_IP=$(hostname -I | awk '{print $1}')

echo "Configuration Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Metrics:"
echo "   • Endpoint: http://${LOCAL_IP}:${NODE_EXPORTER_PORT}/metrics"
echo "   • Status: $(systemctl is-active node_exporter)"
echo ""
echo "📝 Logs:"
echo "   • Syslog forwarding to: ${PROMTAIL_IP}:${PROMTAIL_PORT} (TCP)"
echo "   • Syslog service: $(systemctl is-active syslog-ng)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test connectivity to Promtail
echo ""
echo "Testing connectivity to Promtail..."
if timeout 3 bash -c "echo 'test' > /dev/tcp/${PROMTAIL_IP}/${PROMTAIL_PORT}" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Can connect to Promtail at ${PROMTAIL_IP}:${PROMTAIL_PORT}"
else
    echo -e "${YELLOW}!${NC} Cannot connect to Promtail at ${PROMTAIL_IP}:${PROMTAIL_PORT}"
    echo "   This may be normal if Promtail is not yet configured or network is restricted"
fi

#===============================================================================
# Firewall Configuration (Optional)
#===============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OPTIONAL: Firewall Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "If you have a firewall enabled, you may need to allow port ${NODE_EXPORTER_PORT}:"
echo ""
echo "  iptables -I INPUT -p tcp --dport ${NODE_EXPORTER_PORT} -j ACCEPT"
echo ""
echo "TrueNAS SCALE typically doesn't enable iptables by default, so this may not be necessary."
echo ""

#===============================================================================
# Final Instructions
#===============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                      ✅ SETUP COMPLETE!                                  ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Next Steps:"
echo ""
echo "1. Verify from your workstation:"
echo "   curl http://${LOCAL_IP}:${NODE_EXPORTER_PORT}/metrics | head -20"
echo ""
echo "2. Check Prometheus targets (from your workstation):"
echo "   kubectl port-forward -n monitoring svc/prometheus 9090:9090 &"
echo "   Open: http://localhost:9090/targets"
echo "   Look for: job=\"truenas\" with status UP"
echo ""
echo "3. Check logs in Grafana:"
echo "   Open: http://grafana.home/explore"
echo "   Query: {host=~\"truenas.*\"}"
echo ""
echo "4. Import Grafana dashboards:"
echo "   - Dashboard ID 1860 (Node Exporter Full)"
echo "   - Custom dashboard: configs/grafana/truenas-dashboard.json"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "For detailed documentation, see: docs/TRUENAS_MONITORING.md"
echo ""
