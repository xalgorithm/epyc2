#!/bin/bash

set -e

echo "🔍 NetAlertX Backup Verification Script"
echo "======================================"

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi

# Check NetAlertX namespace
echo "📂 Checking NetAlertX namespace..."
if kubectl get namespace netalertx >/dev/null 2>&1; then
    echo "✅ NetAlertX namespace exists"
else
    echo "❌ NetAlertX namespace not found"
    exit 1
fi

# Check NetAlertX deployment
echo "🚀 Checking NetAlertX deployment..."
if kubectl get deployment netalertx -n netalertx >/dev/null 2>&1; then
    REPLICAS=$(kubectl get deployment netalertx -n netalertx -o jsonpath='{.status.readyReplicas}')
    if [ "$REPLICAS" = "1" ]; then
        echo "✅ NetAlertX deployment is running"
    else
        echo "⚠️  NetAlertX deployment exists but may not be ready (replicas: $REPLICAS)"
    fi
else
    echo "❌ NetAlertX deployment not found"
    exit 1
fi

# Check NetAlertX pod
echo "📱 Checking NetAlertX pod..."
NETALERTX_POD=$(kubectl get pods -n netalertx -l app=netalertx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$NETALERTX_POD" ] && [ "$NETALERTX_POD" != "null" ]; then
    POD_STATUS=$(kubectl get pod "$NETALERTX_POD" -n netalertx -o jsonpath='{.status.phase}')
    echo "✅ NetAlertX pod found: $NETALERTX_POD (Status: $POD_STATUS)"
else
    echo "❌ NetAlertX pod not found"
    exit 1
fi

# Check persistent volumes
echo "💾 Checking persistent volumes..."
if kubectl get pvc netalertx-data -n netalertx >/dev/null 2>&1; then
    PVC_STATUS=$(kubectl get pvc netalertx-data -n netalertx -o jsonpath='{.status.phase}')
    echo "✅ NetAlertX data PVC exists (Status: $PVC_STATUS)"
else
    echo "❌ NetAlertX data PVC not found"
fi

if kubectl get pvc netalertx-config -n netalertx >/dev/null 2>&1; then
    PVC_STATUS=$(kubectl get pvc netalertx-config -n netalertx -o jsonpath='{.status.phase}')
    echo "✅ NetAlertX config PVC exists (Status: $PVC_STATUS)"
else
    echo "❌ NetAlertX config PVC not found"
fi

# Check NetAlertX files
echo "📁 Checking NetAlertX files..."
if kubectl exec -n netalertx "$NETALERTX_POD" -- test -f /db/app.db 2>/dev/null; then
    DB_SIZE=$(kubectl exec -n netalertx "$NETALERTX_POD" -- ls -la /db/app.db | awk '{print $5}')
    echo "✅ NetAlertX database exists (Size: $DB_SIZE bytes)"
else
    echo "⚠️  NetAlertX database not found (may be initializing)"
fi

if kubectl exec -n netalertx "$NETALERTX_POD" -- test -f /config/app.conf 2>/dev/null; then
    echo "✅ NetAlertX configuration exists"
else
    echo "⚠️  NetAlertX configuration not found"
fi

# Check backup namespace
echo "🔄 Checking backup system..."
if kubectl get namespace backup >/dev/null 2>&1; then
    echo "✅ Backup namespace exists"
else
    echo "❌ Backup namespace not found"
    exit 1
fi

# Check backup cronjobs
echo "⏰ Checking backup cronjobs..."
if kubectl get cronjob data-backup -n backup >/dev/null 2>&1; then
    SCHEDULE=$(kubectl get cronjob data-backup -n backup -o jsonpath='{.spec.schedule}')
    LAST_SCHEDULE=$(kubectl get cronjob data-backup -n backup -o jsonpath='{.status.lastScheduleTime}')
    echo "✅ Data backup cronjob exists (Schedule: $SCHEDULE, Last run: $LAST_SCHEDULE)"
else
    echo "❌ Data backup cronjob not found"
fi

# Check recent backup jobs
echo "📊 Checking recent backup jobs..."
RECENT_JOBS=$(kubectl get jobs -n backup --sort-by=.metadata.creationTimestamp | grep data-backup | tail -3)
if [ -n "$RECENT_JOBS" ]; then
    echo "✅ Recent backup jobs found:"
    echo "$RECENT_JOBS"
else
    echo "⚠️  No recent backup jobs found"
fi

# Check backup storage
echo "💿 Checking backup storage..."
BACKUP_POD=$(kubectl get pods -n backup -l app=backup-metrics -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$BACKUP_POD" ] && [ "$BACKUP_POD" != "null" ]; then
    echo "✅ Backup metrics pod found: $BACKUP_POD"
    
    # Check if backup storage is accessible
    if kubectl exec -n backup "$BACKUP_POD" -- test -d /host/backup 2>/dev/null; then
        echo "✅ Backup storage is accessible"
        
        # List recent backups
        echo "📚 Recent backups:"
        kubectl exec -n backup "$BACKUP_POD" -- ls -la /host/backup/data/ 2>/dev/null | tail -5 || echo "No backups found"
        
        # Check for NetAlertX backups
        LATEST_BACKUP=$(kubectl exec -n backup "$BACKUP_POD" -- ls -1t /host/backup/data/ 2>/dev/null | head -1)
        if [ -n "$LATEST_BACKUP" ]; then
            echo "🔍 Checking latest backup for NetAlertX data..."
            if kubectl exec -n backup "$BACKUP_POD" -- test -d "/host/backup/data/$LATEST_BACKUP/persistent-data/netalertx" 2>/dev/null; then
                echo "✅ NetAlertX data found in latest backup: $LATEST_BACKUP"
                
                # Check backup files
                if kubectl exec -n backup "$BACKUP_POD" -- test -f "/host/backup/data/$LATEST_BACKUP/persistent-data/netalertx/app.db" 2>/dev/null; then
                    BACKUP_DB_SIZE=$(kubectl exec -n backup "$BACKUP_POD" -- ls -la "/host/backup/data/$LATEST_BACKUP/persistent-data/netalertx/app.db" | awk '{print $5}')
                    echo "  📄 Database backup: $BACKUP_DB_SIZE bytes"
                fi
                
                if kubectl exec -n backup "$BACKUP_POD" -- test -f "/host/backup/data/$LATEST_BACKUP/persistent-data/netalertx/app.conf" 2>/dev/null; then
                    echo "  ⚙️  Configuration backup: ✅"
                fi
                
                if kubectl exec -n backup "$BACKUP_POD" -- test -f "/host/backup/data/$LATEST_BACKUP/persistent-data/netalertx/logs.tar.gz" 2>/dev/null; then
                    echo "  📝 Logs backup: ✅"
                fi
            else
                echo "⚠️  NetAlertX data not found in latest backup"
            fi
        fi
    else
        echo "❌ Backup storage not accessible"
    fi
else
    echo "❌ Backup metrics pod not found"
fi

# Test backup functionality
echo ""
echo "🧪 Testing backup functionality..."
echo "================================="

# Trigger a test backup
echo "🚀 Triggering test backup job..."
TEST_JOB_NAME="test-netalertx-backup-$(date +%s)"
if kubectl create job --from=cronjob/data-backup "$TEST_JOB_NAME" -n backup >/dev/null 2>&1; then
    echo "✅ Test backup job created: $TEST_JOB_NAME"
    
    # Wait for job to complete (with timeout)
    echo "⏳ Waiting for test backup to complete (timeout: 300s)..."
    if kubectl wait --for=condition=complete job/"$TEST_JOB_NAME" -n backup --timeout=300s >/dev/null 2>&1; then
        echo "✅ Test backup completed successfully"
        
        # Check if NetAlertX data was backed up
        sleep 5
        LATEST_BACKUP=$(kubectl exec -n backup "$BACKUP_POD" -- ls -1t /host/backup/data/ 2>/dev/null | head -1)
        if kubectl exec -n backup "$BACKUP_POD" -- test -f "/host/backup/data/$LATEST_BACKUP/persistent-data/netalertx/app.db" 2>/dev/null; then
            echo "✅ NetAlertX database successfully backed up in test"
        else
            echo "⚠️  NetAlertX database not found in test backup"
        fi
    else
        echo "⚠️  Test backup did not complete within timeout"
        kubectl logs job/"$TEST_JOB_NAME" -n backup | tail -10
    fi
    
    # Clean up test job
    kubectl delete job "$TEST_JOB_NAME" -n backup >/dev/null 2>&1 || true
else
    echo "❌ Failed to create test backup job"
fi

echo ""
echo "📋 Verification Summary"
echo "======================"
echo "NetAlertX Status: $(if kubectl get pod "$NETALERTX_POD" -n netalertx -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Running; then echo "✅ Running"; else echo "❌ Not Running"; fi)"
echo "Backup System: $(if kubectl get cronjob data-backup -n backup >/dev/null 2>&1; then echo "✅ Active"; else echo "❌ Not Found"; fi)"
echo "Backup Storage: $(if kubectl exec -n backup "$BACKUP_POD" -- test -d /host/backup 2>/dev/null; then echo "✅ Accessible"; else echo "❌ Not Accessible"; fi)"
echo "NetAlertX Backups: $(if kubectl exec -n backup "$BACKUP_POD" -- find /host/backup/data -name "app.db" 2>/dev/null | grep -q app.db; then echo "✅ Found"; else echo "❌ Not Found"; fi)"

echo ""
echo "🎯 Next Steps:"
echo "- Monitor backup jobs: kubectl get jobs -n backup"
echo "- Check backup logs: kubectl logs -n backup -l app=data-backup"
echo "- View backup guide: cat BACKUP_GUIDE.md"
echo "- Manual restore: kubectl exec -n backup \$BACKUP_POD -- /scripts/restore-netalertx.sh /host/backup/data/BACKUP_DATE"