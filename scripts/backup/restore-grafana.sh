#!/bin/sh

set -e

echo "🔄 Starting Grafana data restore process..."

# Check if backup path is provided
if [ -z "$1" ]; then
    echo "❌ Error: Backup path not provided"
    echo "Usage: $0 <backup-path>"
    echo "Example: $0 /backup/data/20241030_120000"
    exit 1
fi

BACKUP_PATH="$1"
GRAFANA_BACKUP_PATH="${BACKUP_PATH}/persistent-data/grafana"

# Validate backup path
if [ ! -d "$GRAFANA_BACKUP_PATH" ]; then
    echo "❌ Error: Grafana backup path not found: $GRAFANA_BACKUP_PATH"
    exit 1
fi

echo "📁 Restoring from: $GRAFANA_BACKUP_PATH"

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

# Get Grafana pod name
GRAFANA_POD=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$GRAFANA_POD" ] || [ "$GRAFANA_POD" = "null" ]; then
    echo "❌ Error: Grafana pod not found or not running"
    exit 1
fi

echo "📱 Found Grafana pod: $GRAFANA_POD"

# Stop Grafana temporarily for safe restore
echo "⏸️  Scaling down Grafana deployment..."
kubectl scale deployment grafana -n monitoring --replicas=0
echo "⏳ Waiting for pod to terminate..."
kubectl wait --for=delete pod -l app=grafana -n monitoring --timeout=60s || echo "Pod may still be terminating"

# Wait a bit more to ensure clean shutdown
sleep 10

# Scale back up
echo "🔄 Scaling up Grafana deployment..."
kubectl scale deployment grafana -n monitoring --replicas=1

# Wait for new pod to be ready
echo "⏳ Waiting for Grafana pod to be ready..."
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=120s

# Get new pod name
GRAFANA_POD=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}')
echo "📱 New Grafana pod: $GRAFANA_POD"

# Restore database
if [ -f "$GRAFANA_BACKUP_PATH/grafana.db" ]; then
    echo "🗄️  Restoring Grafana database..."
    
    # Check if backup database is valid (not empty)
    if [ -s "$GRAFANA_BACKUP_PATH/grafana.db" ]; then
        # Copy database to pod
        kubectl cp "$GRAFANA_BACKUP_PATH/grafana.db" "monitoring/$GRAFANA_POD:/tmp/grafana.db.restore"
        
        # Stop Grafana process, restore database, and restart
        kubectl exec -n monitoring "$GRAFANA_POD" -- sh -c '
            # Stop any running processes
            pkill -f "grafana" || true
            sleep 2
            
            # Backup current database if it exists
            if [ -f /var/lib/grafana/grafana.db ]; then
                cp /var/lib/grafana/grafana.db /var/lib/grafana/grafana.db.backup.$(date +%s) || true
            fi
            
            # Restore database
            cp /tmp/grafana.db.restore /var/lib/grafana/grafana.db
            chown 472:472 /var/lib/grafana/grafana.db
            chmod 664 /var/lib/grafana/grafana.db
            
            # Clean up temp file
            rm -f /tmp/grafana.db.restore
            
            echo "Database restored successfully"
        '
        echo "✅ Grafana database restored"
    else
        echo "⚠️  Backup database is empty, skipping restore"
    fi
else
    echo "⚠️  No database backup found"
fi

# Restore data directory
if [ -f "$GRAFANA_BACKUP_PATH/grafana-data.tar.gz" ]; then
    echo "📦 Restoring Grafana data directory..."
    
    # Copy data archive to pod
    kubectl cp "$GRAFANA_BACKUP_PATH/grafana-data.tar.gz" "monitoring/$GRAFANA_POD:/tmp/grafana-data.tar.gz"
    
    kubectl exec -n monitoring "$GRAFANA_POD" -- sh -c '
        # Backup current data directory
        if [ -d /var/lib/grafana ]; then
            tar -czf /tmp/grafana-backup-$(date +%s).tar.gz /var/lib/grafana 2>/dev/null || true
        fi
        
        # Extract data archive
        cd /tmp
        tar -xzf grafana-data.tar.gz
        
        # Copy data to proper location (preserve existing database if we restored it separately)
        if [ -d /tmp/var/lib/grafana ]; then
            # Copy everything except the database if we already restored it
            find /tmp/var/lib/grafana -type f ! -name "grafana.db" -exec cp {} /var/lib/grafana/ \; 2>/dev/null || true
            
            # Copy directories
            find /tmp/var/lib/grafana -type d -exec mkdir -p /var/lib/grafana/{} \; 2>/dev/null || true
            
            # Set proper ownership
            chown -R 472:472 /var/lib/grafana
            chmod -R 755 /var/lib/grafana
        fi
        
        # Clean up
        rm -rf /tmp/grafana-data.tar.gz /tmp/var
        
        echo "Data directory restored successfully"
    '
    echo "✅ Grafana data directory restored"
else
    echo "⚠️  No data directory backup found"
fi

# Restart Grafana to pick up restored data
echo "🔄 Restarting Grafana to apply restored data..."
kubectl rollout restart deployment grafana -n monitoring
kubectl rollout status deployment grafana -n monitoring --timeout=120s

# Verify restore
echo "🔍 Verifying restore..."
sleep 10

# Check if Grafana is responding
GRAFANA_POD=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n monitoring "$GRAFANA_POD" -- sh -c 'ls -la /var/lib/grafana/grafana.db' >/dev/null 2>&1; then
    echo "✅ Grafana database verified"
    
    # Show database size
    DB_SIZE=$(kubectl exec -n monitoring "$GRAFANA_POD" -- sh -c 'ls -la /var/lib/grafana/grafana.db | awk "{print \$5}"' 2>/dev/null || echo "0")
    echo "📊 Restored database size: ${DB_SIZE} bytes"
    
    # Check if Grafana API is responding
    echo "🌐 Testing Grafana API..."
    if kubectl exec -n monitoring "$GRAFANA_POD" -- sh -c 'curl -s http://localhost:3000/api/health' >/dev/null 2>&1; then
        echo "✅ Grafana API is responding"
    else
        echo "⚠️  Grafana API not responding yet (may need more time to start)"
    fi
    
    # Show restore summary
    echo ""
    echo "📋 Restore Summary"
    echo "=================="
    echo "Backup Source: $GRAFANA_BACKUP_PATH"
    echo "Grafana Pod: $GRAFANA_POD"
    echo "Database: $(if [ -f "$GRAFANA_BACKUP_PATH/grafana.db" ]; then echo "✅ Restored"; else echo "❌ Not found"; fi)"
    echo "Data Directory: $(if [ -f "$GRAFANA_BACKUP_PATH/grafana-data.tar.gz" ]; then echo "✅ Restored"; else echo "❌ Not found"; fi)"
    echo ""
    echo "✅ Grafana restore completed successfully!"
    echo "🌐 Access Grafana at: http://$(kubectl get ingress grafana -n monitoring -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo 'grafana.local')"
    echo "👤 Default credentials: admin/admin"
else
    echo "❌ Error: Could not verify restored database"
    exit 1
fi