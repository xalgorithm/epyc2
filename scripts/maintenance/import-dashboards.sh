#!/bin/bash

# Get Grafana URL from kubectl or use default
GRAFANA_URL="http://$(kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo 'localhost'):3000"
USERNAME="admin"
PASSWORD="admin"  # Change this to match your Grafana admin password
FOLDER_ID=1

# Dashboard files to import
DASHBOARDS=(
    "homelab-dashboard.json"
    "prometheus-dashboard.json" 
    "loki-logs-dashboard.json"
    "mimir-dashboard.json"
    "node-exporter-dashboard.json"
)

echo "🎯 Importing Grafana Dashboards..."

for dashboard_file in "${DASHBOARDS[@]}"; do
    echo "📊 Importing $dashboard_file..."
    
    # Get dashboard content from the pod
    dashboard_json=$(kubectl exec grafana-55d449f659-l4vwg -n monitoring -- cat /var/lib/grafana/dashboards/$dashboard_file)
    
    # Create import payload
    import_payload=$(echo "$dashboard_json" | jq --arg folder_id "$FOLDER_ID" '{dashboard: ., folderId: ($folder_id | tonumber), overwrite: true}')
    
    # Import dashboard
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "$USERNAME:$PASSWORD" \
        -d "$import_payload" \
        "$GRAFANA_URL/api/dashboards/db")
    
    # Check response
    if echo "$response" | jq -e '.status == "success"' > /dev/null; then
        dashboard_title=$(echo "$response" | jq -r '.slug')
        echo "✅ Successfully imported: $dashboard_title"
    else
        echo "❌ Failed to import $dashboard_file:"
        echo "$response" | jq .
    fi
    
    sleep 1
done

echo "🎉 Dashboard import complete!"
