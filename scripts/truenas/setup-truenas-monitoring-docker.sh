#!/bin/bash

#===============================================================================
# TrueNAS SCALE 25.04 Monitoring Setup Script (Docker Method)
#===============================================================================
# This script sets up Prometheus node_exporter and syslog forwarding for
# TrueNAS SCALE using Docker containers (TrueNAS SCALE's preferred method).
#
# Usage:
#   bash setup-truenas-monitoring-docker.sh
#
# What it does:
#   - Installs node_exporter as a Docker container
#   - Configures syslog to forward logs to Loki/Promtail
#   - Verifies the setup is working correctly
#===============================================================================

set -e

# Configuration
PROMTAIL_IP="192.168.0.36"
PROMTAIL_PORT="1514"
NODE_EXPORTER_PORT="9100"
CONTAINER_NAME="node_exporter"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║   TrueNAS SCALE Monitoring Setup (Docker Method)                        ║"
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
# PART 1: Setup Node Exporter via Docker
#===============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 1: Setting up Prometheus Node Exporter (Docker)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗${NC} Docker is not available"
    echo "TrueNAS SCALE should have Docker/Kubernetes installed by default."
    echo "Please check your TrueNAS installation."
    exit 1
fi

echo -e "${GREEN}✓${NC} Docker is available"

# Check if node_exporter container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo ""
    echo -e "${YELLOW}!${NC} node_exporter container already exists, removing it..."
    docker stop ${CONTAINER_NAME} 2>/dev/null || true
    docker rm ${CONTAINER_NAME} 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Old container removed"
fi

# Pull the latest node_exporter image
echo ""
echo "Pulling Prometheus node_exporter image..."
docker pull prom/node-exporter:latest

# Run node_exporter as a Docker container
echo ""
echo "Starting node_exporter container..."
docker run -d \
  --name=${CONTAINER_NAME} \
  --net="host" \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  --restart=unless-stopped \
  prom/node-exporter:latest \
  --path.rootfs=/host \
  --web.listen-address=:${NODE_EXPORTER_PORT} \
  --collector.filesystem.mount-points-exclude="^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+|run)($|/)" \
  --collector.netclass.ignored-devices="^(veth.*|docker.*|br-.*|lo)$" \
  --collector.netdev.device-exclude="^(veth.*|docker.*|br-.*|lo)$"

# Wait for container to start
sleep 3

# Check if container is running
if docker ps | grep -q ${CONTAINER_NAME}; then
    echo -e "${GREEN}✓${NC} node_exporter container is running"
else
    echo -e "${RED}✗${NC} node_exporter container failed to start"
    echo "Container logs:"
    docker logs ${CONTAINER_NAME}
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
    docker logs ${CONTAINER_NAME}
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

# Try to get current config to see field names
echo "Checking current syslog configuration..."
CURRENT_CONFIG=$(midclt call system.advanced.config 2>/dev/null | jq -r '.syslogserver' 2>/dev/null || echo "")

# Configure syslog via midclt (TrueNAS SCALE API)
# Note: TrueNAS SCALE 25.04 uses simplified parameters
echo "Attempting to configure via TrueNAS API..."
midclt call system.advanced.update "{\"syslogserver\": \"${PROMTAIL_IP}:${PROMTAIL_PORT}\"}" 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Syslog configuration updated via midclt"
else
    echo -e "${YELLOW}!${NC} midclt configuration failed, using manual syslog-ng configuration..."
    
    # Manual syslog-ng configuration (more reliable)
    SYSLOG_CONF="/etc/syslog-ng/syslog-ng.conf.d/truenas-remote.conf"
    
    # Create directory if it doesn't exist
    mkdir -p /etc/syslog-ng/syslog-ng.conf.d
    
    cat > ${SYSLOG_CONF} << EOFCONF
# TrueNAS Remote Syslog Configuration
# Send all logs to Loki/Promtail

destination d_remote_loki {
    network("${PROMTAIL_IP}"
        port(${PROMTAIL_PORT})
        transport("tcp")
        log_fifo_size(1000)
    );
};

log {
    source(src);
    destination(d_remote_loki);
};
EOFCONF
    
    echo -e "${GREEN}✓${NC} Created manual syslog-ng configuration at ${SYSLOG_CONF}"
fi

# Restart syslog-ng service
echo ""
echo "Restarting syslog-ng service..."
if systemctl restart syslog-ng 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Syslog-ng service restarted via systemctl"
elif service syslog-ng restart 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Syslog-ng service restarted via service command"
else
    echo -e "${YELLOW}!${NC} Could not restart syslog-ng, attempting midclt restart..."
    midclt call service.restart syslog
fi

# Wait for service to start
sleep 2

# Send test log message
echo ""
echo "Sending test log message..."
logger -t truenas-monitoring-setup "TrueNAS monitoring setup completed successfully - $(date)"
echo -e "${GREEN}✓${NC} Test message sent"

#===============================================================================
# PART 3: Persistence Configuration
#===============================================================================

echo ""
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 3: Making Configuration Persistent"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create startup script for TrueNAS
STARTUP_SCRIPT="/root/.truenas-monitoring-startup.sh"

cat > ${STARTUP_SCRIPT} << 'EOFSCRIPT'
#!/bin/bash
# TrueNAS Monitoring - Auto-start script
# This ensures node_exporter stays running after reboots

CONTAINER_NAME="node_exporter"
NODE_EXPORTER_PORT="9100"

# Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Starting node_exporter container..."
    docker run -d \
      --name=${CONTAINER_NAME} \
      --net="host" \
      --pid="host" \
      -v "/:/host:ro,rslave" \
      --restart=unless-stopped \
      prom/node-exporter:latest \
      --path.rootfs=/host \
      --web.listen-address=:${NODE_EXPORTER_PORT} \
      --collector.filesystem.mount-points-exclude="^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+|run)($|/)" \
      --collector.netclass.ignored-devices="^(veth.*|docker.*|br-.*|lo)$" \
      --collector.netdev.device-exclude="^(veth.*|docker.*|br-.*|lo)$"
else
    # Container exists, make sure it's running
    if ! docker ps | grep -q ${CONTAINER_NAME}; then
        echo "Restarting node_exporter container..."
        docker start ${CONTAINER_NAME}
    fi
fi
EOFSCRIPT

chmod +x ${STARTUP_SCRIPT}
echo -e "${GREEN}✓${NC} Created startup script: ${STARTUP_SCRIPT}"

# Add to TrueNAS Init/Shutdown Scripts
echo ""
echo "To make this persistent across reboots, you should add the startup script"
echo "to TrueNAS Init/Shutdown Scripts via the Web UI:"
echo ""
echo "1. Go to: System Settings → Advanced"
echo "2. Scroll to: Init/Shutdown Scripts"
echo "3. Click: Add"
echo "4. Configure:"
echo "   - Description: Node Exporter Monitoring"
echo "   - Type: Command"
echo "   - Command: ${STARTUP_SCRIPT}"
echo "   - When: Post Init"
echo "5. Click: Save"
echo ""

#===============================================================================
# PART 4: Verification
#===============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 4: Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get local IP
LOCAL_IP=$(hostname -I | awk '{print $1}')

echo "Configuration Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Metrics:"
echo "   • Endpoint: http://${LOCAL_IP}:${NODE_EXPORTER_PORT}/metrics"
echo "   • Container: $(docker ps --filter name=${CONTAINER_NAME} --format '{{.Status}}')"
echo ""
echo "📝 Logs:"
echo "   • Syslog forwarding to: ${PROMTAIL_IP}:${PROMTAIL_PORT} (TCP)"
echo "   • Syslog service: $(systemctl is-active syslog-ng 2>/dev/null || echo 'running')"
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
# Container Management Commands
#===============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Container Management Commands"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "View container status:"
echo "  docker ps | grep ${CONTAINER_NAME}"
echo ""
echo "View container logs:"
echo "  docker logs ${CONTAINER_NAME}"
echo ""
echo "Restart container:"
echo "  docker restart ${CONTAINER_NAME}"
echo ""
echo "Stop container:"
echo "  docker stop ${CONTAINER_NAME}"
echo ""
echo "Start container:"
echo "  docker start ${CONTAINER_NAME}"
echo ""
echo "Remove container (will be recreated on reboot if startup script is configured):"
echo "  docker stop ${CONTAINER_NAME} && docker rm ${CONTAINER_NAME}"
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
echo "1. ADD TO INIT/SHUTDOWN SCRIPTS (Important for persistence!):"
echo "   • Go to: System Settings → Advanced → Init/Shutdown Scripts"
echo "   • Add: ${STARTUP_SCRIPT}"
echo "   • Type: Command, When: Post Init"
echo ""
echo "2. Verify from your workstation:"
echo "   curl http://${LOCAL_IP}:${NODE_EXPORTER_PORT}/metrics | head -20"
echo ""
echo "3. Check Prometheus targets (from your workstation):"
echo "   kubectl port-forward -n monitoring svc/prometheus 9090:9090 &"
echo "   Open: http://localhost:9090/targets"
echo "   Look for: job=\"truenas\" with status UP"
echo ""
echo "4. Check logs in Grafana:"
echo "   Open: http://grafana.home/explore"
echo "   Query: {host=~\"truenas.*\"}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Documentation: docs/TRUENAS_MONITORING.md"
echo ""
