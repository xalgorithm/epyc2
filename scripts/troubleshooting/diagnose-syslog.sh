#!/bin/bash
# Diagnose syslog-ng and OPNsense log reception issues

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_header "OPNsense Syslog Reception Diagnostics"

# Check if syslog-ng pod exists and is running
print_header "1. Checking syslog-ng Pod Status"
if kubectl get pods -n monitoring -l app=syslog-ng &>/dev/null; then
    POD_STATUS=$(kubectl get pods -n monitoring -l app=syslog-ng -o jsonpath='{.items[0].status.phase}')
    POD_NAME=$(kubectl get pods -n monitoring -l app=syslog-ng -o jsonpath='{.items[0].metadata.name}')
    
    if [ "$POD_STATUS" == "Running" ]; then
        print_success "syslog-ng pod is running: $POD_NAME"
    else
        print_error "syslog-ng pod is not running. Status: $POD_STATUS"
        kubectl describe pod -n monitoring -l app=syslog-ng
        exit 1
    fi
else
    print_error "syslog-ng pod not found"
    exit 1
fi

# Check pod logs for errors
print_header "2. Checking syslog-ng Logs"
echo "Recent logs from syslog-ng:"
kubectl logs -n monitoring $POD_NAME --tail=20

# Check if there are any errors
if kubectl logs -n monitoring $POD_NAME --tail=50 | grep -i "error" &>/dev/null; then
    print_warning "Errors found in syslog-ng logs"
    kubectl logs -n monitoring $POD_NAME --tail=50 | grep -i "error"
else
    print_success "No errors found in recent logs"
fi

# Check service and LoadBalancer IP
print_header "3. Checking syslog-ng Service"
if kubectl get svc syslog-ng -n monitoring &>/dev/null; then
    EXTERNAL_IP=$(kubectl get svc syslog-ng -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    SERVICE_TYPE=$(kubectl get svc syslog-ng -n monitoring -o jsonpath='{.spec.type}')
    
    echo "Service Type: $SERVICE_TYPE"
    if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" == "<pending>" ]; then
        print_error "LoadBalancer IP is not assigned!"
        echo "This usually means MetalLB is not working or no IPs are available in the pool"
        kubectl describe svc syslog-ng -n monitoring
        exit 1
    else
        print_success "LoadBalancer IP assigned: $EXTERNAL_IP"
        echo "OPNsense should be configured to send logs to: $EXTERNAL_IP:514"
    fi
else
    print_error "syslog-ng service not found"
    exit 1
fi

# Check if ports are exposed
print_header "4. Checking Port Configuration"
UDP_PORT=$(kubectl get svc syslog-ng -n monitoring -o jsonpath='{.spec.ports[?(@.protocol=="UDP")].port}')
TCP_PORT=$(kubectl get svc syslog-ng -n monitoring -o jsonpath='{.spec.ports[?(@.protocol=="TCP")].port}')

if [ -n "$UDP_PORT" ]; then
    print_success "UDP port exposed: $UDP_PORT"
else
    print_error "UDP port not exposed"
fi

if [ -n "$TCP_PORT" ]; then
    print_success "TCP port exposed: $TCP_PORT"
else
    print_error "TCP port not exposed"
fi

# Test if syslog-ng is listening inside the pod
print_header "5. Testing if syslog-ng is Listening"
echo "Checking if syslog-ng process is running and listening..."
if kubectl exec -n monitoring $POD_NAME -- ps aux | grep -v grep | grep syslog-ng &>/dev/null; then
    print_success "syslog-ng process is running"
    kubectl exec -n monitoring $POD_NAME -- ps aux | grep -v grep | grep syslog-ng
else
    print_error "syslog-ng process not found"
fi

# Check if Loki is reachable from syslog-ng
print_header "6. Checking Loki Connectivity"
echo "Testing if syslog-ng can reach Loki..."
if kubectl exec -n monitoring $POD_NAME -- wget -qO- --timeout=5 http://loki.monitoring.svc.cluster.local:3100/ready 2>/dev/null | grep -q "ready"; then
    print_success "Loki is reachable from syslog-ng"
else
    print_warning "Cannot reach Loki or Loki is not ready"
    echo "Checking Loki status..."
    kubectl get pods -n monitoring -l app=loki
fi

# Test sending a message to syslog-ng
print_header "7. Testing Log Reception"
echo "Sending test message to syslog-ng from within cluster..."

# Create a test pod to send a message
cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: syslog-test
  namespace: monitoring
spec:
  containers:
  - name: netcat
    image: busybox:latest
    command: ['sh', '-c', 'sleep 3600']
  restartPolicy: Never
EOF

echo "Waiting for test pod to be ready..."
kubectl wait --for=condition=Ready pod/syslog-test -n monitoring --timeout=60s &>/dev/null || true

# Send test message via UDP
echo "Sending UDP test message..."
kubectl exec -n monitoring syslog-test -- sh -c "echo '<134>$(date --rfc-3339=seconds) test-host syslog-test: Test message from cluster' | nc -u -w1 syslog-ng.monitoring.svc.cluster.local 514" 2>/dev/null || print_warning "Failed to send UDP message"

# Send test message via TCP
echo "Sending TCP test message..."
kubectl exec -n monitoring syslog-test -- sh -c "echo '<134>$(date --rfc-3339=seconds) test-host syslog-test: Test message from cluster TCP' | nc -w1 syslog-ng.monitoring.svc.cluster.local 514" 2>/dev/null || print_warning "Failed to send TCP message"

# Check if messages appear in logs
echo "Waiting 3 seconds for messages to be processed..."
sleep 3

echo "Checking syslog-ng logs for test messages..."
if kubectl logs -n monitoring $POD_NAME --tail=50 | grep -q "syslog-test"; then
    print_success "Test messages appear in syslog-ng logs!"
else
    print_warning "Test messages NOT found in syslog-ng logs"
    echo "This suggests syslog-ng might not be receiving or processing messages correctly"
fi

# Clean up test pod
kubectl delete pod syslog-test -n monitoring --ignore-not-found=true &>/dev/null

# Check syslog-ng configuration
print_header "8. Checking syslog-ng Configuration"
echo "Current syslog-ng configuration:"
kubectl get configmap syslog-ng-config -n monitoring -o jsonpath='{.data.syslog-ng\.conf}' | head -n 30

# Query Loki for recent logs
print_header "9. Querying Loki for OPNsense Logs"
LOKI_POD=$(kubectl get pod -n monitoring -l app=loki -o name | head -1)
if [ -n "$LOKI_POD" ]; then
    echo "Checking if any logs with application=opnsense exist in Loki..."
    QUERY_RESULT=$(kubectl exec -n monitoring $LOKI_POD -- wget -qO- 'http://localhost:3100/loki/api/v1/query?query={application="opnsense"}' 2>/dev/null || echo "")
    
    if echo "$QUERY_RESULT" | grep -q '"status":"success"'; then
        LOG_COUNT=$(echo "$QUERY_RESULT" | grep -o '"result":\[.*\]' | wc -c)
        if [ "$LOG_COUNT" -gt 20 ]; then
            print_success "OPNsense logs found in Loki!"
            echo "$QUERY_RESULT" | jq '.data.result[] | .values[] | .[1]' 2>/dev/null | head -n 5
        else
            print_warning "No OPNsense logs found in Loki"
        fi
    else
        print_warning "Unable to query Loki"
    fi
else
    print_warning "Loki pod not found"
fi

# Network connectivity test
print_header "10. Network Connectivity Recommendations"
echo "To test from OPNsense, run these commands in OPNsense shell:"
echo ""
echo "# Test UDP connectivity:"
echo "echo '<134>1 $(date -u +%Y-%m-%dT%H:%M:%S.%3NZ) opnsense test - - - Test UDP message' | nc -u -w1 $EXTERNAL_IP 514"
echo ""
echo "# Test TCP connectivity:"
echo "echo '<134>1 $(date -u +%Y-%m-%dT%H:%M:%S.%3NZ) opnsense test - - - Test TCP message' | nc -w1 $EXTERNAL_IP 514"
echo ""
echo "# Check if port is reachable:"
echo "nc -zv $EXTERNAL_IP 514"

print_header "Summary and Next Steps"
echo "1. Ensure OPNsense is configured to send logs to: $EXTERNAL_IP:514"
echo "2. In OPNsense: System → Settings → Logging / Targets"
echo "3. Add a remote log target with:"
echo "   - Transport: UDP(4) or TCP(6)"
echo "   - Hostname: $EXTERNAL_IP"
echo "   - Port: 514"
echo "   - Level: Informational"
echo ""
echo "4. Check OPNsense firewall rules allow outbound traffic to $EXTERNAL_IP:514"
echo "5. Monitor logs: kubectl logs -n monitoring -l app=syslog-ng -f"
echo ""
echo "For more details, see: docs/OPNSENSE_LOGGING.md"

