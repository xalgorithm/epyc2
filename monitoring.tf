# Monitoring Namespace
resource "kubernetes_namespace" "monitoring" {
  depends_on = [null_resource.kubeconfig_ready, null_resource.cluster_api_ready]

  metadata {
    name = "monitoring"
    labels = {
      name = "monitoring"
    }
  }
}

# Prometheus Storage PVC (only create if cluster is accessible)
resource "kubernetes_persistent_volume_claim" "prometheus_storage" {
  # Skip creation if cluster is not accessible
  count = 1

  metadata {
    name      = "prometheus-storage"
    namespace = "monitoring"
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "50Gi"
      }
    }

    storage_class_name = "nfs-storage"
  }

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.nfs_csi_driver,
    kubernetes_storage_class.nfs_storage_class,
    null_resource.check_nfs_storage,
    null_resource.check_cluster_connectivity
  ]

  timeouts {
    create = "15m"
  }
}

# Grafana Storage PVC (only create if cluster is accessible)
resource "kubernetes_persistent_volume_claim" "grafana_storage" {
  # Skip creation if cluster is not accessible
  count = 1

  metadata {
    name      = "grafana-storage"
    namespace = "monitoring"
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
    kubernetes_namespace.monitoring,
    helm_release.nfs_csi_driver,
    kubernetes_storage_class.nfs_storage_class,
    null_resource.check_nfs_storage,
    null_resource.check_cluster_connectivity
  ]

  timeouts {
    create = "15m"
  }
}

# Docker Hub Secret for Image Pulling
resource "kubernetes_secret" "dockerhub_secret" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "dockerhub-secret"
    namespace = "monitoring"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "https://index.docker.io/v1/" = {
          username = var.dockerhub_username
          password = var.dockerhub_password
          email    = var.dockerhub_email
          auth     = base64encode("${var.dockerhub_username}:${var.dockerhub_password}")
        }
      }
    })
  }
}

# Grafana Dashboard Provisioning ConfigMap
resource "kubernetes_config_map" "grafana_dashboard_provisioning" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "grafana-dashboard-provisioning"
    namespace = "monitoring"
  }

  data = {
    "dashboards.yml" = file("${path.module}/configs/grafana/grafana-dashboards.yml")
  }
}

# Grafana Dashboards ConfigMap
resource "kubernetes_config_map" "grafana_dashboards" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "grafana-dashboards"
    namespace = "monitoring"
  }

  data = {
    # Original dashboards
    "homelab-dashboard.json"       = file("${path.module}/configs/grafana/homelab-dashboard.json")
    "prometheus-dashboard.json"    = file("${path.module}/configs/grafana/prometheus-dashboard.json")
    "loki-logs-dashboard.json"     = file("${path.module}/configs/grafana/loki-logs-dashboard.json")
    "mimir-dashboard.json"         = file("${path.module}/configs/grafana/mimir-dashboard.json")
    "node-exporter-dashboard.json" = file("${path.module}/configs/grafana/node-exporter-dashboard.json")
    "proxmox-dashboard.json"       = file("${path.module}/configs/grafana/proxmox-dashboard.json")
    "backup-dashboard.json"        = file("${path.module}/configs/grafana/backup-dashboard.json")

    # Comprehensive Kubernetes dashboards
    "kubernetes-cluster-overview.json"    = file("${path.module}/configs/grafana/kubernetes-cluster-overview.json")
    "kubernetes-pods-workloads.json"      = file("${path.module}/configs/grafana/kubernetes-pods-workloads.json")
    "kubernetes-logs-analysis.json"       = file("${path.module}/configs/grafana/kubernetes-logs-analysis.json")
    "kubernetes-resource-monitoring.json" = file("${path.module}/configs/grafana/kubernetes-resource-monitoring.json")
    "kubernetes-events-alerts.json"       = file("${path.module}/configs/grafana/kubernetes-events-alerts.json")

    # OPNsense Firewall & Network Monitoring Dashboards
    "opnsense-firewall-dashboard.json"  = file("${path.module}/configs/grafana/opnsense-firewall-dashboard.json")
    "opnsense-bandwidth-dashboard.json" = file("${path.module}/configs/grafana/opnsense-bandwidth-dashboard.json")
    "opnsense-security-dashboard.json"  = file("${path.module}/configs/grafana/opnsense-security-dashboard.json")
  }
}

# Prometheus Service Account
resource "kubernetes_service_account" "prometheus" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "prometheus"
    namespace = "monitoring"
  }
}

# Prometheus ClusterRole
resource "kubernetes_cluster_role" "prometheus" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name = "prometheus"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "nodes/proxy", "services", "endpoints", "pods"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    non_resource_urls = ["/metrics"]
    verbs             = ["get"]
  }
}

# Prometheus ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "prometheus" {
  depends_on = [kubernetes_cluster_role.prometheus, kubernetes_service_account.prometheus]

  metadata {
    name = "prometheus"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "prometheus"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "prometheus"
    namespace = "monitoring"
  }
}

# Prometheus ConfigMap
resource "kubernetes_config_map" "prometheus_config" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "prometheus-config"
    namespace = "monitoring"
  }

  data = {
    "prometheus.yml" = file("${path.module}/configs/prometheus/prometheus.yml")
  }
}

# Mimir ConfigMap
resource "kubernetes_config_map" "mimir_config" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "mimir-config"
    namespace = "monitoring"
  }

  data = {
    "mimir.yml" = file("${path.module}/configs/prometheus/mimir.yml")
  }
}

# Loki ConfigMap
resource "kubernetes_config_map" "loki_config" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "loki-config"
    namespace = "monitoring"
  }

  data = {
    "loki.yml" = file("${path.module}/configs/prometheus/loki.yml")
  }
}

# Promtail Service Account
resource "kubernetes_service_account" "promtail" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "promtail"
    namespace = "monitoring"
  }
}

# Promtail ClusterRole
resource "kubernetes_cluster_role" "promtail" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name = "promtail"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "nodes/proxy", "services", "endpoints", "pods"]
    verbs      = ["get", "list", "watch"]
  }
}

# Promtail ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "promtail" {
  depends_on = [kubernetes_cluster_role.promtail, kubernetes_service_account.promtail]

  metadata {
    name = "promtail"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "promtail"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "promtail"
    namespace = "monitoring"
  }
}

# Promtail ConfigMap
resource "kubernetes_config_map" "promtail_config" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "promtail-config"
    namespace = "monitoring"
  }

  data = {
    "promtail.yml" = file("${path.module}/configs/prometheus/promtail.yml")
  }
}

# Grafana ConfigMaps
resource "kubernetes_config_map" "grafana_config" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "grafana-config"
    namespace = "monitoring"
  }

  data = {
    "grafana.ini" = file("${path.module}/configs/grafana/grafana.ini")
  }
}

resource "kubernetes_config_map" "grafana_datasources" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "grafana-datasources"
    namespace = "monitoring"
  }

  data = {
    "datasources.yml" = file("${path.module}/configs/grafana/grafana-datasources.yml")
  }
}

# Mimir Deployment
resource "kubernetes_deployment" "mimir" {
  depends_on       = [kubernetes_config_map.mimir_config]
  wait_for_rollout = false

  metadata {
    name      = "mimir"
    namespace = "monitoring"
    labels = {
      app = "mimir"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "mimir"
      }
    }

    template {
      metadata {
        labels = {
          app = "mimir"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8080"
        }
      }

      spec {
        image_pull_secrets {
          name = "dockerhub-secret"
        }

        container {
          name  = "mimir"
          image = "grafana/mimir:2.9.0"
          args  = ["-config.file=/etc/mimir/mimir.yml"]

          port {
            container_port = 8080
            name           = "http"
          }

          port {
            container_port = 9095
            name           = "grpc"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }

          volume_mount {
            name       = "mimir-config"
            mount_path = "/etc/mimir"
          }

          volume_mount {
            name       = "mimir-data"
            mount_path = "/data"
          }
        }

        volume {
          name = "mimir-config"
          config_map {
            name = "mimir-config"
          }
        }

        volume {
          name = "mimir-data"
          empty_dir {}
        }
      }
    }
  }
}

# Mimir Services
resource "kubernetes_service" "mimir_distributor" {
  depends_on = [kubernetes_deployment.mimir]

  metadata {
    name      = "mimir-distributor"
    namespace = "monitoring"
    labels = {
      app = "mimir"
    }
    annotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "8080"
    }
  }

  spec {
    port {
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
      name        = "http"
    }

    port {
      port        = 9095
      target_port = 9095
      protocol    = "TCP"
      name        = "grpc"
    }

    selector = {
      app = "mimir"
    }
  }
}

resource "kubernetes_service" "mimir_query_frontend" {
  depends_on = [kubernetes_deployment.mimir]

  metadata {
    name      = "mimir-query-frontend"
    namespace = "monitoring"
    labels = {
      app = "mimir"
    }
  }

  spec {
    type = "ClusterIP"

    port {
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }

    selector = {
      app = "mimir"
    }
  }
}

# Prometheus Deployment
resource "kubernetes_deployment" "prometheus" {
  depends_on = [
    kubernetes_config_map.prometheus_config,
    kubernetes_service_account.prometheus,
    kubernetes_persistent_volume_claim.prometheus_storage[0],
    null_resource.validate_service_data
  ]
  wait_for_rollout = false

  metadata {
    name      = "prometheus"
    namespace = "monitoring"
    labels = {
      app = "prometheus"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "prometheus"
      }
    }

    template {
      metadata {
        labels = {
          app = "prometheus"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9090"
        }
      }

      spec {
        service_account_name = "prometheus"

        container {
          name  = "prometheus"
          image = "quay.io/prometheus/prometheus:v2.45.0"
          args = [
            "--config.file=/etc/prometheus/prometheus.yml",
            "--storage.tsdb.path=/prometheus/",
            "--web.console.libraries=/etc/prometheus/console_libraries",
            "--web.console.templates=/etc/prometheus/consoles",
            "--storage.tsdb.retention.time=200h",
            "--web.enable-lifecycle",
            "--web.enable-admin-api"
          ]

          port {
            container_port = 9090
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "1000Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2500Mi"
            }
          }

          volume_mount {
            name       = "prometheus-config-volume"
            mount_path = "/etc/prometheus/"
          }

          volume_mount {
            name       = "prometheus-storage-volume"
            mount_path = "/prometheus/"
          }

          security_context {
            run_as_user  = 65534
            run_as_group = 65534
          }
        }

        security_context {
          fs_group = 65534
        }

        volume {
          name = "prometheus-config-volume"
          config_map {
            default_mode = "0420"
            name         = "prometheus-config"
          }
        }

        volume {
          name = "prometheus-storage-volume"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.prometheus_storage[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Prometheus Service
resource "kubernetes_service" "prometheus" {
  depends_on = [kubernetes_deployment.prometheus]

  metadata {
    name      = "prometheus"
    namespace = "monitoring"
    labels = {
      app = "prometheus"
    }
    annotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "9090"
    }
  }

  spec {
    type = "ClusterIP"

    port {
      port        = 9090
      target_port = 9090
      protocol    = "TCP"
    }

    selector = {
      app = "prometheus"
    }
  }
}

# Loki Deployment
resource "kubernetes_deployment" "loki" {
  depends_on       = [kubernetes_config_map.loki_config]
  wait_for_rollout = false

  metadata {
    name      = "loki"
    namespace = "monitoring"
    labels = {
      app = "loki"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "loki"
      }
    }

    template {
      metadata {
        labels = {
          app = "loki"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "3100"
        }
      }

      spec {
        image_pull_secrets {
          name = "dockerhub-secret"
        }

        container {
          name  = "loki"
          image = "grafana/loki:2.6.1"
          args  = ["-config.file=/etc/loki/loki.yml"]

          port {
            container_port = 3100
            name           = "http"
          }

          port {
            container_port = 9096
            name           = "grpc"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "loki-config"
            mount_path = "/etc/loki"
          }

          volume_mount {
            name       = "loki-data"
            mount_path = "/loki"
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 3100
            }
            initial_delay_seconds = 45
          }

          liveness_probe {
            http_get {
              path = "/ready"
              port = 3100
            }
            initial_delay_seconds = 45
          }
        }

        volume {
          name = "loki-config"
          config_map {
            name = "loki-config"
          }
        }

        volume {
          name = "loki-data"
          empty_dir {}
        }
      }
    }
  }
}

# Loki Service
resource "kubernetes_service" "loki" {
  depends_on = [kubernetes_deployment.loki]

  metadata {
    name      = "loki"
    namespace = "monitoring"
    labels = {
      app = "loki"
    }
    annotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "3100"
    }
  }

  spec {
    type = "ClusterIP"

    port {
      port        = 3100
      target_port = 3100
      protocol    = "TCP"
      name        = "http"
    }

    port {
      port        = 9096
      target_port = 9096
      protocol    = "TCP"
      name        = "grpc"
    }

    selector = {
      app = "loki"
    }
  }
}

# Promtail DaemonSet
resource "kubernetes_daemonset" "promtail" {
  depends_on = [kubernetes_config_map.promtail_config, kubernetes_service_account.promtail]

  metadata {
    name      = "promtail"
    namespace = "monitoring"
    labels = {
      app = "promtail"
    }
  }

  spec {
    selector {
      match_labels = {
        app = "promtail"
      }
    }

    template {
      metadata {
        labels = {
          app = "promtail"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "3101"
        }
      }

      spec {
        service_account_name = "promtail"

        image_pull_secrets {
          name = "dockerhub-secret"
        }

        container {
          name  = "promtail"
          image = "grafana/promtail:2.6.1"
          args  = ["-config.file=/etc/promtail/promtail.yml"]

          env {
            name = "HOSTNAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          port {
            container_port = 3101
            name           = "http-metrics"
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

          volume_mount {
            name       = "promtail-config"
            mount_path = "/etc/promtail"
          }

          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }

          volume_mount {
            name       = "varlibdockercontainers"
            mount_path = "/var/lib/docker/containers"
            read_only  = true
          }

          readiness_probe {
            failure_threshold = 5
            http_get {
              path = "/ready"
              port = 3101
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            success_threshold     = 1
            timeout_seconds       = 1
          }

          liveness_probe {
            failure_threshold = 5
            http_get {
              path = "/ready"
              port = 3101
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            success_threshold     = 1
            timeout_seconds       = 1
          }
        }

        toleration {
          key      = "node-role.kubernetes.io/master"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        volume {
          name = "promtail-config"
          config_map {
            name = "promtail-config"
          }
        }

        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }

        volume {
          name = "varlibdockercontainers"
          host_path {
            path = "/var/lib/docker/containers"
          }
        }
      }
    }
  }
}

# Grafana Deployment
resource "kubernetes_deployment" "grafana" {
  depends_on = [
    kubernetes_config_map.grafana_config,
    kubernetes_config_map.grafana_datasources,
    kubernetes_config_map.grafana_dashboard_provisioning,
    kubernetes_config_map.grafana_dashboards,
    kubernetes_persistent_volume_claim.grafana_storage[0],
    null_resource.validate_service_data
  ]
  wait_for_rollout = false

  metadata {
    name      = "grafana"
    namespace = "monitoring"
    labels = {
      app = "grafana"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "grafana"
      }
    }

    template {
      metadata {
        labels = {
          app = "grafana"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "3000"
        }
      }

      spec {
        image_pull_secrets {
          name = "dockerhub-secret"
        }

        security_context {
          run_as_user  = 472
          run_as_group = 472
          fs_group     = 472
        }

        init_container {
          name  = "grafana-init"
          image = "busybox:1.35"

          command = [
            "sh",
            "-c",
            "mkdir -p /var/lib/grafana/plugins /var/lib/grafana/dashboards && chown -R 472:472 /var/lib/grafana && chmod -R 755 /var/lib/grafana"
          ]

          volume_mount {
            name       = "grafana-storage"
            mount_path = "/var/lib/grafana"
          }

          security_context {
            run_as_user = 0
          }
        }

        container {
          name  = "grafana"
          image = "grafana/grafana:8.5.27"

          port {
            container_port = 3000
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

          env {
            name  = "GF_SECURITY_ADMIN_USER"
            value = "admin"
          }

          env {
            name  = "GF_SECURITY_ADMIN_PASSWORD"
            value = "admin"
          }

          env {
            name  = "GF_INSTALL_PLUGINS"
            value = "grafana-piechart-panel"
          }

          env {
            name  = "GF_PATHS_PLUGINS"
            value = "/var/lib/grafana/plugins"
          }

          env {
            name  = "GF_PATHS_DATA"
            value = "/var/lib/grafana"
          }

          volume_mount {
            name       = "grafana-config"
            mount_path = "/etc/grafana/grafana.ini"
            sub_path   = "grafana.ini"
          }

          volume_mount {
            name       = "grafana-datasources"
            mount_path = "/etc/grafana/provisioning/datasources"
          }

          volume_mount {
            name       = "grafana-storage"
            mount_path = "/var/lib/grafana"
          }

          volume_mount {
            name       = "grafana-dashboard-provisioning"
            mount_path = "/etc/grafana/provisioning/dashboards"
          }

          volume_mount {
            name       = "grafana-dashboards"
            mount_path = "/var/lib/grafana/dashboards"
          }

          readiness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
          }

          liveness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 60
            timeout_seconds       = 30
            failure_threshold     = 10
          }
        }

        volume {
          name = "grafana-config"
          config_map {
            name = "grafana-config"
          }
        }

        volume {
          name = "grafana-datasources"
          config_map {
            name = "grafana-datasources"
          }
        }

        volume {
          name = "grafana-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.grafana_storage[0].metadata[0].name
          }
        }

        volume {
          name = "grafana-dashboard-provisioning"
          config_map {
            name = "grafana-dashboard-provisioning"
          }
        }

        volume {
          name = "grafana-dashboards"
          config_map {
            name = "grafana-dashboards"
          }
        }
      }
    }
  }
}

# Grafana Service
resource "kubernetes_service" "grafana" {
  depends_on = [kubernetes_deployment.grafana]

  metadata {
    name      = "grafana"
    namespace = "monitoring"
    labels = {
      app = "grafana"
    }
    annotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "3000"
    }
  }

  spec {
    type = "ClusterIP"

    port {
      port        = 3000
      target_port = 3000
      protocol    = "TCP"
    }

    selector = {
      app = "grafana"
    }
  }
}

# Kube-State-Metrics Service Account
resource "kubernetes_service_account" "kube_state_metrics" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "kube-state-metrics"
    namespace = "monitoring"
  }
}

# Kube-State-Metrics ClusterRole
resource "kubernetes_cluster_role" "kube_state_metrics" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name = "kube-state-metrics"
  }

  rule {
    api_groups = [""]
    resources = [
      "configmaps",
      "secrets",
      "nodes",
      "pods",
      "services",
      "resourcequotas",
      "replicationcontrollers",
      "limitranges",
      "persistentvolumeclaims",
      "persistentvolumes",
      "namespaces",
      "endpoints"
    ]
    verbs = ["list", "watch"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["daemonsets", "deployments", "replicasets", "ingresses"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["statefulsets", "daemonsets", "deployments", "replicasets"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["cronjobs", "jobs"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["authentication.k8s.io"]
    resources  = ["tokenreviews"]
    verbs      = ["create"]
  }

  rule {
    api_groups = ["authorization.k8s.io"]
    resources  = ["subjectaccessreviews"]
    verbs      = ["create"]
  }

  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["certificates.k8s.io"]
    resources  = ["certificatesigningrequests"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses", "volumeattachments"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["admissionregistration.k8s.io"]
    resources  = ["mutatingwebhookconfigurations", "validatingwebhookconfigurations"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies", "ingresses"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["list", "watch"]
  }
}

# Kube-State-Metrics ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "kube_state_metrics" {
  depends_on = [kubernetes_cluster_role.kube_state_metrics, kubernetes_service_account.kube_state_metrics]

  metadata {
    name = "kube-state-metrics"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "kube-state-metrics"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "kube-state-metrics"
    namespace = "monitoring"
  }
}

# Kube-State-Metrics Deployment
resource "kubernetes_deployment" "kube_state_metrics" {
  depends_on       = [kubernetes_service_account.kube_state_metrics]
  wait_for_rollout = false

  metadata {
    name      = "kube-state-metrics"
    namespace = "monitoring"
    labels = {
      app = "kube-state-metrics"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "kube-state-metrics"
      }
    }

    template {
      metadata {
        labels = {
          app = "kube-state-metrics"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8080"
        }
      }

      spec {
        service_account_name = "kube-state-metrics"

        container {
          name  = "kube-state-metrics"
          image = "k8s.gcr.io/kube-state-metrics/kube-state-metrics:v2.10.0"
          args = [
            "--port=8080",
            "--telemetry-port=8081"
          ]

          port {
            container_port = 8080
            name           = "http-metrics"
          }

          port {
            container_port = 8081
            name           = "telemetry"
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 5
            timeout_seconds       = 5
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 8081
            }
            initial_delay_seconds = 5
            timeout_seconds       = 5
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          security_context {
            run_as_user                = 65534
            run_as_non_root            = true
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
          }
        }

        security_context {
          run_as_non_root = true
          run_as_user     = 65534
        }
      }
    }
  }
}

# Kube-State-Metrics Service
resource "kubernetes_service" "kube_state_metrics" {
  depends_on = [kubernetes_deployment.kube_state_metrics]

  metadata {
    name      = "kube-state-metrics"
    namespace = "monitoring"
    labels = {
      app = "kube-state-metrics"
    }
    annotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "8080"
    }
  }

  spec {
    port {
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
      name        = "http-metrics"
    }

    port {
      port        = 8081
      target_port = 8081
      protocol    = "TCP"
      name        = "telemetry"
    }

    selector = {
      app = "kube-state-metrics"
    }
  }
}

# Node Exporter DaemonSet
resource "kubernetes_daemonset" "node_exporter" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "node-exporter"
    namespace = "monitoring"
    labels = {
      app = "node-exporter"
    }
  }

  spec {
    selector {
      match_labels = {
        app = "node-exporter"
      }
    }

    template {
      metadata {
        labels = {
          app = "node-exporter"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9100"
        }
      }

      spec {
        host_network = true
        host_pid     = true

        container {
          name  = "node-exporter"
          image = "quay.io/prometheus/node-exporter:v1.6.1"
          args = [
            "--path.sysfs=/host/sys",
            "--path.rootfs=/host/root",
            "--no-collector.wifi",
            "--no-collector.hwmon",
            "--collector.filesystem.ignored-mount-points=^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/pods/.+)($|/)",
            "--collector.netclass.ignored-devices=^(veth.*)$",
            "--collector.netdev.device-exclude=^(veth.*)$"
          ]

          port {
            container_port = 9100
            host_port      = 9100
            name           = "http"
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "24Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "100Mi"
            }
          }

          volume_mount {
            name       = "sys"
            mount_path = "/host/sys"
            read_only  = true
          }

          volume_mount {
            name       = "root"
            mount_path = "/host/root"
            read_only  = true
          }

          security_context {
            run_as_user                = 65534
            run_as_non_root            = true
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
          }
        }

        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }

        volume {
          name = "root"
          host_path {
            path = "/"
          }
        }

        toleration {
          key      = "node-role.kubernetes.io/master"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        toleration {
          key      = "node-role.kubernetes.io/control-plane"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      }
    }
  }
}

# Node Exporter Service
resource "kubernetes_service" "node_exporter" {
  depends_on = [kubernetes_daemonset.node_exporter]

  metadata {
    name      = "node-exporter"
    namespace = "monitoring"
    labels = {
      app = "node-exporter"
    }
    annotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "9100"
    }
  }

  spec {
    port {
      port        = 9100
      target_port = 9100
      protocol    = "TCP"
      name        = "http"
    }

    selector = {
      app = "node-exporter"
    }
  }
}
