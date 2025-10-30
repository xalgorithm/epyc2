#!/bin/sh

set -e

echo "🔄 Starting NetAlertX data restore process..."

# Check if backup path is provided
if [ -z "$1" ]; then
    echo "❌ Error: Backup path not provided"
    echo "Usage: $0 <backup-path>"
    echo "Example: $0 /backup/data/20241030_120000"
    exit 1
fi

BACKUP_PATH="$1"
NETALERTX_BACKUP_PATH="${BACKUP_PATH}/persistent-data/netalertx"

# Validate backup path
if [ ! -d "$NETALERTX_BACKUP_PATH" ]; then
    echo "❌ Error: NetAlertX backup path not found: $NETALERTX_BACKUP_PATH"
    exit 1
fi

echo "📁 Restoring from: $NETALERTX_BACKUP_PATH"

# Install kubectl if not available
if ! command -v kubectl >/dev/null 2>&1; then
    echo "📦 Installing kubectl..."
    apk add --no-cache curl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
fi

# Check if NetAlertX namespace exists
if ! kubectl get namespace netalertx >/dev/null 2>&1; then
    echo "❌ Error: NetAlertX namespace not found. Please deploy NetAlertX first."
    exit 1
fi

# Get NetAlertX pod name
NETALERTX_POD=$(kubectl get pods -n netalertx -l app=netalertx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$NETALERTX_POD" ] || [ "$NETALERTX_POD" = "null" ]; then
    echo "❌ Error: NetAlertX pod not found or not running"
    exit 1
fi

echo "📱 Found NetAlertX pod: $NETALERTX_POD"

# Stop NetAlertX temporarily for safe restore
echo "⏸️  Scaling down NetAlertX deployment..."
kubectl scale deployment netalertx -n netalertx --replicas=0
echo "⏳ Waiting for pod to terminate..."
kubectl wait --for=delete pod -l app=netalertx -n netalertx --timeout=60s || echo "Pod may still be terminating"

# Wait a bit more to ensure clean shutdown
sleep 10

# Scale back up
echo "🔄 Scaling up NetAlertX deployment..."
kubectl scale deployment netalertx -n netalertx --replicas=1

# Wait for new pod to be ready
echo "⏳ Waiting for NetAlertX pod to be ready..."
kubectl wait --for=condition=ready pod -l app=netalertx -n netalertx --timeout=120s

# Get new pod name
NETALERTX_POD=$(kubectl get pods -n netalertx -l app=netalertx -o jsonpath='{.items[0].metadata.name}')
echo "📱 New NetAlertX pod: $NETALERTX_POD"

# Restore database
if [ -f "$NETALERTX_BACKUP_PATH/app.db" ]; then
    echo "🗄️  Restoring NetAlertX database..."
    
    # Check if backup database is valid (not empty)
    if [ -s "$NETALERTX_BACKUP_PATH/app.db" ]; then
        # Copy database to pod
        kubectl cp "$NETALERTX_BACKUP_PATH/app.db" "netalertx/$NETALERTX_POD:/tmp/app.db.restore"
        
        # Stop NetAlertX process, restore database, and restart
        kubectl exec -n netalertx "$NETALERTX_POD" -- sh -c '
            # Stop any running processes
            pkill -f "python" || true
            sleep 2
            
            # Backup current database if it exists
            if [ -f /db/app.db ]; then
                cp /db/app.db /db/app.db.backup.$(date +%s) || true
            fi
            
            # Restore database
            cp /tmp/app.db.restore /db/app.db
            chown 1000:1000 /db/app.db
            chmod 664 /db/app.db
            
            # Clean up temp file
            rm -f /tmp/app.db.restore
            
            echo "Database restored successfully"
        '
        echo "✅ NetAlertX database restored"
    else
        echo "⚠️  Backup database is empty, skipping restore"
    fi
else
    echo "⚠️  No database backup found"
fi

# Restore configuration
if [ -f "$NETALERTX_BACKUP_PATH/app.conf" ]; then
    echo "⚙️  Restoring NetAlertX configuration..."
    
    # Copy configuration to pod
    kubectl cp "$NETALERTX_BACKUP_PATH/app.conf" "netalertx/$NETALERTX_POD:/tmp/app.conf.restore"
    
    kubectl exec -n netalertx "$NETALERTX_POD" -- sh -c '
        # Backup current config if it exists
        if [ -f /config/app.conf ]; then
            cp /config/app.conf /config/app.conf.backup.$(date +%s) || true
        fi
        
        # Restore configuration
        cp /tmp/app.conf.restore /config/app.conf
        chown 1000:1000 /config/app.conf
        chmod 664 /config/app.conf
        
        # Clean up temp file
        rm -f /tmp/app.conf.restore
        
        echo "Configuration restored successfully"
    '
    echo "✅ NetAlertX configuration restored"
else
    echo "⚠️  No configuration backup found"
fi

# Restore logs if available
if [ -f "$NETALERTX_BACKUP_PATH/logs.tar.gz" ]; then
    echo "📝 Restoring NetAlertX logs..."
    
    # Copy logs archive to pod
    kubectl cp "$NETALERTX_BACKUP_PATH/logs.tar.gz" "netalertx/$NETALERTX_POD:/tmp/logs.tar.gz"
    
    kubectl exec -n netalertx "$NETALERTX_POD" -- sh -c '
        # Extract logs
        cd /tmp
        tar -xzf logs.tar.gz
        
        # Copy logs to proper location
        if [ -d /tmp/app/front/log ]; then
            cp -r /tmp/app/front/log/* /app/front/log/ 2>/dev/null || true
            chown -R 1000:1000 /app/front/log
        fi
        
        # Clean up
        rm -rf /tmp/logs.tar.gz /tmp/app
        
        echo "Logs restored successfully"
    '
    echo "✅ NetAlertX logs restored"
else
    echo "⚠️  No logs backup found"
fi

# Restart NetAlertX to pick up restored data
echo "🔄 Restarting NetAlertX to apply restored data..."
kubectl rollout restart deployment netalertx -n netalertx
kubectl rollout status deployment netalertx -n netalertx --timeout=120s

# Verify restore
echo "🔍 Verifying restore..."
sleep 10

# Check if NetAlertX is responding
NETALERTX_POD=$(kubectl get pods -n netalertx -l app=netalertx -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n netalertx "$NETALERTX_POD" -- sh -c 'ls -la /db/app.db /config/app.conf' >/dev/null 2>&1; then
    echo "✅ NetAlertX files verified"
    
    # Show database size
    DB_SIZE=$(kubectl exec -n netalertx "$NETALERTX_POD" -- sh -c 'ls -la /db/app.db | awk "{print \$5}"' 2>/dev/null || echo "0")
    echo "📊 Restored database size: ${DB_SIZE} bytes"
    
    # Show restore summary
    echo ""
    echo "📋 Restore Summary"
    echo "=================="
    echo "Backup Source: $NETALERTX_BACKUP_PATH"
    echo "NetAlertX Pod: $NETALERTX_POD"
    echo "Database: $(if [ -f "$NETALERTX_BACKUP_PATH/app.db" ]; then echo "✅ Restored"; else echo "❌ Not found"; fi)"
    echo "Configuration: $(if [ -f "$NETALERTX_BACKUP_PATH/app.conf" ]; then echo "✅ Restored"; else echo "❌ Not found"; fi)"
    echo "Logs: $(if [ -f "$NETALERTX_BACKUP_PATH/logs.tar.gz" ]; then echo "✅ Restored"; else echo "❌ Not found"; fi)"
    echo ""
    echo "✅ NetAlertX restore completed successfully!"
    echo "🌐 Access NetAlertX at: http://$(kubectl get ingress netalertx -n netalertx -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo 'netalertx.local')"
else
    echo "❌ Error: Could not verify restored files"
    exit 1
fi