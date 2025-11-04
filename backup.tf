# Backup Namespace
resource "kubernetes_namespace" "backup" {
  depends_on = [null_resource.kubeconfig_ready, null_resource.cluster_api_ready]

  metadata {
    name = "backup"
    labels = {
      name = "backup"
    }
  }
}

# Backup Service Account
resource "kubernetes_service_account" "backup" {
  depends_on = [kubernetes_namespace.backup]

  metadata {
    name      = "backup"
    namespace = "backup"
  }
}

# Backup ClusterRole
resource "kubernetes_cluster_role" "backup" {
  depends_on = [kubernetes_namespace.backup]

  metadata {
    name = "backup"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "persistentvolumes", "persistentvolumeclaims", "nodes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "daemonsets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets", "configmaps"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
}

# Backup ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "backup" {
  depends_on = [kubernetes_cluster_role.backup, kubernetes_service_account.backup]

  metadata {
    name = "backup"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "backup"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "backup"
    namespace = "backup"
  }
}

# Backup Scripts ConfigMap
resource "kubernetes_config_map" "backup_scripts" {
  depends_on = [kubernetes_namespace.backup]

  metadata {
    name      = "backup-scripts"
    namespace = "backup"
  }

  data = {
    "etcd-backup.sh"                 = file("${path.module}/scripts/backup/etcd-backup.sh")
    "k3s-etcd-backup.sh"             = file("${path.module}/scripts/backup/k3s-etcd-backup.sh")
    "data-backup.sh"                 = file("${path.module}/scripts/backup/data-backup.sh")
    "manual-backup-comprehensive.sh" = file("${path.module}/scripts/backup/manual-backup-comprehensive.sh")
    "test-backup-connectivity.sh"    = file("${path.module}/scripts/maintenance/test-backup-connectivity.sh")
    "test-nfs-permissions.sh"        = file("${path.module}/scripts/maintenance/test-nfs-permissions.sh")
    "fix-kubeconfig-secret.sh"       = file("${path.module}/scripts/troubleshooting/fix-kubeconfig-secret.sh")
    "diagnose-nfs-access.sh"         = file("${path.module}/scripts/troubleshooting/diagnose-nfs-access.sh")
    "fix-nfs-permissions.sh"         = file("${path.module}/scripts/maintenance/fix-nfs-permissions.sh")
    "restore-etcd.sh"                = file("${path.module}/scripts/backup/restore-etcd.sh")

    "restore-grafana.sh"    = file("${path.module}/scripts/backup/restore-grafana.sh")
    "restore-prometheus.sh" = file("${path.module}/scripts/backup/restore-prometheus.sh")
    "restore-loki.sh"       = file("${path.module}/scripts/backup/restore-loki.sh")
    "restore-mimir.sh"      = file("${path.module}/scripts/backup/restore-mimir.sh")

    "backup-file-metrics.sh" = file("${path.module}/scripts/backup/backup-file-metrics.sh")
    "backup-cleanup.sh"      = file("${path.module}/scripts/backup/backup-cleanup.sh")
  }
}

# ETCD Backup CronJob
resource "kubernetes_cron_job_v1" "etcd_backup" {
  depends_on = [kubernetes_config_map.backup_scripts, kubernetes_service_account.backup]

  metadata {
    name      = "etcd-backup"
    namespace = "backup"
    labels = {
      app = "etcd-backup"
    }
  }

  spec {
    schedule                      = "0 2 * * *" # Daily at 2 AM
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 1

    job_template {
      metadata {
        labels = {
          app = "etcd-backup"
        }
      }

      spec {
        template {
          metadata {
            labels = {
              app = "etcd-backup"
            }
          }

          spec {
            service_account_name = "backup"
            restart_policy       = "OnFailure"

            host_network = true
            node_selector = {
              "node-role.kubernetes.io/control-plane" = ""
            }

            toleration {
              key      = "node-role.kubernetes.io/control-plane"
              operator = "Exists"
              effect   = "NoSchedule"
            }

            container {
              name    = "etcd-backup"
              image   = "k8s.gcr.io/etcd:3.5.9-0"
              command = ["/bin/sh"]
              args    = ["/scripts/etcd-backup.sh"]

              env {
                name  = "ETCDCTL_API"
                value = "3"
              }

              env {
                name  = "BACKUP_DIR"
                value = "/backup/etcd"
              }

              env {
                name = "NODE_NAME"
                value_from {
                  field_ref {
                    field_path = "spec.nodeName"
                  }
                }
              }

              volume_mount {
                name       = "backup-scripts"
                mount_path = "/scripts"
              }

              volume_mount {
                name       = "etcd-certs"
                mount_path = "/etc/kubernetes/pki/etcd"
                read_only  = true
              }

              volume_mount {
                name       = "backup-storage"
                mount_path = "/backup"
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
            }

            volume {
              name = "backup-scripts"
              config_map {
                name         = "backup-scripts"
                default_mode = "0755"
              }
            }

            volume {
              name = "etcd-certs"
              host_path {
                path = "/etc/kubernetes/pki/etcd"
                type = "Directory"
              }
            }

            volume {
              name = "backup-storage"
              nfs {
                server = var.nfs_server_ip
                path   = var.nfs_backup_path
              }
            }
          }
        }
      }
    }
  }
}

# Data Backup CronJob
resource "kubernetes_cron_job_v1" "data_backup" {
  depends_on = [kubernetes_config_map.backup_scripts, kubernetes_service_account.backup]

  metadata {
    name      = "data-backup"
    namespace = "backup"
    labels = {
      app = "data-backup"
    }
  }

  spec {
    schedule                      = "0 3 * * *" # Daily at 3 AM
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 1

    job_template {
      metadata {
        labels = {
          app = "data-backup"
        }
      }

      spec {
        template {
          metadata {
            labels = {
              app = "data-backup"
            }
          }

          spec {
            service_account_name = "backup"
            restart_policy       = "OnFailure"

            container {
              name    = "data-backup"
              image   = "alpine:3.18"
              command = ["/bin/sh"]
              args    = ["/scripts/data-backup.sh"]

              env {
                name  = "BACKUP_DIR"
                value = "/backup/data"
              }



              volume_mount {
                name       = "backup-scripts"
                mount_path = "/scripts"
              }

              volume_mount {
                name       = "backup-storage"
                mount_path = "/backup"
              }

              volume_mount {
                name       = "kubectl-config"
                mount_path = "/root/.kube"
                read_only  = true
              }

              volume_mount {
                name       = "restore-scripts"
                mount_path = "/restore-scripts"
                read_only  = true
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
              name = "backup-storage"
              nfs {
                server = var.nfs_server_ip
                path   = var.nfs_backup_path
              }
            }

            volume {
              name = "kubectl-config"
              secret {
                secret_name = "backup-kubeconfig"
              }
            }

            volume {
              name = "restore-scripts"
              config_map {
                name         = "backup-scripts"
                default_mode = "0755"
              }
            }
          }
        }
      }
    }
  }
}

# Backup Cleanup CronJob
resource "kubernetes_cron_job_v1" "backup_cleanup" {
  depends_on = [kubernetes_config_map.backup_scripts, kubernetes_service_account.backup]

  metadata {
    name      = "backup-cleanup"
    namespace = "backup"
    labels = {
      app = "backup-cleanup"
    }
  }

  spec {
    schedule                      = "0 4 * * 0" # Weekly on Sunday at 4 AM
    successful_jobs_history_limit = 2
    failed_jobs_history_limit     = 1

    job_template {
      metadata {
        labels = {
          app = "backup-cleanup"
        }
      }

      spec {
        template {
          metadata {
            labels = {
              app = "backup-cleanup"
            }
          }

          spec {
            service_account_name = "backup"
            restart_policy       = "OnFailure"

            container {
              name    = "backup-cleanup"
              image   = "alpine:3.18"
              command = ["/bin/sh"]
              args    = ["/scripts/backup-cleanup.sh"]

              env {
                name  = "BACKUP_DIR"
                value = "/backup"
              }

              env {
                name  = "RETENTION_DAYS"
                value = tostring(var.backup_retention_days)
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
                  cpu    = "50m"
                  memory = "64Mi"
                }
                limits = {
                  cpu    = "200m"
                  memory = "256Mi"
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
                server = var.nfs_server_ip
                path   = var.nfs_backup_path
              }
            }
          }
        }
      }
    }
  }
}

# Backup File Metrics CronJob
resource "kubernetes_cron_job_v1" "backup_file_metrics" {
  depends_on = [kubernetes_config_map.backup_scripts, kubernetes_service_account.backup]

  metadata {
    name      = "backup-file-metrics"
    namespace = "backup"
    labels = {
      app = "backup-file-metrics"
    }
  }

  spec {
    schedule                      = "*/5 * * * *" # Every 5 minutes
    successful_jobs_history_limit = 2
    failed_jobs_history_limit     = 1

    job_template {
      metadata {
        labels = {
          app = "backup-file-metrics"
        }
      }

      spec {
        template {
          metadata {
            labels = {
              app = "backup-file-metrics"
            }
          }

          spec {
            service_account_name = "backup"
            restart_policy       = "OnFailure"

            container {
              name    = "backup-file-metrics"
              image   = "alpine:3.18"
              command = ["/bin/sh"]
              args    = ["/scripts/backup-file-metrics.sh"]

              volume_mount {
                name       = "backup-scripts"
                mount_path = "/scripts"
              }

              volume_mount {
                name       = "backup-storage"
                mount_path = "/host/backup"
              }

              volume_mount {
                name       = "textfile-collector"
                mount_path = "/var/lib/node_exporter/textfile_collector"
              }

              resources {
                requests = {
                  cpu    = "10m"
                  memory = "32Mi"
                }
                limits = {
                  cpu    = "100m"
                  memory = "128Mi"
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
                server = var.nfs_server_ip
                path   = var.nfs_backup_path
              }
            }

            volume {
              name = "textfile-collector"
              empty_dir {}
            }
          }
        }
      }
    }
  }
}

# Backup Kubeconfig Secret
resource "kubernetes_secret" "backup_kubeconfig" {
  depends_on = [kubernetes_namespace.backup, null_resource.kubeconfig_ready]

  metadata {
    name      = "backup-kubeconfig"
    namespace = "backup"
  }

  data = {
    "config" = file("~/.kube/config")
  }

  type = "Opaque"
}

# Backup Monitoring Service
resource "kubernetes_service" "backup_metrics" {
  depends_on = [kubernetes_namespace.backup]

  metadata {
    name      = "backup-metrics"
    namespace = "backup"
    labels = {
      app = "backup-metrics"
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
      name        = "metrics"
    }

    selector = {
      app = "backup-metrics"
    }
  }
}

# Backup Status Deployment
resource "kubernetes_deployment" "backup_metrics" {
  depends_on       = [kubernetes_namespace.backup, kubernetes_service_account.backup]
  wait_for_rollout = false

  metadata {
    name      = "backup-metrics"
    namespace = "backup"
    labels = {
      app = "backup-metrics"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "backup-metrics"
      }
    }

    template {
      metadata {
        labels = {
          app = "backup-metrics"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8080"
        }
      }

      spec {
        service_account_name = "backup"

        init_container {
          name    = "backup-file-metrics-init"
          image   = "alpine:3.18"
          command = ["/bin/sh"]
          args    = ["/scripts/backup-file-metrics.sh"]

          volume_mount {
            name       = "backup-scripts"
            mount_path = "/scripts"
          }

          volume_mount {
            name       = "backup-storage"
            mount_path = "/host/backup"
          }

          volume_mount {
            name       = "textfile-collector"
            mount_path = "/var/lib/node_exporter/textfile_collector"
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }

        container {
          name  = "backup-metrics"
          image = "prom/node-exporter:v1.6.1"
          args = [
            "--path.rootfs=/host",
            "--collector.textfile.directory=/var/lib/node_exporter/textfile_collector",
            "--web.listen-address=:8080"
          ]

          port {
            container_port = 8080
            name           = "metrics"
          }

          volume_mount {
            name       = "backup-storage"
            mount_path = "/host/backup"
          }

          volume_mount {
            name       = "textfile-collector"
            mount_path = "/var/lib/node_exporter/textfile_collector"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
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
            server = var.nfs_server_ip
            path   = var.nfs_backup_path
          }
        }

        volume {
          name = "textfile-collector"
          empty_dir {}
        }
      }
    }
  }
}
