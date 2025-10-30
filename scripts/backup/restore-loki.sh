#!/bin/sh

set -e

echo "🔄 Starting Loki data restore process..."

# Check if backup path is provided
if [ -z "$1" ]; then
    echo "❌ Error: Backup path not provided"
    echo "Usage: $0 <backup-path>"
    echo "Example: $0 /backup/data/20241030_120000"
    exit 1
fi

BACKUP_PATH="$1"
LOKI_BACKUP_PATH="${BACKUP_PATH}/persistent-data/loki"

# Validate backup path
if [ ! -d "$LOKI_BACKUP_PATH" ]; then
    echo "❌ Error: Loki backup path not found: $LOKI_BACKUP_PATH"
    exit 1
fi

echo "📁 Restoring from: $LOKI_BACKUP_PATH"

# Install kubectl if not available
if ! command -v kubectl >/dev/null 2>&1; then
    echo "📦 Installing kubectl..."
    apk add --no-cache curl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
fi

# Check if monitoring namespace exists
if ! kubectl get namespace monitoring >/dev/null 2>&1; then
    echo "❌ Error: Monitoring namespace not found. Please deploy the monitoring stack first."
    exit 1
fi

# Check if backup file exists
if [ ! -f "$LOKI_BACKUP_PATH/loki-data.tar.gz" ]; then
    echo "❌ Error: Loki backup file not found: $LOKI_BACKUP_PATH/loki-data.tar.gz"
    exit 1
fi

# Get Loki pod name
LOKI_POD=$(kubectl get pods -n monitoring -l app=loki -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$LOKI_POD" ] || [ "$LOKI_POD" = "null" ]; then
    echo "❌ Error: Loki pod not found or not running"
    exit 1
fi

echo "📱 Found Loki pod: $LOKI_POD"

# Stop Loki temporarily for safe restore
echo "⏸️  Scaling down Loki deployment..."
kubectl scale deployment loki -n monitoring --replicas=0
echo "⏳ Waiting for pod to terminate..."
kubectl wait --for=delete pod -l app=loki -n monitoring --timeout=60s || echo "Pod may still be terminating"

# Wait a bit more to ensure clean shutdown
sleep 10

# Scale back up
echo "🔄 Scaling up Loki deployment..."
kubectl scale deployment loki -n monitoring --replicas=1

# Wait for new pod to be ready
echo "⏳ Waiting for Loki pod to be ready..."
kubectl wait --for=condition=ready pod -l app=loki -n monitoring --timeout=120s

# Get new pod name
LOKI_POD=$(kubectl get pods -n monitoring -l app=loki -o jsonpath='{.items[0].metadata.name}')
echo "📱 New Loki pod: $LOKI_POD"

# Stop Loki process for restore
echo "⏸️  Stopping Loki process for restore..."
kubectl exec -n monitoring "$LOKI_POD" -- sh -c 'pkill -f "loki" || true'
sleep 5

# Restore data
echo "📦 Restoring Loki data..."

# Copy backup file to pod
kubectl cp "$LOKI_BACKUP_PATH/loki-data.tar.gz" "monitoring/$LOKI_POD:/tmp/loki-data.tar.gz"

kubectl exec -n monitoring "$LOKI_POD" -- sh -c '
    # Backup current data directory
    if [ -d /loki ]; then
        mv /loki /loki.backup.$(date +%s) || true
    fi
    
    # Create new loki directory
    mkdir -p /loki
    
    # Extract backup
    cd /tmp
    tar -xzf loki-data.tar.gz
    
    # Move data to proper location
    if [ -d /tmp/loki ]; then
        cp -r /tmp/loki/* /loki/ 2>/dev/null || true
    fi
    
    # Set proper ownership and permissions
    chown -R 10001:10001 /loki 2>/dev/null || true
    chmod -R 755 /loki
    
    # Clean up
    rm -rf /tmp/loki-data.tar.gz /tmp/loki
    
    echo "Data restored successfully"
'

echo "✅ Loki data restored"

# Restart Loki deployment to pick up restored data
echo "🔄 Restarting Loki deployment..."
kubectl rollout restart deployment loki -n monitoring
kubectl rollout status deployment loki -n monitoring --timeout=120s

# Verify restore
echo "🔍 Verifying restore..."
sleep 15

# Check if Loki is responding
LOKI_POD=$(kubectl get pods -n monitoring -l app=loki -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n monitoring "$LOKI_POD" -- sh -c 'ls -la /loki' >/dev/null 2>&1; then
    echo "✅ Loki data directory verified"
    
    # Show data size
    DATA_SIZE=$(kubectl exec -n monitoring "$LOKI_POD" -- sh -c 'du -sh /loki | cut -f1' 2>/dev/null || echo "N/A")
    echo "📊 Restored data size: ${DATA_SIZE}"
    
    # Check if Loki API is responding
    echo "🌐 Testing Loki API..."
    sleep 10
    if kubectl exec -n monitoring "$LOKI_POD" -- sh -c 'curl -s http://localhost:3100/ready' >/dev/null 2>&1; then
        echo "✅ Loki API is responding"
        
        # Check labels availability
        LABELS_COUNT=$(kubectl exec -n monitoring "$LOKI_POD" -- sh -c 'curl -s "http://localhost:3100/loki/api/v1/labels" | grep -o "\"[^\"]*\"" | wc -l' 2>/dev/null || echo "0")
        echo "📊 Available labels: ${LABELS_COUNT}"
    else
        echo "⚠️  Loki API not responding yet (may need more time to start)"
    fi
    
    # Show restore summary
    echo ""
    echo "📋 Restore Summary"
    echo "=================="
    echo "Backup Source: $LOKI_BACKUP_PATH"
    echo "Loki Pod: $LOKI_POD"
    echo "Data Size: ${DATA_SIZE}"
    echo ""
    echo "✅ Loki restore completed successfully!"
    echo "🌐 Access Loki at: http://$(kubectl get ingress loki -n monitoring -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo 'loki.local')"
    echo "📝 Log retention: Check Loki configuration for retention settings"
else
    echo "❌ Error: Could not verify restored data directory"
    exit 1
fi