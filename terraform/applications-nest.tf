# Nest Data Application
# Collects Google Nest thermostat data and stores in PostgreSQL
#
# Configuration: Create configs/nest/.env with your credentials:
#   CLIENT_SECRET_FILE=/secrets/client_secret.json
#   REDIRECT_URI=http://nest.home/auth/callback
#   PROJECT_ID=your-google-project-id
#   DB_HOST=nest-postgres
#   DB_USER=nest
#   DB_NAME=nest_data
#   DB_PASSWORD=your-db-password
#   DB_PORT=5432
#
# Also place your Google OAuth client_secret.json in configs/nest/

# =============================================================================
# Nest Namespace
# =============================================================================

resource "kubernetes_namespace" "nest" {
  depends_on = [null_resource.kubeconfig_ready, null_resource.cluster_api_ready]

  metadata {
    name = "nest"
    labels = {
      name = "nest"
    }
  }
}

# =============================================================================
# Nest Secrets - loaded from config files
# =============================================================================

resource "kubernetes_secret" "nest_env" {
  depends_on = [kubernetes_namespace.nest]

  metadata {
    name      = "nest-env"
    namespace = "nest"
  }

  data = {
    ".env" = file("${path.root}/../configs/nest/.env")
  }
}

resource "kubernetes_secret" "nest_google_credentials" {
  depends_on = [kubernetes_namespace.nest]

  metadata {
    name      = "nest-google-credentials"
    namespace = "nest"
  }

  data = {
    "client_secret.json" = file("${path.root}/../configs/nest/client_secret.json")
  }
}

# =============================================================================
# PostgreSQL for Nest Data
# =============================================================================

resource "kubernetes_persistent_volume_claim" "nest_postgres" {
  depends_on = [kubernetes_namespace.nest]

  metadata {
    name      = "nest-postgres-pvc"
    namespace = "nest"
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "nfs-storage"
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "nest_postgres" {
  depends_on       = [kubernetes_namespace.nest, kubernetes_persistent_volume_claim.nest_postgres, kubernetes_secret.nest_env]
  wait_for_rollout = false

  metadata {
    name      = "nest-postgres"
    namespace = "nest"
    labels = {
      app = "nest-postgres"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "nest-postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "nest-postgres"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:15-alpine"

          # Use shell to extract password from .env and set it
          command = ["/bin/sh", "-c"]
          args = [
            "export POSTGRES_PASSWORD=$(grep DB_PASSWORD /env/.env | cut -d'=' -f2) && exec docker-entrypoint.sh postgres"
          ]

          env {
            name  = "POSTGRES_USER"
            value = "nest"
          }

          env {
            name  = "POSTGRES_DB"
            value = "nest_data"
          }

          port {
            container_port = 5432
            name           = "postgres"
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

          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }

          volume_mount {
            name       = "nest-env"
            mount_path = "/env"
            read_only  = true
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "nest", "-d", "nest_data"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "nest", "-d", "nest_data"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }
        }

        volume {
          name = "postgres-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.nest_postgres.metadata[0].name
          }
        }

        volume {
          name = "nest-env"
          secret {
            secret_name = kubernetes_secret.nest_env.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "nest_postgres" {
  depends_on = [kubernetes_deployment.nest_postgres]

  metadata {
    name      = "nest-postgres"
    namespace = "nest"
    labels = {
      app = "nest-postgres"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "nest-postgres"
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
# Nest Data Application
# =============================================================================

resource "kubernetes_deployment" "nest_data" {
  depends_on       = [kubernetes_namespace.nest, kubernetes_service.nest_postgres, kubernetes_secret.nest_env]
  wait_for_rollout = false

  metadata {
    name      = "nest-data"
    namespace = "nest"
    labels = {
      app = "nest-data"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "nest-data"
      }
    }

    template {
      metadata {
        labels = {
          app = "nest-data"
        }
      }

      spec {
        security_context {
          fs_group = 1000
        }

        container {
          name              = "nest-data"
          image             = "${var.registry_node_ip}:${var.registry_node_port}/nest-data:latest"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = 8080
            name           = "http"
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

          volume_mount {
            name       = "nest-env"
            mount_path = "/app/.env"
            sub_path   = ".env"
            read_only  = true
          }

          volume_mount {
            name       = "google-credentials"
            mount_path = "/secrets"
            read_only  = true
          }

          volume_mount {
            name       = "nest-tokens"
            mount_path = "/app/tokens"
          }

          liveness_probe {
            http_get {
              path = "/docs"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/docs"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }
        }

        volume {
          name = "nest-env"
          secret {
            secret_name = kubernetes_secret.nest_env.metadata[0].name
          }
        }

        volume {
          name = "google-credentials"
          secret {
            secret_name = kubernetes_secret.nest_google_credentials.metadata[0].name
          }
        }

        volume {
          name = "nest-tokens"
          nfs {
            server = var.nfs_storage_server
            path   = "${var.nfs_storage_path}/nest-tokens"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "nest_data" {
  depends_on = [kubernetes_deployment.nest_data]

  metadata {
    name      = "nest-data"
    namespace = "nest"
    labels = {
      app = "nest-data"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "nest-data"
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
# Nest Data Ingress
# =============================================================================

resource "kubernetes_ingress_v1" "nest_data" {
  depends_on = [kubernetes_service.nest_data]

  metadata {
    name      = "nest-data"
    namespace = "nest"
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      host = var.nest_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.nest_data.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}
