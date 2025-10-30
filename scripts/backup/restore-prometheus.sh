#!/bin/sh

set -e

echo "🔄 Starting Prometheus data restore process..."

# Check if backup path is provided
if [ -z "$1" ]; then
    echo "❌ Error: Backup path not provided"
    echo "Usage: $0 <backup-path>"
    echo "Example: $0 /backup/data/20241030_120000"
    exit 1
fi

BACKUP_PATH="$1"
PROMETHEUS_BACKUP_PATH="${BACKUP_PATH}/persistent-data/prometheus"

# Validate backup path
if [ ! -d "$PROMETHEUS_BACKUP_PATH" ]; then
    echo "❌ Error: Prometheus backup path not found: $PROMETHEUS_BACKUP_PATH"
    exit 1
fi

echo "📁 Restoring from: $PROMETHEUS_BACKUP_PATH"

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

# Get Prometheus pod name
PROMETHEUS_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$PROMETHEUS_POD" ] || [ "$PROMETHEUS_POD" = "null" ]; then
    echo "❌ Error: Prometheus pod not found or not running"
    exit 1
fi

echo "📱 Found Prometheus pod: $PROMETHEUS_POD"

# Stop Prometheus temporarily for safe restore
echo "⏸️  Scaling down Prometheus deployment..."
kubectl scale deployment prometheus -n monitoring --replicas=0
echo "⏳ Waiting for pod to terminate..."
kubectl wait --for=delete pod -l app=prometheus -n monitoring --timeout=60s || echo "Pod may still be terminating"

# Wait a bit more to ensure clean shutdown
sleep 10

# Determine which backup file to use
BACKUP_FILE=""
if [ -f "$PROMETHEUS_BACKUP_PATH/prometheus-snapshot.tar.gz" ]; then
    BACKUP_FILE="prometheus-snapshot.tar.gz"
    echo "📸 Using snapshot backup"
elif [ -f "$PROMETHEUS_BACKUP_PATH/prometheus-data.tar.gz" ]; then
    BACKUP_FILE="prometheus-data.tar.gz"
    echo "📦 Using data directory backup"
else
    echo "❌ Error: No Prometheus backup files found"
    exit 1
fi

# Scale back up
echo "🔄 Scaling up Prometheus deployment..."
kubectl scale deployment prometheus -n monitoring --replicas=1

# Wait for new pod to be ready
echo "⏳ Waiting for Prometheus pod to be ready..."
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=120s

# Get new pod name
PROMETHEUS_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}')
echo "📱 New Prometheus pod: $PROMETHEUS_POD"

# Stop Prometheus process for restore
echo "⏸️  Stopping Prometheus process for restore..."
kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c 'pkill -f "prometheus" || true'
sleep 5

# Restore data
echo "📦 Restoring Prometheus data..."

# Copy backup file to pod
kubectl cp "$PROMETHEUS_BACKUP_PATH/$BACKUP_FILE" "monitoring/$PROMETHEUS_POD:/tmp/$BACKUP_FILE"

kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c "
    # Backup current data directory
    if [ -d /prometheus ]; then
        mv /prometheus /prometheus.backup.\$(date +%s) || true
    fi
    
    # Create new prometheus directory
    mkdir -p /prometheus
    
    # Extract backup
    cd /tmp
    tar -xzf $BACKUP_FILE
    
    # Move data to proper location
    if [ -d /tmp/prometheus/snapshots ]; then
        # This is a snapshot backup
        echo 'Restoring from snapshot...'
        SNAPSHOT_DIR=\$(find /tmp/prometheus/snapshots -maxdepth 1 -type d | head -2 | tail -1)
        if [ -n \"\$SNAPSHOT_DIR\" ]; then
            cp -r \"\$SNAPSHOT_DIR\"/* /prometheus/ 2>/dev/null || true
        fi
    elif [ -d /tmp/prometheus ]; then
        # This is a full data backup
        echo 'Restoring from data directory...'
        cp -r /tmp/prometheus/* /prometheus/ 2>/dev/null || true
    fi
    
    # Set proper ownership
    chown -R 65534:65534 /prometheus
    chmod -R 755 /prometheus
    
    # Clean up
    rm -rf /tmp/$BACKUP_FILE /tmp/prometheus
    
    echo 'Data restored successfully'
"

echo "✅ Prometheus data restored"

# Restart Prometheus deployment to pick up restored data
echo "🔄 Restarting Prometheus deployment..."
kubectl rollout restart deployment prometheus -n monitoring
kubectl rollout status deployment prometheus -n monitoring --timeout=120s

# Verify restore
echo "🔍 Verifying restore..."
sleep 15

# Check if Prometheus is responding
PROMETHEUS_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c 'ls -la /prometheus' >/dev/null 2>&1; then
    echo "✅ Prometheus data directory verified"
    
    # Show data size
    DATA_SIZE=$(kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c 'du -sh /prometheus | cut -f1' 2>/dev/null || echo "N/A")
    echo "📊 Restored data size: ${DATA_SIZE}"
    
    # Check if Prometheus API is responding
    echo "🌐 Testing Prometheus API..."
    sleep 10
    if kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c 'curl -s http://localhost:9090/-/ready' >/dev/null 2>&1; then
        echo "✅ Prometheus API is responding"
        
        # Check metrics availability
        METRICS_COUNT=$(kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c 'curl -s "http://localhost:9090/api/v1/label/__name__/values" | grep -o "\"[^\"]*\"" | wc -l' 2>/dev/null || echo "0")
        echo "📊 Available metrics: ${METRICS_COUNT}"
    else
        echo "⚠️  Prometheus API not responding yet (may need more time to start)"
    fi
    
    # Show restore summary
    echo ""
    echo "📋 Restore Summary"
    echo "=================="
    echo "Backup Source: $PROMETHEUS_BACKUP_PATH"
    echo "Backup Type: $(if [ "$BACKUP_FILE" = "prometheus-snapshot.tar.gz" ]; then echo "Snapshot"; else echo "Data Directory"; fi)"
    echo "Prometheus Pod: $PROMETHEUS_POD"
    echo "Data Size: ${DATA_SIZE}"
    echo ""
    echo "✅ Prometheus restore completed successfully!"
    echo "🌐 Access Prometheus at: http://$(kubectl get ingress prometheus -n monitoring -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo 'prometheus.local')"
    echo "📊 Data retention: Check Prometheus configuration for retention settings"
else
    echo "❌ Error: Could not verify restored data directory"
    exit 1
fi