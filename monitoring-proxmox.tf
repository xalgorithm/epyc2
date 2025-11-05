# Proxmox VE Monitoring Configuration
# This file configures the Proxmox VE exporter for metrics collection

# ConfigMap for Proxmox Exporter Configuration
resource "kubernetes_config_map" "proxmox_exporter_config" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "proxmox-exporter-config"
    namespace = "monitoring"
  }

  data = {
    "pve.yml" = <<-EOT
default:
  user: ${split("!", var.proxmox_api_token_id)[0]}
  token_name: ${split("!", var.proxmox_api_token_id)[1]}
  token_value: ${var.proxmox_api_token_secret}
  verify_ssl: ${var.proxmox_tls_insecure ? "false" : "true"}
    EOT
  }
}

# Proxmox Exporter Deployment
resource "kubernetes_deployment" "proxmox_exporter" {
  depends_on = [
    kubernetes_namespace.monitoring,
    kubernetes_config_map.proxmox_exporter_config
  ]

  metadata {
    name      = "proxmox-exporter"
    namespace = "monitoring"
    labels = {
      app = "proxmox-exporter"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "proxmox-exporter"
      }
    }

    template {
      metadata {
        labels = {
          app = "proxmox-exporter"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9221"
          "prometheus.io/path"   = "/pve"
        }
      }

      spec {
        container {
          name  = "proxmox-exporter"
          image = "prompve/prometheus-pve-exporter:latest"

          port {
            container_port = 9221
            name           = "metrics"
          }

          # Mount the config file to default location
          volume_mount {
            name       = "config"
            mount_path = "/etc/prometheus"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            tcp_socket {
              port = 9221
            }
            initial_delay_seconds = 15
            period_seconds        = 20
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          readiness_probe {
            tcp_socket {
              port = 9221
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }
        }

        # Mount the config file from ConfigMap
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.proxmox_exporter_config.metadata[0].name
          }
        }
      }
    }
  }
}

# Proxmox Exporter Service
resource "kubernetes_service" "proxmox_exporter" {
  depends_on = [kubernetes_deployment.proxmox_exporter]

  metadata {
    name      = "proxmox-exporter"
    namespace = "monitoring"
    labels = {
      app = "proxmox-exporter"
    }
    annotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "9221"
      "prometheus.io/path"   = "/pve"
    }
  }

  spec {
    selector = {
      app = "proxmox-exporter"
    }

    port {
      name        = "metrics"
      port        = 9221
      target_port = 9221
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

