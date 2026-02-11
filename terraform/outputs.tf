# Output Definitions
# This file contains all output values from the infrastructure deployment

# =============================================================================
# Infrastructure Outputs
# =============================================================================

# VM Information
output "vm_info" {
  description = "Created VM information"
  value = {
    bumblebee = {
      vm_id = proxmox_virtual_environment_vm.bumblebee.vm_id
      name  = proxmox_virtual_environment_vm.bumblebee.name
      ip    = var.control_plane_ip
      role  = "control-plane"
      disk  = "256GB"
    }
    prime = {
      vm_id = proxmox_virtual_environment_vm.prime.vm_id
      name  = proxmox_virtual_environment_vm.prime.name
      ip    = var.worker_ips[0]
      role  = "worker"
      disk  = "256GB"
    }
    wheeljack = {
      vm_id = proxmox_virtual_environment_vm.wheeljack.vm_id
      name  = proxmox_virtual_environment_vm.wheeljack.name
      ip    = var.worker_ips[1]
      role  = "worker"
      disk  = "256GB"
    }
    work = {
      vm_id = proxmox_virtual_environment_vm.work.vm_id
      name  = proxmox_virtual_environment_vm.work.name
      ip    = var.work_vm_ip
      role  = "standalone"
      disk  = "64GB"
      fqdn  = "work.xalg.im"
      nfs_mount = "192.168.0.7:/data -> /data"
    }
  }
}

# Rebellion Cluster Information
output "rebellion_vm_info" {
  description = "Rebellion cluster VM information"
  value = {
    luke = {
      vm_id = proxmox_virtual_environment_vm.luke.vm_id
      name  = proxmox_virtual_environment_vm.luke.name
      ip    = var.rebellion_control_plane_ip
      role  = "control-plane"
      disk  = "128GB"
      cpu   = "4 cores"
      memory = "8GB"
    }
    leia = {
      vm_id = proxmox_virtual_environment_vm.leia.vm_id
      name  = proxmox_virtual_environment_vm.leia.name
      ip    = var.rebellion_worker_ips[0]
      role  = "worker"
      disk  = "128GB"
      cpu   = "4 cores"
      memory = "8GB"
    }
    han = {
      vm_id = proxmox_virtual_environment_vm.han.vm_id
      name  = proxmox_virtual_environment_vm.han.name
      ip    = var.rebellion_worker_ips[1]
      role  = "worker"
      disk  = "128GB"
      cpu   = "4 cores"
      memory = "8GB"
    }
  }
}

output "rebellion_cluster_info" {
  description = "Rebellion Kubernetes cluster configuration"
  value = {
    cluster_name          = "rebellion"
    control_plane_ip      = var.rebellion_control_plane_ip
    worker_ips            = var.rebellion_worker_ips
    vm_names              = var.rebellion_vm_names
    metallb_pool_start    = var.rebellion_metallb_pool_start
    metallb_pool_end      = var.rebellion_metallb_pool_end
    kubeconfig_path       = "~/.kube/configs/rebellion-config"
  }
}

# Cluster Information
output "cluster_info" {
  description = "Kubernetes cluster information"
  value = {
    control_plane_ip = var.control_plane_ip
    worker_ips       = var.worker_ips
    worker_names     = var.worker_names
    k8s_version      = var.k8s_version
  }
}

# Network Configuration
output "network_info" {
  description = "Network configuration"
  value = {
    pod_network_cidr   = var.pod_network_cidr
    service_cidr       = var.service_cidr
    metallb_pool_start = var.metallb_pool_start
    metallb_pool_end   = var.metallb_pool_end
    ingress_ip         = var.ingress_ip
    syslog_ip          = var.syslog_ip
  }
}

# =============================================================================
# Storage Outputs
# =============================================================================

# NFS Storage Information
output "nfs_storage_info" {
  description = "NFS storage configuration details"
  value = var.bootstrap_cluster ? {
    storage_class_name = kubernetes_storage_class.nfs_storage_class[0].metadata[0].name
    nfs_server         = var.nfs_storage_server
    nfs_path           = var.nfs_storage_path
    is_default         = true
    } : {
    storage_class_name = "nfs-storage"
    nfs_server         = var.nfs_storage_server
    nfs_path           = var.nfs_storage_path
    is_default         = true
  }
}

# Backup Configuration
output "backup_info" {
  description = "Backup configuration and commands"
  value = {
    nfs_server              = var.nfs_server_ip
    nfs_backup_path         = var.nfs_backup_path
    retention_days          = var.backup_retention_days
    manual_backup           = "./scripts/backup/manual-backup-comprehensive.sh"
    trigger_manual_backup   = "./scripts/backup/trigger-manual-backup.sh"
    test_backup_restoration = "./scripts/backup/test-backup-restoration.sh"
    etcd_backup_schedule    = "Daily at 2:00 AM"
    data_backup_schedule    = "Daily at 3:00 AM"
    cleanup_schedule        = "Weekly on Sunday at 4:00 AM"
  }
}

# =============================================================================
# Service Endpoints
# =============================================================================

# All Service Endpoints
output "service_endpoints" {
  description = "All service endpoints with domains and IPs"
  value = {
    ingress_ip = var.ingress_ip
    services = {
      grafana = {
        domain   = var.grafana_host
        url      = "http://${var.grafana_host}"
        ip       = var.ingress_ip
        username = "admin"
        password = "admin"
      }
      prometheus = {
        domain = var.prometheus_host
        url    = "http://${var.prometheus_host}"
        ip     = var.ingress_ip
      }
      loki = {
        domain = var.loki_host
        url    = "http://${var.loki_host}"
        ip     = var.ingress_ip
      }
      mimir = {
        domain = var.mimir_host
        url    = "http://${var.mimir_host}"
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
    dns_configuration = "Add to /etc/hosts: ${var.ingress_ip}  ${var.grafana_host} ${var.prometheus_host} ${var.loki_host} ${var.mimir_host} automate.home"
  }
}

# OPNsense Logging Integration
output "opnsense_logging_info" {
  description = "OPNsense logging integration information"
  value = {
    syslog_ip           = var.syslog_ip
    syslog_udp_port     = 514
    syslog_tcp_port     = 514
    loki_endpoint       = "http://loki.monitoring.svc.cluster.local:3100"
    grafana_explore_url = "http://${var.grafana_host}/explore?orgId=1&left=%5B%22now-1h%22,%22now%22,%22Loki%22,%7B%22expr%22:%22%7Bapplication%3D%5C%22opnsense%5C%22%7D%22%7D%5D"
  }
}

# =============================================================================
# Useful Commands
# =============================================================================

# Deployment Commands
output "deployment_commands" {
  description = "Useful commands after deployment"
  value = {
    # Cluster Information
    check_nodes  = "kubectl get nodes -o wide"
    check_pods   = "kubectl get pods -A"
    cluster_info = "kubectl cluster-info"

    # Service Checks
    check_services       = "kubectl get svc -n monitoring"
    check_media_services = "kubectl get svc -n media"
    check_backup_jobs    = "kubectl get cronjobs -n backup"
    check_ingresses      = "kubectl get ingress -A"

    # Get Service IPs
    get_grafana_ip    = "kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
    get_prometheus_ip = "kubectl get svc prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
    get_loki_ip       = "kubectl get svc loki -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
    get_mylar_ip      = "kubectl get svc mylar -n media -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"

    # Storage
    check_storage = "kubectl get sc,pv,pvc -A"

    # Logs
    grafana_logs    = "kubectl logs -n monitoring -l app=grafana --tail=50"
    prometheus_logs = "kubectl logs -n monitoring -l app=prometheus --tail=50"

    # Port Forwarding (for troubleshooting)
    port_forward_grafana = "kubectl port-forward -n monitoring svc/grafana 3000:3000"
  }
}
