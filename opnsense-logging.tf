# OPNsense Log Integration
# Collects logs from OPNsense router and forwards to Loki

# Syslog-ng ConfigMap
resource "kubernetes_config_map" "syslog_ng_config" {
  metadata {
    name      = "syslog-ng-config"
    namespace = "monitoring"
  }

  data = {
    "syslog-ng.conf" = <<-EOT
      @version: 4.5
      @include "scl.conf"

      # Source: UDP syslog from OPNsense
      source s_opnsense {
        network(
          ip(0.0.0.0)
          port(514)
          transport("udp")
          flags(no-parse)
        );
        network(
          ip(0.0.0.0)
          port(514)
          transport("tcp")
          flags(no-parse)
        );
      };

      # Destination: Loki via HTTP
      destination d_loki {
        http(
          url("http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push")
          method("POST")
          headers(
            "Content-Type: application/json"
          )
          body-suffix("\n")
          body('$(format-json 
            --scope rfc5424 
            --key streams 
            --pair label="{\\"job\\":\\"syslog\\",\\"host\\":\\"$HOST\\",\\"application\\":\\"opnsense\\"}" 
            --pair entries="[{\\"ts\\":\\"$ISODATE\\",\\"line\\":\\"$MESSAGE\\"}]"
          )')
          batch-lines(100)
          batch-timeout(1000)
          timeout(10)
          workers(4)
        );
      };

      # Log processing
      log {
        source(s_opnsense);
        destination(d_loki);
      };
    EOT
  }

  depends_on = [
    kubernetes_namespace.monitoring
  ]
}

# Syslog-ng Deployment
resource "kubernetes_deployment" "syslog_ng" {
  metadata {
    name      = "syslog-ng"
    namespace = "monitoring"
    labels = {
      app = "syslog-ng"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "syslog-ng"
      }
    }

    template {
      metadata {
        labels = {
          app = "syslog-ng"
        }
      }

      spec {
        container {
          name  = "syslog-ng"
          image = "balabit/syslog-ng:4.5.0"

          port {
            name           = "syslog-udp"
            container_port = 514
            protocol       = "UDP"
          }

          port {
            name           = "syslog-tcp"
            container_port = 514
            protocol       = "TCP"
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/syslog-ng/syslog-ng.conf"
            sub_path   = "syslog-ng.conf"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            tcp_socket {
              port = 514
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            tcp_socket {
              port = 514
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.syslog_ng_config.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map.syslog_ng_config,
    kubernetes_deployment.loki
  ]
}

# Syslog-ng Service (LoadBalancer for external access)
resource "kubernetes_service" "syslog_ng" {
  metadata {
    name      = "syslog-ng"
    namespace = "monitoring"
    labels = {
      app = "syslog-ng"
    }
    annotations = {
      "metallb.universe.tf/allow-shared-ip" = "monitoring-services"
    }
  }

  spec {
    type = "LoadBalancer"

    load_balancer_ip = var.syslog_ip # Will need to add this variable

    port {
      name        = "syslog-udp"
      port        = 514
      target_port = 514
      protocol    = "UDP"
    }

    port {
      name        = "syslog-tcp"
      port        = 514
      target_port = 514
      protocol    = "TCP"
    }

    selector = {
      app = "syslog-ng"
    }
  }

  depends_on = [
    kubernetes_deployment.syslog_ng
  ]
}
