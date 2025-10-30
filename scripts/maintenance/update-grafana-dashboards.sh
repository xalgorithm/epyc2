#!/bin/bash

# Update Grafana Dashboards Script
# This script updates Grafana with comprehensive Kubernetes monitoring dashboards

set -e

echo "📊 Updating Grafana Dashboards"
echo "==============================="
echo ""

echo "🔍 Checking current Grafana deployment..."
if ! kubectl get deployment grafana -n monitoring >/dev/null 2>&1; then
    echo "❌ Grafana deployment not found"
    echo "Please deploy the full stack first with: ./scripts/deploy-full-stack.sh"
    exit 1
fi

echo "✅ Grafana deployment found"
echo ""

echo "📋 New comprehensive dashboards being added:"
echo "============================================="
echo "• Kubernetes Cluster Overview - High-level cluster metrics and status"
echo "• Kubernetes Pods & Workloads - Detailed pod status and resource usage"
echo "• Kubernetes Logs Analysis - Comprehensive log analysis with filtering"
echo "• Kubernetes Resource Monitoring - CPU, memory, network, and disk usage"
echo "• Kubernetes Events & Alerts - System events and health monitoring"
echo ""

echo "🚀 Applying dashboard updates via Terraform..."
terraform apply -target=kubernetes_config_map.grafana_dashboards -auto-approve

echo ""
echo "⏳ Restarting Grafana to load new dashboards..."
kubectl rollout restart deployment/grafana -n monitoring
kubectl rollout status deployment/grafana -n monitoring --timeout=300s

echo ""
echo "📊 Checking Grafana pod status:"
kubectl get pods -n monitoring -l app=grafana

echo ""
echo "🎉 Dashboard update complete!"
echo ""
echo "📋 Available Dashboards:"
echo "========================"
echo ""
echo "🏠 Original Dashboards:"
echo "• Homelab Dashboard - General homelab overview"
echo "• Prometheus Dashboard - Prometheus metrics and status"
echo "• Loki Logs Dashboard - Basic log viewing"
echo "• Mimir Dashboard - Long-term metrics storage"
echo "• Node Exporter Dashboard - System metrics"
echo "• Proxmox Dashboard - Virtualization metrics"
echo "• Backup Dashboard - Backup system status"
echo ""
echo "🚀 New Kubernetes Dashboards:"
echo "• Kubernetes Cluster Overview - Cluster health and resource usage"
echo "• Kubernetes Pods & Workloads - Pod status, resource usage by namespace"
echo "• Kubernetes Logs Analysis - Advanced log filtering and analysis"
echo "• Kubernetes Resource Monitoring - Detailed resource usage and I/O"
echo "• Kubernetes Events & Alerts - System events and health alerts"
echo ""
echo "🌐 Access Grafana:"
GRAFANA_IP=$(kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
if [ "$GRAFANA_IP" != "pending" ] && [ -n "$GRAFANA_IP" ]; then
    echo "• Direct access: http://$GRAFANA_IP:3000"
fi
echo "• Ingress: http://grafana.home"
echo "• Credentials: admin/admin"
echo ""
echo "💡 Tips for using the new dashboards:"
echo "• Start with 'Kubernetes Cluster Overview' for general health"
echo "• Use 'Kubernetes Logs Analysis' for troubleshooting issues"
echo "• Monitor resource usage with 'Kubernetes Resource Monitoring'"
echo "• Check system health with 'Kubernetes Events & Alerts'"
echo ""
echo "🎯 The dashboards include:"
echo "• Real-time metrics and logs"
echo "• Interactive filtering by namespace and pod"
echo "• Resource usage trends and alerts"
echo "• Error and warning log analysis"
echo "• Network and disk I/O monitoring"
echo ""
echo "✅ Your Grafana now has comprehensive Kubernetes monitoring!"