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
            value = "America/Los_Angeles"
          }

          env {
            name  = "HOST_WHITELIST"
            value = "sabnzbd.home,sabnzbd"
          }

          port {
            container_port = 8090
            name           = "http"
          }

          # Resource limits
          resources {
            requests = {
              cpu    = "2000m"
              memory = "6Gi"
            }
            limits = {
              cpu    = "4000m"
              memory = "10Gi"
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

          volume_mount {
            name       = "nzb-downloads"
            mount_path = "/nzb-downloads"
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
            initial_delay_seconds = 60
            period_seconds        = 20
            failure_threshold     = 10
            timeout_seconds       = 15
          }
        }

        # Volumes
        volume {
          name = "mylar-config"
          nfs {
            server = "192.168.0.2"
            path   = "/volume1/Apps/mylar"
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

        volume {
          name = "nzb-downloads"
          nfs {
            server = "192.168.0.2"
            path   = "/volume2/Downloads/sabnzbd/comics"
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

# =============================================================================
# SABnzbd - Usenet Downloader
# =============================================================================

# SABnzbd Deployment
resource "kubernetes_deployment" "sabnzbd" {
  depends_on       = [kubernetes_namespace.media]
  wait_for_rollout = false

  metadata {
    name      = "sabnzbd"
    namespace = "media"
    labels = {
      app = "sabnzbd"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "sabnzbd"
      }
    }

    template {
      metadata {
        labels = {
          app = "sabnzbd"
        }
      }

      spec {
        # Security context for NFS access
        security_context {
          fs_group = 1000
        }

        container {
          name  = "sabnzbd"
          image = "bmoorman/sabnzbd:latest"

          # Environment variables
          env {
            name  = "SABNZBD_UID"
            value = "1000"
          }

          env {
            name  = "SABNZBD_GID"
            value = "1000"
          }

          env {
            name  = "TZ"
            value = "America/Los_Angeles"
          }

          env {
            name  = "HOST_WHITELIST_ENTRIES"
            value = "sabnzbd.home,sabnzbd,localhost"
          }

          env {
            name  = "SABNZBD_HOST"
            value = "0.0.0.0"
          }

          env {
            name  = "SABNZBD_PORT"
            value = "8080"
          }

          port {
            container_port = 8080
            name           = "http"
          }

          # Resource limits
          resources {
            requests = {
              cpu    = "150m"
              memory = "1.5Gi"
            }
            limits = {
              cpu    = "1500m"
              memory = "3Gi"
            }
          }

          # Volume mounts
          volume_mount {
            name       = "sabnzbd-config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "sabnzbd-data"
            mount_path = "/data"
          }

          volume_mount {
            name       = "sabnzbd-downloads"
            mount_path = "/downloads"
          }

          # Health checks
          liveness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 60
            period_seconds        = 30
            timeout_seconds       = 15
            failure_threshold     = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 60
            period_seconds        = 20
            timeout_seconds       = 15
            failure_threshold     = 10
          }
        }

        # Volumes
        volume {
          name = "sabnzbd-config"
          nfs {
            server = "192.168.0.2"
            path   = "/volume1/Apps/sabnzbd"
          }
        }

        volume {
          name = "sabnzbd-data"
          nfs {
            server = "192.168.0.2"
            path   = "/volume2/Downloads/sabnzbd"
          }
        }

        volume {
          name = "sabnzbd-downloads"
          nfs {
            server = "192.168.0.2"
            path   = "/volume2/Downloads/sabnzbd"
          }
        }
      }
    }
  }
}

# SABnzbd Service
resource "kubernetes_service" "sabnzbd" {
  depends_on = [kubernetes_deployment.sabnzbd]

  metadata {
    name      = "sabnzbd"
    namespace = "media"
    labels = {
      app = "sabnzbd"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "sabnzbd"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }
  }
}

# =============================================================================
# Prowlarr - Indexer Manager
# =============================================================================

# Prowlarr Deployment
resource "kubernetes_deployment" "prowlarr" {
  depends_on       = [kubernetes_namespace.media]
  wait_for_rollout = false

  metadata {
    name      = "prowlarr"
    namespace = "media"
    labels = {
      app = "prowlarr"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "prowlarr"
      }
    }

    template {
      metadata {
        labels = {
          app = "prowlarr"
        }
      }

      spec {
        # Security context for NFS access
        security_context {
          fs_group = 1000
        }

        # DNS configuration to work around Alpine/musl-libc DNS issues
        dns_policy = "None"
        dns_config {
          nameservers = ["10.96.0.10", "1.1.1.1", "8.8.8.8"]
          searches    = ["media.svc.cluster.local", "svc.cluster.local", "cluster.local"]
          option {
            name  = "ndots"
            value = "5"
          }
        }

        container {
          name  = "prowlarr"
          image = "lscr.io/linuxserver/prowlarr:latest"

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
            value = "America/Los_Angeles"
          }

          port {
            container_port = 9696
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
              memory = "1Gi"
            }
          }

          # Volume mounts
          volume_mount {
            name       = "prowlarr-config"
            mount_path = "/config"
          }

          # Health checks
          liveness_probe {
            http_get {
              path = "/"
              port = 9696
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 9696
            }
            initial_delay_seconds = 15
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }
        }

        # Volumes
        volume {
          name = "prowlarr-config"
          nfs {
            server = "192.168.0.2"
            path   = "/volume1/Apps/prowlarr"
          }
        }
      }
    }
  }
}

# Prowlarr Service
resource "kubernetes_service" "prowlarr" {
  depends_on = [kubernetes_deployment.prowlarr]

  metadata {
    name      = "prowlarr"
    namespace = "media"
    labels = {
      app = "prowlarr"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "prowlarr"
    }

    port {
      name        = "http"
      port        = 9696
      target_port = 9696
      protocol    = "TCP"
    }
  }
}

# =============================================================================
# Radarr - Movie Manager
# =============================================================================

# Radarr Deployment
resource "kubernetes_deployment" "radarr" {
  depends_on       = [kubernetes_namespace.media]
  wait_for_rollout = false

  metadata {
    name      = "radarr"
    namespace = "media"
    labels = {
      app = "radarr"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "radarr"
      }
    }

    template {
      metadata {
        labels = {
          app = "radarr"
        }
      }

      spec {
        # Security context for NFS access
        security_context {
          fs_group = 1000
        }

        # DNS configuration to work around Alpine/musl-libc DNS issues
        dns_policy = "None"
        dns_config {
          nameservers = ["10.96.0.10", "1.1.1.1", "8.8.8.8"]
          searches    = ["media.svc.cluster.local", "svc.cluster.local", "cluster.local"]
          option {
            name  = "ndots"
            value = "5"
          }
        }

        container {
          name  = "radarr"
          image = "lscr.io/linuxserver/radarr:latest"

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
            value = "America/Los_Angeles"
          }

          port {
            container_port = 7878
            name           = "http"
          }

          # Resource limits
          resources {
            requests = {
              cpu    = "2000m"
              memory = "6Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "12Gi"
            }
          }

          # Volume mounts
          volume_mount {
            name       = "radarr-config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "radarr-movies"
            mount_path = "/movies"
          }

          volume_mount {
            name       = "radarr-downloads"
            mount_path = "/downloads"
          }

          # Health checks
          liveness_probe {
            http_get {
              path = "/ping"
              port = 7878
            }
            initial_delay_seconds = 60
            period_seconds        = 30
            timeout_seconds       = 15
            failure_threshold     = 10
          }

          readiness_probe {
            http_get {
              path = "/ping"
              port = 7878
            }
            initial_delay_seconds = 60
            period_seconds        = 20
            timeout_seconds       = 15
            failure_threshold     = 10
          }
        }

        # Volumes
        volume {
          name = "radarr-config"
          nfs {
            server = "192.168.0.2"
            path   = "/volume1/Apps/radarr"
          }
        }

        volume {
          name = "radarr-movies"
          nfs {
            server = "192.168.0.11"
            path   = "/mnt/vpool/video/video"
          }
        }

        volume {
          name = "radarr-downloads"
          nfs {
            server = "192.168.0.2"
            path   = "/volume2/Downloads/sabnzbd/movies"
          }
        }
      }
    }
  }
}

# Radarr Service
resource "kubernetes_service" "radarr" {
  depends_on = [kubernetes_deployment.radarr]

  metadata {
    name      = "radarr"
    namespace = "media"
    labels = {
      app = "radarr"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "radarr"
    }

    port {
      name        = "http"
      port        = 7878
      target_port = 7878
      protocol    = "TCP"
    }
  }
}

