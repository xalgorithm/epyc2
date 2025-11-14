# Rebellion Cluster Monitoring Integration
# This file configures monitoring for the rebellion cluster and cross-cluster federation

# =============================================================================
# Rebellion Dashboards for Main Grafana
# =============================================================================

# Create ConfigMap with rebellion dashboards for main Grafana
resource "kubernetes_config_map" "rebellion_grafana_dashboards" {
  count = var.bootstrap_cluster ? 1 : 0

  metadata {
    name      = "rebellion-dashboards"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "rebellion-cluster-dashboard.json"  = file("${path.module}/configs/grafana/rebellion-cluster-dashboard.json")
    "rebellion-istio-dashboard.json"    = file("${path.module}/configs/grafana/rebellion-istio-dashboard.json")
  }

  depends_on = [
    kubernetes_namespace.monitoring
  ]
}

# =============================================================================
# Cross-Cluster Monitoring Configuration
# =============================================================================

# Add rebellion cluster as a Prometheus federation target
resource "kubernetes_config_map" "prometheus_rebellion_targets" {
  count = var.bootstrap_cluster ? 1 : 0

  metadata {
    name      = "prometheus-rebellion-targets"
    namespace = "monitoring"
    labels = {
      prometheus = "scrape-config"
    }
  }

  data = {
    "rebellion-nodes.yml" = <<-EOT
      - job_name: 'rebellion-nodes'
        honor_labels: true
        static_configs:
          - targets:
              - '192.168.0.40:9100'  # luke
              - '192.168.0.41:9100'  # leia
              - '192.168.0.42:9100'  # han
            labels:
              cluster: 'rebellion'
              environment: 'production'
      
      - job_name: 'rebellion-prometheus'
        honor_labels: true
        static_configs:
          - targets:
              - 'prometheus-rebellion.monitoring.svc.rebellion.local:9090'
            labels:
              cluster: 'rebellion'
        metric_relabel_configs:
          - source_labels: [__name__]
            regex: 'up|scrape_.*'
            action: drop
    EOT
  }

  depends_on = [
    kubernetes_namespace.monitoring
  ]
}

# =============================================================================
# Outputs
# =============================================================================

output "rebellion_monitoring_info" {
  description = "Rebellion cluster monitoring integration information"
  value = {
    dashboards = {
      cluster_overview = "rebellion-cluster-dashboard"
      istio_metrics    = "rebellion-istio-dashboard"
    }
    federation = {
      prometheus_targets = "rebellion-nodes, rebellion-prometheus"
      loki_client        = "promtail → main cluster Loki"
      mimir_remote_write = "rebellion Prometheus → main cluster Mimir"
    }
    access = {
      rebellion_prometheus = "export KUBECONFIG=~/.kube/configs/rebellion-config && kubectl port-forward -n monitoring svc/prometheus-rebellion 9090:9090"
      main_grafana         = "http://${var.grafana_host} (dashboards: Rebellion Cluster Overview, Rebellion Istio Gateway)"
    }
  }
}

