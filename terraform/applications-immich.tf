# Immich Photo/Video Management
# This file contains Immich application deployment and related resources

# =============================================================================
# Immich Namespace
# =============================================================================

# Create namespace for Immich applications
resource "kubernetes_namespace" "immich" {
  depends_on = [null_resource.kubeconfig_ready, null_resource.cluster_api_ready]

  metadata {
    name = "immich"
    labels = {
      name = "immich"
    }
  }
}

# =============================================================================
# Immich PostgreSQL Secret
# =============================================================================

resource "kubernetes_secret" "immich_postgres_secret" {
  depends_on = [kubernetes_namespace.immich]

  metadata {
    name      = "immich-postgres-secret"
    namespace = "immich"
  }

  data = {
    POSTGRES_PASSWORD = var.immich_db_password
  }

  type = "Opaque"
}

# =============================================================================
# Immich PostgreSQL Database
# =============================================================================

# PostgreSQL Deployment with pgvecto.rs
resource "kubernetes_deployment" "immich_postgres" {
  depends_on       = [kubernetes_namespace.immich]
  wait_for_rollout = false

  metadata {
    name      = "immich-postgres"
    namespace = "immich"
    labels = {
      app = "immich-postgres"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "immich-postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "immich-postgres"
        }
      }

      spec {
        container {
          name  = "immich-postgres"
          image = "tensorchord/pgvecto-rs:pg16-v0.2.0"

          # Environment variables
          env {
            name  = "POSTGRES_DB"
            value = "immich"
          }

          env {
            name  = "POSTGRES_USER"
            value = "immich"
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = "immich-postgres-secret"
                key  = "POSTGRES_PASSWORD"
              }
            }
          }

          env {
            name  = "POSTGRES_INITDB_ARGS"
            value = "--data-checksums"
          }

          port {
            container_port = 5432
            name           = "postgres"
          }

          # Resource limits
          resources {
            requests = {
              cpu    = "500m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "1000m"
              memory = "4Gi"
            }
          }

          # Volume mounts
          volume_mount {
            name       = "immich-postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }

          # Health checks
          readiness_probe {
            tcp_socket {
              port = 5432
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          liveness_probe {
            tcp_socket {
              port = 5432
            }
            initial_delay_seconds = 60
            period_seconds        = 30
          }
        }

        # Volumes
        volume {
          name = "immich-postgres-data"
          nfs {
            server = "192.168.0.2"
            path   = "/volume1/Apps/immich/postgres"
          }
        }
      }
    }
  }
}

# =============================================================================
# Immich PostgreSQL Service
# =============================================================================

resource "kubernetes_service" "immich_postgres" {
  depends_on = [kubernetes_deployment.immich_postgres]

  metadata {
    name      = "immich-postgres"
    namespace = "immich"
    labels = {
      app = "immich-postgres"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "immich-postgres"
    }

    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
      protocol    = "TCP"
    }
  }
}

# =============================================================================
# Immich Redis Cache
# =============================================================================

# Redis Deployment
resource "kubernetes_deployment" "immich_redis" {
  depends_on       = [kubernetes_namespace.immich]
  wait_for_rollout = false

  metadata {
    name      = "immich-redis"
    namespace = "immich"
    labels = {
      app = "immich-redis"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "immich-redis"
      }
    }

    template {
      metadata {
        labels = {
          app = "immich-redis"
        }
      }

      spec {
        container {
          name  = "immich-redis"
          image = "redis:7-alpine"

          port {
            container_port = 6379
            name           = "redis"
          }

          # Resource limits
          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          # Volume mounts
          volume_mount {
            name       = "immich-redis-data"
            mount_path = "/data"
          }

          # Health checks
          readiness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }

          liveness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }
        }

        # Volumes
        volume {
          name = "immich-redis-data"
          nfs {
            server = "192.168.0.2"
            path   = "/volume1/Apps/immich/redis"
          }
        }
      }
    }
  }
}

# =============================================================================
# Immich Redis Service
# =============================================================================

resource "kubernetes_service" "immich_redis" {
  depends_on = [kubernetes_deployment.immich_redis]

  metadata {
    name      = "immich-redis"
    namespace = "immich"
    labels = {
      app = "immich-redis"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "immich-redis"
    }

    port {
      name        = "redis"
      port        = 6379
      target_port = 6379
      protocol    = "TCP"
    }
  }
}

# =============================================================================
# Immich Machine Learning
# =============================================================================

# Immich ML Deployment
resource "kubernetes_deployment" "immich_machine_learning" {
  depends_on       = [kubernetes_namespace.immich]
  wait_for_rollout = false

  metadata {
    name      = "immich-machine-learning"
    namespace = "immich"
    labels = {
      app = "immich-machine-learning"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "immich-machine-learning"
      }
    }

    template {
      metadata {
        labels = {
          app = "immich-machine-learning"
        }
      }

      spec {
        container {
          name  = "immich-machine-learning"
          image = "ghcr.io/immich-app/immich-machine-learning:release"

          # Environment variables
          env {
            name  = "IMMICH_HOST"
            value = "0.0.0.0"
          }

          env {
            name  = "IMMICH_PORT"
            value = "3003"
          }

          port {
            container_port = 3003
            name           = "http"
          }

          # Resource limits
          resources {
            requests = {
              cpu    = "1000m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }

          # Volume mounts
          volume_mount {
            name       = "immich-ml-cache"
            mount_path = "/cache"
          }

          # Health checks
          readiness_probe {
            http_get {
              path = "/ping"
              port = 3003
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/ping"
              port = 3003
            }
            initial_delay_seconds = 60
            period_seconds        = 30
            failure_threshold     = 5
          }
        }

        # Volumes
        volume {
          name = "immich-ml-cache"
          nfs {
            server = "192.168.0.2"
            path   = "/volume1/Apps/immich/ml-cache"
          }
        }
      }
    }
  }
}

# =============================================================================
# Immich Machine Learning Service
# =============================================================================

resource "kubernetes_service" "immich_machine_learning" {
  depends_on = [kubernetes_deployment.immich_machine_learning]

  metadata {
    name      = "immich-machine-learning"
    namespace = "immich"
    labels = {
      app = "immich-machine-learning"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "immich-machine-learning"
    }

    port {
      name        = "http"
      port        = 3003
      target_port = 3003
      protocol    = "TCP"
    }
  }
}

# =============================================================================
# Immich Server
# =============================================================================

# Immich Server Deployment
resource "kubernetes_deployment" "immich_server" {
  depends_on       = [kubernetes_namespace.immich, kubernetes_deployment.immich_postgres, kubernetes_deployment.immich_redis, kubernetes_deployment.immich_machine_learning]
  wait_for_rollout = false

  metadata {
    name      = "immich-server"
    namespace = "immich"
    labels = {
      app = "immich-server"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "immich-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "immich-server"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8081"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        security_context {
          fs_group = 1000
        }

        container {
          name  = "immich-server"
          image = "ghcr.io/immich-app/immich-server:release"

          # Environment variables
          env {
            name  = "DB_URL"
            value = "postgresql://immich:${var.immich_db_password}@immich-postgres.immich.svc.cluster.local:5432/immich"
          }

          env {
            name  = "REDIS_HOSTNAME"
            value = "immich-redis.immich.svc.cluster.local"
          }

          env {
            name  = "IMMICH_MACHINE_LEARNING_URL"
            value = "http://immich-machine-learning.immich.svc.cluster.local:3003"
          }

          env {
            name  = "UPLOAD_LOCATION"
            value = "/usr/src/app/upload"
          }

          env {
            name  = "TZ"
            value = "America/Los_Angeles"
          }

          # Enable all Prometheus telemetry metrics
          env {
            name  = "IMMICH_TELEMETRY_INCLUDE"
            value = "all"
          }

          env {
            name  = "IMMICH_API_METRICS_PORT"
            value = "8081"
          }

          port {
            container_port = 2283
            name           = "http"
          }

          port {
            container_port = 8081
            name           = "metrics"
          }

          # Resource limits
          resources {
            requests = {
              cpu    = "1000m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }

          # Volume mounts
          volume_mount {
            name       = "photography-library"
            mount_path = "/mnt/media/photography"
          }

          volume_mount {
            name       = "my-life-library"
            mount_path = "/mnt/media/my-life"
          }

          volume_mount {
            name       = "immich-upload"
            mount_path = "/usr/src/app/upload"
          }

          # Health checks
          readiness_probe {
            http_get {
              path = "/api/server/ping"
              port = 2283
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 5
          }

          liveness_probe {
            http_get {
              path = "/api/server/ping"
              port = 2283
            }
            initial_delay_seconds = 60
            period_seconds        = 30
            failure_threshold     = 10
          }
        }

        # Volumes
        volume {
          name = "photography-library"
          nfs {
            server = "192.168.0.11"
            path   = "/mnt/vpool/image-main/Photography"
          }
        }

        volume {
          name = "my-life-library"
          nfs {
            server = "192.168.0.11"
            path   = "/mnt/vpool/image-main/my-life"
          }
        }

        volume {
          name = "immich-upload"
          nfs {
            server = "192.168.0.2"
            path   = "/volume1/Apps/immich/upload"
          }
        }
      }
    }
  }
}

# =============================================================================
# Immich Server Service
# =============================================================================

resource "kubernetes_service" "immich_server" {
  depends_on = [kubernetes_deployment.immich_server]

  metadata {
    name      = "immich-server"
    namespace = "immich"
    labels = {
      app = "immich-server"
    }
    annotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "8081"
      "prometheus.io/path"   = "/metrics"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "immich-server"
    }

    port {
      name        = "http"
      port        = 2283
      target_port = 2283
      protocol    = "TCP"
    }

    port {
      name        = "metrics"
      port        = 8081
      target_port = 8081
      protocol    = "TCP"
    }
  }
}

# =============================================================================
# Immich Ingress
# =============================================================================

resource "kubernetes_ingress_v1" "immich" {
  metadata {
    name      = "immich"
    namespace = "immich"
    annotations = {
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "0"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "600"
      "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTP"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = var.immich_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.immich_server.metadata[0].name
              port {
                number = 2283
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.ingress_nginx,
    kubernetes_service.immich_server
  ]
}

# =============================================================================
# Immich Database Backup CronJob
# =============================================================================

resource "kubernetes_cron_job_v1" "immich_db_backup" {
  depends_on = [kubernetes_config_map.backup_scripts, kubernetes_service_account.backup]

  metadata {
    name      = "immich-db-backup"
    namespace = "backup"
    labels = {
      app = "immich-db-backup"
    }
  }

  spec {
    schedule                      = "30 2 * * *"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 1

    job_template {
      metadata {
        labels = {
          app = "immich-db-backup"
        }
      }

      spec {
        template {
          metadata {
            labels = {
              app = "immich-db-backup"
            }
          }

          spec {
            service_account_name = "backup"
            restart_policy       = "OnFailure"

            container {
              name    = "immich-db-backup"
              image   = "postgres:16-alpine"
              command = ["/bin/sh"]
              args    = ["/scripts/immich-db-backup.sh"]

              env {
                name  = "PGPASSWORD"
                value = var.immich_db_password
              }

              volume_mount {
                name       = "backup-scripts"
                mount_path = "/scripts"
              }

              volume_mount {
                name       = "backup-storage"
                mount_path = "/backup"
              }

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
            }

            volume {
              name = "backup-scripts"
              config_map {
                name         = "backup-scripts"
                default_mode = "0755"
              }
            }

            volume {
              name = "backup-storage"
              nfs {
                server = "192.168.0.2"
                path   = "/volume1/Apps/kube-backups/immich"
              }
            }
          }
        }
      }
    }
  }
}

# =============================================================================
# Immich Upload Backup CronJob
# =============================================================================

resource "kubernetes_cron_job_v1" "immich_upload_backup" {
  depends_on = [kubernetes_config_map.backup_scripts, kubernetes_service_account.backup]

  metadata {
    name      = "immich-upload-backup"
    namespace = "backup"
    labels = {
      app = "immich-upload-backup"
    }
  }

  spec {
    schedule                      = "30 3 * * *"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 1

    job_template {
      metadata {
        labels = {
          app = "immich-upload-backup"
        }
      }

      spec {
        template {
          metadata {
            labels = {
              app = "immich-upload-backup"
            }
          }

          spec {
            service_account_name = "backup"
            restart_policy       = "OnFailure"

            container {
              name    = "immich-upload-backup"
              image   = "alpine:3.18"
              command = ["/bin/sh"]
              args    = ["/scripts/immich-upload-backup.sh"]

              volume_mount {
                name       = "backup-scripts"
                mount_path = "/scripts"
              }

              volume_mount {
                name       = "immich-upload-source"
                mount_path = "/source/upload"
                read_only  = true
              }

              volume_mount {
                name       = "backup-storage"
                mount_path = "/backup"
              }

              resources {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "1000m"
                  memory = "1Gi"
                }
              }
            }

            volume {
              name = "backup-scripts"
              config_map {
                name         = "backup-scripts"
                default_mode = "0755"
              }
            }

            volume {
              name = "immich-upload-source"
              nfs {
                server = "192.168.0.2"
                path   = "/volume1/Apps/immich/upload"
              }
            }

            volume {
              name = "backup-storage"
              nfs {
                server = "192.168.0.2"
                path   = "/volume1/Apps/kube-backups/immich"
              }
            }
          }
        }
      }
    }
  }
}
