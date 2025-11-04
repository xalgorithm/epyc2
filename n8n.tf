# N8N Workflow Automation
# Deploys n8n workflow automation tool in the automation namespace

# Automation Namespace
resource "kubernetes_namespace" "automation" {
  depends_on = [null_resource.kubeconfig_ready, null_resource.cluster_api_ready]

  metadata {
    name = "automation"
    labels = {
      name = "automation"
    }
  }
}

# N8N Storage PVC
resource "kubernetes_persistent_volume_claim" "n8n_storage" {
  metadata {
    name      = "n8n-storage"
    namespace = "automation"
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "10Gi"
      }
    }

    storage_class_name = "nfs-storage"
  }

  depends_on = [
    kubernetes_namespace.automation,
    helm_release.nfs_csi_driver,
    kubernetes_storage_class.nfs_storage_class
  ]

  timeouts {
    create = "15m"
  }
}

# N8N Deployment
resource "kubernetes_deployment" "n8n" {
  depends_on = [
    kubernetes_persistent_volume_claim.n8n_storage
  ]
  wait_for_rollout = false

  metadata {
    name      = "n8n"
    namespace = "automation"
    labels = {
      app = "n8n"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "n8n"
      }
    }

    template {
      metadata {
        labels = {
          app = "n8n"
        }
      }

      spec {
        # Init container to fix permissions
        init_container {
          name  = "n8n-init"
          image = "busybox:1.35"

          command = [
            "sh",
            "-c",
            "mkdir -p /home/node/.n8n && chown -R 1000:1000 /home/node/.n8n && chmod -R 755 /home/node/.n8n"
          ]

          volume_mount {
            name       = "n8n-data"
            mount_path = "/home/node/.n8n"
          }

          security_context {
            run_as_user = 0
          }
        }

        container {
          name  = "n8n"
          image = "n8nio/n8n:latest"

          port {
            container_port = 5678
            name           = "http"
          }

          env {
            name  = "N8N_BASIC_AUTH_ACTIVE"
            value = "true"
          }

          env {
            name  = "N8N_BASIC_AUTH_USER"
            value = "admin"
          }

          env {
            name  = "N8N_BASIC_AUTH_PASSWORD"
            value = "automate"
          }

          env {
            name  = "N8N_HOST"
            value = "automate.home"
          }

          env {
            name  = "N8N_PORT"
            value = "5678"
          }

          env {
            name  = "N8N_PROTOCOL"
            value = "http"
          }

          env {
            name  = "WEBHOOK_URL"
            value = "http://automate.home/"
          }

          env {
            name  = "N8N_SECURE_COOKIE"
            value = "false"
          }

          env {
            name  = "GENERIC_TIMEZONE"
            value = "America/New_York"
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

          volume_mount {
            name       = "n8n-data"
            mount_path = "/home/node/.n8n"
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 5678
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 5678
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }
        }

        volume {
          name = "n8n-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.n8n_storage.metadata[0].name
          }
        }
      }
    }
  }
}

# N8N Service
resource "kubernetes_service" "n8n" {
  depends_on = [kubernetes_deployment.n8n]

  metadata {
    name      = "n8n"
    namespace = "automation"
    labels = {
      app = "n8n"
    }
  }

  spec {
    type = "ClusterIP"

    port {
      port        = 5678
      target_port = 5678
      protocol    = "TCP"
      name        = "http"
    }

    selector = {
      app = "n8n"
    }
  }
}

# N8N Ingress
resource "kubernetes_ingress_v1" "n8n" {
  depends_on = [kubernetes_service.n8n]

  metadata {
    name      = "n8n"
    namespace = "automation"
    annotations = {
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "automate.home"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.n8n.metadata[0].name
              port {
                number = 5678
              }
            }
          }
        }
      }
    }
  }
}

# Output N8N information
output "n8n_info" {
  description = "N8N access information"
  value = {
    url         = "http://automate.home"
    username    = "admin"
    password    = "automate"
    namespace   = "automation"
    ingress_ip  = "192.168.0.35"
  }
}

