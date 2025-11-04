# Kubernetes Ingress Resources
# This file contains all Ingress resource definitions for services

# =============================================================================
# Monitoring Ingress Resources
# =============================================================================

# Grafana Ingress
resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = "monitoring"
    annotations = {
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
    }
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      host = var.grafana_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.grafana.metadata[0].name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.ingress_nginx,
    kubernetes_service.grafana
  ]
}

# Prometheus Ingress
resource "kubernetes_ingress_v1" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = "monitoring"
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      host = var.prometheus_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.prometheus.metadata[0].name
              port {
                number = 9090
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.ingress_nginx,
    kubernetes_service.prometheus
  ]
}

# Loki Ingress
resource "kubernetes_ingress_v1" "loki" {
  metadata {
    name      = "loki"
    namespace = "monitoring"
    annotations = {
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
    }
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      host = var.loki_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.loki.metadata[0].name
              port {
                number = 3100
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.ingress_nginx,
    kubernetes_service.loki
  ]
}

# Mimir (query-frontend) Ingress
resource "kubernetes_ingress_v1" "mimir" {
  metadata {
    name      = "mimir"
    namespace = "monitoring"
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      host = var.mimir_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.mimir_query_frontend.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.ingress_nginx,
    kubernetes_service.mimir_query_frontend
  ]
}

# =============================================================================
# Application Ingress Resources
# =============================================================================

# Mylar Ingress
resource "kubernetes_ingress_v1" "mylar" {
  metadata {
    name      = "mylar"
    namespace = "media"
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      host = var.mylar_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.mylar.metadata[0].name
              port {
                number = 8090
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.ingress_nginx,
    kubernetes_service.mylar
  ]
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

