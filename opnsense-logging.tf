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

      # Options for better logging
      options {
        keep_hostname(yes);
        keep_timestamp(yes);
        log_fifo_size(10000);
      };

      # Source: UDP syslog from OPNsense
      source s_opnsense_udp {
        network(
          ip("0.0.0.0")
          port(514)
          transport("udp")
          flags(no-parse)
          log_iw_size(10000)
        );
      };

      # Source: TCP syslog from OPNsense
      source s_opnsense_tcp {
        network(
          ip("0.0.0.0")
          port(514)
          transport("tcp")
          flags(no-parse)
          log_iw_size(10000)
          max_connections(100)
        );
      };

      # Destination: File for Promtail to pick up
      destination d_opnsense_file {
        file("/var/log/opnsense/firewall.log"
          template("$ISODATE $HOST $MESSAGE\n")
          create_dirs(yes)
        );
      };

      # Destination: stdout for debugging
      destination d_stdout {
        file("/dev/stdout"
          template("[$ISODATE] $HOST: $MSG\n")
        );
      };

      # Log processing - UDP
      log {
        source(s_opnsense_udp);
        destination(d_stdout);
        destination(d_opnsense_file);
      };

      # Log processing - TCP
      log {
        source(s_opnsense_tcp);
        destination(d_stdout);
        destination(d_opnsense_file);
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
          
          # Override command to disable capability management
          command = ["/usr/sbin/syslog-ng"]
          args    = ["-F", "--no-caps"]

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

          volume_mount {
            name       = "opnsense-logs"
            mount_path = "/var/log/opnsense"
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

        volume {
          name = "opnsense-logs"
          empty_dir {}
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
