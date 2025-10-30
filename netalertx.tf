# NetAlertX Network Monitoring
# Network device discovery and monitoring for the homelab

# NetAlertX namespace
resource "kubernetes_namespace" "netalertx" {
  depends_on = [null_resource.kubeconfig_ready, null_resource.cluster_api_ready]

  metadata {
    name = "netalertx"
    labels = {
      name = "netalertx"
    }
  }
}

# NetAlertX configuration
resource "kubernetes_config_map" "netalertx_config" {
  depends_on = [kubernetes_namespace.netalertx]

  metadata {
    name      = "netalertx-config"
    namespace = "netalertx"
  }

  data = {
    "app.conf" = <<-EOT
#################################################################################
# NetAlertX Configuration File
#################################################################################

#################################################################################
# Network Configuration
#################################################################################
SCAN_SUBNETS = ['${var.netalertx_scan_range}']
INTERFACE = eth0

#################################################################################
# Scanning Settings
#################################################################################
SCAN_CYCLE_MINUTES = 5
ARPSCAN_RUN_TIMEOUT = 30
PINGSCAN_RUN_TIMEOUT = 30

#################################################################################
# Network Tools
#################################################################################
NMAP_ARGS = -sn --host-timeout 10s
ARPSCAN_ARGS = -l -g -t 1000

#################################################################################
# Plugin Settings
#################################################################################
# Increase plugin timeouts to prevent timeout errors
PLUGINS_TIMEOUT = 30

# Plugin-specific settings
AVAHISCAN_TIMEOUT = 30
NBTSCAN_TIMEOUT = 30
NSLOOKUP_TIMEOUT = 30
DIG_TIMEOUT = 30

# Disable problematic plugins if network tools are not available
AVAHISCAN_RUN = True
NBTSCAN_RUN = True
NSLOOKUP_RUN = True
DIG_RUN = True

#################################################################################
# Database Settings
#################################################################################
DB_PATH = /db/app.db
LOG_LEVEL = verbose

#################################################################################
# Web Interface
#################################################################################
WEB_PROTECTION = False
WEB_PASSWORD = 

#################################################################################
# Notifications (disabled by default)
#################################################################################
REPORT_MAIL = False
SMTP_SERVER = 
SMTP_PORT = 587
REPORT_TO = 
REPORT_FROM = 

#################################################################################
# Device Settings
#################################################################################
DAYS_TO_KEEP_EVENTS = 90
SCAN_WEBSERVICES = True
WEBSERVICES_TIMEOUT = 1

#################################################################################
# Network Scanning
#################################################################################
ICMP_TIMEOUT_SEC = 5
DHCP_LEASES_FILE = 
PIHOLE_DB = 

# Network interface settings
SCAN_INTERFACE = eth0
SCAN_DELAY_MINUTES = 1

# Improve network scanning reliability
ARPSCAN_RUN_TIMEOUT = 60
PINGSCAN_RUN_TIMEOUT = 60
NMAP_RUN_TIMEOUT = 60

#################################################################################
# Advanced Settings
#################################################################################
TIMEZONE = UTC
LANG = en_us.UTF-8

#################################################################################
# Additional NetAlertX Settings
#################################################################################
# Enable/disable features
SCAN_WEBSERVICES = True
SCAN_WEBSERVICES_TIMEOUT = 1

# Device tracking
NEW_DEVICE_NOTIFICATIONS = True
DOWN_DEVICE_NOTIFICATIONS = True

# Logging
LOG_LEVEL = verbose
LOG_FILE = /app/front/log/pialert.log

# API Settings
API_CUSTOM_SQL = False
    EOT
  }
}

# NetAlertX persistent storage for database
resource "kubernetes_persistent_volume_claim" "netalertx_data" {
  metadata {
    name      = "netalertx-data"
    namespace = "netalertx"
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "2Gi"
      }
    }

    storage_class_name = kubernetes_storage_class.nfs_storage_class.metadata[0].name
  }

  depends_on = [
    kubernetes_namespace.netalertx,
    kubernetes_storage_class.nfs_storage_class
  ]
}

# NetAlertX persistent storage for configuration
resource "kubernetes_persistent_volume_claim" "netalertx_config" {
  metadata {
    name      = "netalertx-config"
    namespace = "netalertx"
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "100Mi"
      }
    }

    storage_class_name = kubernetes_storage_class.nfs_storage_class.metadata[0].name
  }

  depends_on = [
    kubernetes_namespace.netalertx,
    kubernetes_storage_class.nfs_storage_class
  ]
}

# NetAlertX deployment
resource "kubernetes_deployment" "netalertx" {
  depends_on = [
    kubernetes_config_map.netalertx_config,
    kubernetes_persistent_volume_claim.netalertx_data,
    kubernetes_persistent_volume_claim.netalertx_config
  ]
  wait_for_rollout = false

  metadata {
    name      = "netalertx"
    namespace = "netalertx"
    labels = {
      app = "netalertx"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "netalertx"
      }
    }

    template {
      metadata {
        labels = {
          app = "netalertx"
        }
        annotations = {
          "prometheus.io/scrape" = "false"
        }
      }

      spec {
        # Use host network for network scanning
        host_network = true
        dns_policy   = "ClusterFirstWithHostNet"

        # Security context for network access
        security_context {
          run_as_user = 0
          fs_group    = 0
        }

        # Init container to set up directories, copy config, and set permissions
        init_container {
          name  = "netalertx-init"
          image = "busybox:1.35"

          command = [
            "sh",
            "-c",
            <<-EOT
            # Create directories
            mkdir -p /db /config /app/front/log /app/front/config
            
            # Check if config already exists in persistent volume
            if [ -f /config/app.conf ]; then
              echo "Config file already exists in persistent volume, preserving existing configuration"
              # Just ensure proper permissions on existing file
              chown 1000:1000 /config/app.conf
              chmod 664 /config/app.conf
            else
              # Copy config from read-only mount to persistent volume (first time setup)
              if [ -f /tmp/config/app.conf ]; then
                cp /tmp/config/app.conf /config/app.conf
                echo "Config file copied to persistent volume (first time setup)"
                chown 1000:1000 /config/app.conf
                chmod 664 /config/app.conf
              else
                echo "Warning: Config file not found in /tmp/config/"
              fi
            fi
            
            # Check and fix database issues
            if [ -f /db/app.db ]; then
              echo "Database file exists, checking integrity..."
              # Check if database file is corrupted (empty or invalid)
              if [ ! -s /db/app.db ]; then
                echo "Database file is empty, removing corrupted file"
                rm -f /db/app.db*
              else
                echo "Database file appears valid"
              fi
            else
              echo "No existing database file found (will be created by NetAlertX)"
            fi
            
            # Set proper ownership and permissions for directories
            chown -R 1000:1000 /db /config /app
            chmod -R 755 /db /config /app
            
            # Ensure database directory has proper permissions
            chmod 755 /db
            
            echo "Initialization complete"
            EOT
          ]

          volume_mount {
            name       = "netalertx-data"
            mount_path = "/db"
          }

          volume_mount {
            name       = "netalertx-logs"
            mount_path = "/app/front/log"
          }

          volume_mount {
            name       = "netalertx-config-persistent"
            mount_path = "/config"
          }

          volume_mount {
            name       = "netalertx-config"
            mount_path = "/tmp/config"
          }

          security_context {
            run_as_user = 0
          }
        }

        container {
          name  = "netalertx"
          image = "jokobsk/netalertx:latest"

          # Environment variables
          env {
            name  = "TZ"
            value = "UTC"
          }

          env {
            name  = "HOST_USER_ID"
            value = "1000"
          }

          env {
            name  = "HOST_USER_GID"
            value = "1000"
          }

          env {
            name  = "PORT"
            value = "20211"
          }

          env {
            name  = "PIALERT_PATH"
            value = "/app"
          }

          env {
            name  = "PIALERT_CONFIG_FILE"
            value = "/config/app.conf"
          }

          env {
            name  = "PIALERT_DB_PATH"
            value = "/db/app.db"
          }

          env {
            name  = "SQLITE_TMPDIR"
            value = "/tmp"
          }

          env {
            name  = "PYTHONUNBUFFERED"
            value = "1"
          }

          env {
            name  = "PLUGINS_TIMEOUT"
            value = "30"
          }

          # Ports
          port {
            container_port = 20211
            name           = "http"
            protocol       = "TCP"
          }

          # Resource limits
          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          # Volume mounts
          volume_mount {
            name       = "netalertx-data"
            mount_path = "/db"
          }

          volume_mount {
            name       = "netalertx-config-persistent"
            mount_path = "/config"
          }

          volume_mount {
            name       = "netalertx-logs"
            mount_path = "/app/front/log"
          }

          # Health checks
          readiness_probe {
            http_get {
              path = "/"
              port = 20211
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 20211
            }
            initial_delay_seconds = 60
            period_seconds        = 30
            failure_threshold     = 3
          }

          # Security context
          security_context {
            run_as_user                = 0
            allow_privilege_escalation = true
            capabilities {
              add = ["NET_ADMIN", "NET_RAW"]
            }
          }
        }

        # Volumes
        volume {
          name = "netalertx-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.netalertx_data.metadata[0].name
          }
        }

        volume {
          name = "netalertx-config"
          config_map {
            name = kubernetes_config_map.netalertx_config.metadata[0].name
          }
        }

        volume {
          name = "netalertx-logs"
          empty_dir {}
        }

        volume {
          name = "netalertx-config-persistent"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.netalertx_config.metadata[0].name
          }
        }

        # Node selector to ensure it runs on a specific node if needed
        # Uncomment and modify if you want to pin to a specific node
        # node_selector = {
        #   "kubernetes.io/hostname" = "bumblebee"
        # }
      }
    }
  }
}

# NetAlertX service
resource "kubernetes_service" "netalertx" {
  depends_on = [kubernetes_deployment.netalertx]

  metadata {
    name      = "netalertx"
    namespace = "netalertx"
    labels = {
      app = "netalertx"
    }
  }

  spec {
    type = "ClusterIP"

    port {
      port        = 20211
      target_port = 20211
      protocol    = "TCP"
      name        = "http"
    }

    selector = {
      app = "netalertx"
    }
  }
}

# NetAlertX ingress
resource "kubernetes_ingress_v1" "netalertx" {
  metadata {
    name      = "netalertx"
    namespace = "netalertx"
    annotations = {
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
    }
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      host = var.netalertx_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.netalertx.metadata[0].name
              port {
                number = 20211
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.ingress_nginx,
    kubernetes_service.netalertx
  ]
}
