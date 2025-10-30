#!/bin/bash

# NetAlertX Health Check Script
# Quick health check for NetAlertX database and configuration

set -e

echo "🏥 NetAlertX Health Check"
echo "========================"
echo ""

# Check if NetAlertX deployment exists
if ! kubectl get deployment netalertx -n netalertx >/dev/null 2>&1; then
    echo "❌ NetAlertX deployment not found"
    exit 1
fi

# Get pod name
NETALERTX_POD=$(kubectl get pods -n netalertx -l app=netalertx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$NETALERTX_POD" ]; then
    echo "❌ NetAlertX pod not found"
    exit 1
fi

echo "📊 Pod Status:"
kubectl get pods -n netalertx -l app=netalertx
echo ""

echo "🔍 Health Checks:"
echo "=================="

# Check 1: Pod is running
POD_STATUS=$(kubectl get pod "$NETALERTX_POD" -n netalertx -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" = "Running" ]; then
    echo "✅ Pod is running"
else
    echo "❌ Pod is not running (status: $POD_STATUS)"
fi

# Check 2: Database file exists and is valid
if kubectl exec -n netalertx "$NETALERTX_POD" -- test -f /db/app.db 2>/dev/null; then
    DB_SIZE=$(kubectl exec -n netalertx "$NETALERTX_POD" -- stat -c%s /db/app.db 2>/dev/null || echo "0")
    if [ "$DB_SIZE" -gt 1000 ]; then
        echo "✅ Database file exists and has content ($DB_SIZE bytes)"
        
        # Test database integrity
        if kubectl exec -n netalertx "$NETALERTX_POD" -- sqlite3 /db/app.db "PRAGMA integrity_check;" >/dev/null 2>&1; then
            echo "✅ Database integrity check passed"
        else
            echo "❌ Database integrity check failed"
        fi
    else
        echo "❌ Database file is empty or too small ($DB_SIZE bytes)"
    fi
else
    echo "❌ Database file does not exist"
fi

# Check 3: Configuration file exists and is writable
if kubectl exec -n netalertx "$NETALERTX_POD" -- test -f /config/app.conf 2>/dev/null; then
    if kubectl exec -n netalertx "$NETALERTX_POD" -- test -w /config/app.conf 2>/dev/null; then
        echo "✅ Configuration file exists and is writable"
    else
        echo "⚠️  Configuration file exists but is not writable"
    fi
else
    echo "❌ Configuration file does not exist"
fi

# Check 4: Web interface responds
if kubectl exec -n netalertx "$NETALERTX_POD" -- curl -s --connect-timeout 5 http://localhost:20211 >/dev/null 2>&1; then
    echo "✅ Web interface responds internally"
else
    echo "❌ Web interface not responding internally"
fi

# Check 5: Ingress accessibility
if curl -s --connect-timeout 5 http://netalertx.home >/dev/null 2>&1; then
    echo "✅ Web interface accessible via ingress"
else
    echo "⚠️  Web interface not accessible via ingress (check DNS)"
fi

# Check 6: Storage volumes
echo ""
echo "💾 Storage Status:"
kubectl get pvc -n netalertx

echo ""
echo "📋 Summary:"
echo "==========="

# Count successful checks
CHECKS=0
PASSED=0

# Pod running check
CHECKS=$((CHECKS + 1))
if [ "$POD_STATUS" = "Running" ]; then
    PASSED=$((PASSED + 1))
fi

# Database check
CHECKS=$((CHECKS + 1))
if kubectl exec -n netalertx "$NETALERTX_POD" -- test -f /db/app.db 2>/dev/null; then
    DB_SIZE=$(kubectl exec -n netalertx "$NETALERTX_POD" -- stat -c%s /db/app.db 2>/dev/null || echo "0")
    if [ "$DB_SIZE" -gt 1000 ]; then
        PASSED=$((PASSED + 1))
    fi
fi

# Config check
CHECKS=$((CHECKS + 1))
if kubectl exec -n netalertx "$NETALERTX_POD" -- test -w /config/app.conf 2>/dev/null; then
    PASSED=$((PASSED + 1))
fi

# Web interface check
CHECKS=$((CHECKS + 1))
if kubectl exec -n netalertx "$NETALERTX_POD" -- curl -s --connect-timeout 5 http://localhost:20211 >/dev/null 2>&1; then
    PASSED=$((PASSED + 1))
fi

echo "Health Score: $PASSED/$CHECKS checks passed"

if [ "$PASSED" -eq "$CHECKS" ]; then
    echo "🎉 NetAlertX is healthy!"
    echo ""
    echo "🌐 Access: http://netalertx.home"
elif [ "$PASSED" -ge 2 ]; then
    echo "⚠️  NetAlertX has some issues but is partially functional"
    echo ""
    echo "🔧 Run for detailed diagnosis: ./scripts/debug-netalertx.sh"
else
    echo "❌ NetAlertX has significant issues"
    echo ""
    echo "🔧 Recommended actions:"
    echo "• Check logs: kubectl logs -n netalertx deployment/netalertx"
    echo "• Fix database: ./scripts/fix-netalertx-database.sh"
    echo "• Debug issues: ./scripts/debug-netalertx.sh"
fi