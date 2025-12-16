# Media Applications
# This file contains media-related application deployments (Mylar)

# =============================================================================
# Media Namespace
# =============================================================================

# Create namespace for Media applications
resource "kubernetes_namespace" "media" {
  depends_on = [null_resource.kubeconfig_ready, null_resource.cluster_api_ready]

  metadata {
    name = "media"
    labels = {
      name = "media"
    }
  }
}

# =============================================================================
# Mylar - Comic Book Manager
# =============================================================================

# Mylar Deployment
resource "kubernetes_deployment" "mylar" {
  depends_on       = [kubernetes_namespace.media]
  wait_for_rollout = false

  metadata {
    name      = "mylar"
    namespace = "media"
    labels = {
      app = "mylar"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "mylar"
      }
    }

    template {
      metadata {
        labels = {
          app = "mylar"
        }
      }

      spec {
        # Security context for NFS access
        security_context {
          fs_group = 1000
        }

        container {
          name  = "mylar"
          image = "lscr.io/linuxserver/mylar3:latest"

          # Environment variables
          env {
            name  = "PUID"
            value = "1000"
          }

          env {
            name  = "PGID"
            value = "1000"
          }

          env {
            name  = "TZ"
            value = "America/New_York"
          }

          port {
            container_port = 8090
            name           = "http"
          }

          # Resource limits
          resources {
            requests = {
              cpu    = "100m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }

          # Volume mounts
          volume_mount {
            name       = "mylar-config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "mylar-data"
            mount_path = "/data"
          }

          volume_mount {
            name       = "mylar-comics"
            mount_path = "/comics"
          }

          volume_mount {
            name       = "mylar-downloads"
            mount_path = "/downloads"
          }

          # Health checks
          liveness_probe {
            http_get {
              path = "/"
              port = 8090
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 8090
            }
            initial_delay_seconds = 15
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }
        }

        # Volumes
        volume {
          name = "mylar-config"
          host_path {
            path = "/opt/mylar-config"
            type = "DirectoryOrCreate"
          }
        }

        volume {
          name = "mylar-data"
          nfs {
            server = var.nfs_storage_server
            path   = var.nfs_storage_path
          }
        }

        volume {
          name = "mylar-comics"
          nfs {
            server = "192.168.0.3"
            path   = "/mnt/red-nas/comics/Comics"
          }
        }

        volume {
          name = "mylar-downloads"
          nfs {
            server = var.nfs_storage_server
            path   = "${var.nfs_storage_path}/mylar-downloads"
          }
        }
      }
    }
  }
}

# Mylar Service
resource "kubernetes_service" "mylar" {
  depends_on = [kubernetes_deployment.mylar]

  metadata {
    name      = "mylar"
    namespace = "media"
    labels = {
      app = "mylar"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "mylar"
    }

    port {
      name        = "http"
      port        = 8090
      target_port = 8090
      protocol    = "TCP"
    }
  }
}

