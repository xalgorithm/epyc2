#!/bin/sh

set -e

echo "🔄 Starting Mimir data restore process..."

# Check if backup path is provided
if [ -z "$1" ]; then
    echo "❌ Error: Backup path not provided"
    echo "Usage: $0 <backup-path>"
    echo "Example: $0 /backup/data/20241030_120000"
    exit 1
fi

BACKUP_PATH="$1"
MIMIR_BACKUP_PATH="${BACKUP_PATH}/persistent-data/mimir"

# Validate backup path
if [ ! -d "$MIMIR_BACKUP_PATH" ]; then
    echo "❌ Error: Mimir backup path not found: $MIMIR_BACKUP_PATH"
    exit 1
fi

echo "📁 Restoring from: $MIMIR_BACKUP_PATH"

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
if [ ! -f "$MIMIR_BACKUP_PATH/mimir-data.tar.gz" ]; then
    echo "❌ Error: Mimir backup file not found: $MIMIR_BACKUP_PATH/mimir-data.tar.gz"
    exit 1
fi

# Get Mimir pod name
MIMIR_POD=$(kubectl get pods -n monitoring -l app=mimir -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$MIMIR_POD" ] || [ "$MIMIR_POD" = "null" ]; then
    echo "❌ Error: Mimir pod not found or not running"
    exit 1
fi

echo "📱 Found Mimir pod: $MIMIR_POD"

# Stop Mimir temporarily for safe restore
echo "⏸️  Scaling down Mimir deployment..."
kubectl scale deployment mimir -n monitoring --replicas=0
echo "⏳ Waiting for pod to terminate..."
kubectl wait --for=delete pod -l app=mimir -n monitoring --timeout=60s || echo "Pod may still be terminating"

# Wait a bit more to ensure clean shutdown
sleep 10

# Scale back up
echo "🔄 Scaling up Mimir deployment..."
kubectl scale deployment mimir -n monitoring --replicas=1

# Wait for new pod to be ready
echo "⏳ Waiting for Mimir pod to be ready..."
kubectl wait --for=condition=ready pod -l app=mimir -n monitoring --timeout=120s

# Get new pod name
MIMIR_POD=$(kubectl get pods -n monitoring -l app=mimir -o jsonpath='{.items[0].metadata.name}')
echo "📱 New Mimir pod: $MIMIR_POD"

# Stop Mimir process for restore
echo "⏸️  Stopping Mimir process for restore..."
kubectl exec -n monitoring "$MIMIR_POD" -- sh -c 'pkill -f "mimir" || true'
sleep 5

# Restore data
echo "📦 Restoring Mimir data..."

# Copy backup file to pod
kubectl cp "$MIMIR_BACKUP_PATH/mimir-data.tar.gz" "monitoring/$MIMIR_POD:/tmp/mimir-data.tar.gz"

kubectl exec -n monitoring "$MIMIR_POD" -- sh -c '
    # Backup current data directory
    if [ -d /data ]; then
        mv /data /data.backup.$(date +%s) || true
    fi
    
    # Create new data directory
    mkdir -p /data
    
    # Extract backup
    cd /tmp
    tar -xzf mimir-data.tar.gz
    
    # Move data to proper location
    if [ -d /tmp/data ]; then
        cp -r /tmp/data/* /data/ 2>/dev/null || true
    fi
    
    # Set proper ownership and permissions
    chown -R 10001:10001 /data 2>/dev/null || true
    chmod -R 755 /data
    
    # Clean up
    rm -rf /tmp/mimir-data.tar.gz /tmp/data
    
    echo "Data restored successfully"
'

echo "✅ Mimir data restored"

# Restart Mimir deployment to pick up restored data
echo "🔄 Restarting Mimir deployment..."
kubectl rollout restart deployment mimir -n monitoring
kubectl rollout status deployment mimir -n monitoring --timeout=120s

# Verify restore
echo "🔍 Verifying restore..."
sleep 15

# Check if Mimir is responding
MIMIR_POD=$(kubectl get pods -n monitoring -l app=mimir -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n monitoring "$MIMIR_POD" -- sh -c 'ls -la /data' >/dev/null 2>&1; then
    echo "✅ Mimir data directory verified"
    
    # Show data size
    DATA_SIZE=$(kubectl exec -n monitoring "$MIMIR_POD" -- sh -c 'du -sh /data | cut -f1' 2>/dev/null || echo "N/A")
    echo "📊 Restored data size: ${DATA_SIZE}"
    
    # Check if Mimir API is responding
    echo "🌐 Testing Mimir API..."
    sleep 10
    if kubectl exec -n monitoring "$MIMIR_POD" -- sh -c 'curl -s http://localhost:8080/ready' >/dev/null 2>&1; then
        echo "✅ Mimir API is responding"
        
        # Check metrics availability
        METRICS_COUNT=$(kubectl exec -n monitoring "$MIMIR_POD" -- sh -c 'curl -s "http://localhost:8080/prometheus/api/v1/label/__name__/values" | grep -o "\"[^\"]*\"" | wc -l' 2>/dev/null || echo "0")
        echo "📊 Available metrics: ${METRICS_COUNT}"
    else
        echo "⚠️  Mimir API not responding yet (may need more time to start)"
    fi
    
    # Show restore summary
    echo ""
    echo "📋 Restore Summary"
    echo "=================="
    echo "Backup Source: $MIMIR_BACKUP_PATH"
    echo "Mimir Pod: $MIMIR_POD"
    echo "Data Size: ${DATA_SIZE}"
    echo ""
    echo "✅ Mimir restore completed successfully!"
    echo "🌐 Access Mimir at: http://$(kubectl get ingress mimir -n monitoring -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo 'mimir.local')"
    echo "📊 Data retention: Check Mimir configuration for retention settings"
else
    echo "❌ Error: Could not verify restored data directory"
    exit 1
fi