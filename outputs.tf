# Output important information after deployment

# Service Endpoints - All services accessible via nginx ingress
output "service_endpoints" {
  description = "All service endpoints with domains and IPs"
  value = {
    ingress_ip = var.ingress_ip
    services = {
      grafana = {
        domain   = "grafana.home"
        url      = "http://grafana.home"
        ip       = var.ingress_ip
        username = "admin"
        password = "admin"
      }
      prometheus = {
        domain = "prometheus.home"
        url    = "http://prometheus.home"
        ip     = var.ingress_ip
      }
      loki = {
        domain = "loki.home"
        url    = "http://loki.home"
        ip     = var.ingress_ip
      }
      mimir = {
        domain = "mimir.home"
        url    = "http://mimir.home"
        ip     = var.ingress_ip
      }
      mylar = {
        domain = "mylar.home"
        url    = "http://mylar.home"
        ip     = var.ingress_ip
      }
      n8n = {
        domain   = "automate.home"
        url      = "http://automate.home"
        ip       = var.ingress_ip
        username = "admin"
        password = "automate"
      }
    }
    dns_configuration = "Add to /etc/hosts: ${var.ingress_ip}  grafana.home prometheus.home loki.home mimir.home mylar.home automate.home"
  }
}

output "cluster_info" {
  description = "Kubernetes cluster information"
  value = {
    control_plane_ip = var.control_plane_ip
    worker_ips       = var.worker_ips
    worker_names     = var.worker_names
    k8s_version      = var.k8s_version
  }
}

output "network_info" {
  description = "Network configuration"
  value = {
    pod_network_cidr   = var.pod_network_cidr
    service_cidr       = var.service_cidr
    metallb_pool_start = var.metallb_pool_start
    metallb_pool_end   = var.metallb_pool_end
    ingress_ip         = var.ingress_ip
  }
}

output "deployment_commands" {
  description = "Useful commands after deployment"
  value = {
    check_nodes          = "kubectl get nodes -o wide"
    check_pods           = "kubectl get pods -A"
    check_services       = "kubectl get svc -n monitoring"
    check_media_services = "kubectl get svc -n media"
    check_backup_jobs    = "kubectl get cronjobs -n backup"
    get_grafana_ip       = "kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
    get_prometheus_ip    = "kubectl get svc prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
    get_loki_ip          = "kubectl get svc loki -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
    get_mylar_ip         = "kubectl get svc mylar -n media -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"

  }
}

output "backup_info" {
  description = "Backup configuration and commands"
  value = {
    nfs_server               = var.nfs_server_ip
    nfs_backup_path          = var.nfs_backup_path
    retention_days           = var.backup_retention_days
    manual_backup            = "./scripts/backup/manual-backup-comprehensive.sh"
    trigger_manual_backup    = "./scripts/backup/trigger-manual-backup.sh"
    test_backup_restoration  = "./scripts/backup/test-backup-restoration.sh"
    etcd_backup_schedule     = "Daily at 2:00 AM"
    data_backup_schedule     = "Daily at 3:00 AM"
    cleanup_schedule         = "Weekly on Sunday at 4:00 AM"
  }
}


