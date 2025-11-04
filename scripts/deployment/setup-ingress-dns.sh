#!/bin/bash

# Setup Ingress DNS Resolution
# This script helps configure local DNS resolution for ingress endpoints

set -e

echo "🌐 Setting up Ingress DNS Resolution"
echo "===================================="
echo ""

# Get the ingress IP
# Get ingress IP from terraform.tfvars or kubectl
INGRESS_IP=$(grep ingress_ip terraform.tfvars 2>/dev/null | cut -d '"' -f 2 || kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "192.168.1.200")
echo "📋 Configured Ingress IP: $INGRESS_IP"
echo ""

# Check if ingress controller is running
echo "🔍 Checking NGINX Ingress Controller status..."
if kubectl get svc ingress-nginx-controller -n ingress-nginx >/dev/null 2>&1; then
    ACTUAL_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    echo "✅ NGINX Ingress Controller is deployed"
    echo "📍 Actual LoadBalancer IP: $ACTUAL_IP"
    
    if [ "$ACTUAL_IP" != "pending" ] && [ -n "$ACTUAL_IP" ]; then
        INGRESS_IP="$ACTUAL_IP"
        echo "✅ Using actual LoadBalancer IP: $INGRESS_IP"
    else
        echo "⏳ LoadBalancer IP is still pending, using configured IP: $INGRESS_IP"
    fi
else
    echo "❌ NGINX Ingress Controller not found"
    echo "Please deploy the full stack first"
    exit 1
fi

echo ""
echo "🔍 Checking ingress resources..."
kubectl get ingress -A

echo ""
echo "📝 DNS Configuration Required:"
echo "=============================="
echo ""
echo "Add these entries to your /etc/hosts file:"
echo ""
echo "$INGRESS_IP grafana.home"
echo "$INGRESS_IP prometheus.home" 
echo "$INGRESS_IP loki.home"
echo "$INGRESS_IP mimir.home"
echo "$INGRESS_IP mylar.home"
echo ""

# Offer to add to /etc/hosts automatically
read -p "🤔 Would you like to add these entries to /etc/hosts automatically? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Adding entries to /etc/hosts..."
    
    # Backup current hosts file
    sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)
    echo "✅ Backed up /etc/hosts"
    
    # Remove any existing entries for these hosts
    sudo sed -i '' '/grafana\.home/d' /etc/hosts 2>/dev/null || sudo sed -i '/grafana\.home/d' /etc/hosts
    sudo sed -i '' '/prometheus\.home/d' /etc/hosts 2>/dev/null || sudo sed -i '/prometheus\.home/d' /etc/hosts
    sudo sed -i '' '/loki\.home/d' /etc/hosts 2>/dev/null || sudo sed -i '/loki\.home/d' /etc/hosts
    sudo sed -i '' '/mimir\.home/d' /etc/hosts 2>/dev/null || sudo sed -i '/mimir\.home/d' /etc/hosts
    sudo sed -i '' '/mylar\.home/d' /etc/hosts 2>/dev/null || sudo sed -i '/mylar\.home/d' /etc/hosts

    
    # Add new entries
    echo "" | sudo tee -a /etc/hosts >/dev/null
    echo "# Kubernetes Ingress Endpoints" | sudo tee -a /etc/hosts >/dev/null
    echo "$INGRESS_IP grafana.home" | sudo tee -a /etc/hosts >/dev/null
    echo "$INGRESS_IP prometheus.home" | sudo tee -a /etc/hosts >/dev/null
    echo "$INGRESS_IP loki.home" | sudo tee -a /etc/hosts >/dev/null
    echo "$INGRESS_IP mimir.home" | sudo tee -a /etc/hosts >/dev/null
    echo "$INGRESS_IP mylar.home" | sudo tee -a /etc/hosts >/dev/null

    
    echo "✅ Added entries to /etc/hosts"
else
    echo "ℹ️  You can manually add the entries above to /etc/hosts"
fi

echo ""
echo "🧪 Testing DNS Resolution:"
echo "=========================="
for host in grafana.home prometheus.home loki.home mimir.home mylar.home; do
    if ping -c 1 -W 1000 "$host" >/dev/null 2>&1; then
        echo "✅ $host resolves correctly"
    else
        echo "❌ $host does not resolve"
    fi
done

echo ""
echo "🌐 Access URLs:"
echo "==============="
echo "• Grafana:    http://grafana.home (admin/admin)"
echo "• Prometheus: http://prometheus.home"
echo "• Loki:       http://loki.home"
echo "• Mimir:      http://mimir.home"
echo "• Mylar:      http://mylar.home"

echo ""

echo "🔍 Testing HTTP connectivity..."
for service in grafana prometheus loki mimir mylar; do
    if curl -s --connect-timeout 5 "http://${service}.home" >/dev/null 2>&1; then
        echo "✅ $service.home is accessible"
    else
        echo "⏳ $service.home is not yet accessible (may still be starting)"
    fi
done

echo ""
echo "🎉 DNS setup complete!"
echo ""
echo "💡 Tips:"
echo "- If services are not accessible, wait a few minutes for pods to start"
echo "- Check pod status with: kubectl get pods -A"
echo "- Check ingress status with: kubectl get ingress -A"