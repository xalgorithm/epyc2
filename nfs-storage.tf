# NFS Storage Configuration
# This configures NFS as the default storage class for the Kubernetes cluster

# NFS CSI Driver Helm Chart
resource "helm_release" "nfs_csi_driver" {
  name       = "csi-driver-nfs"
  repository = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts"
  chart      = "csi-driver-nfs"
  namespace  = "kube-system"
  version    = "v4.5.0"

  wait    = true
  timeout = 600

  set {
    name  = "kubeletDir"
    value = "/var/lib/kubelet"
  }

  depends_on = [
    null_resource.kubeconfig_ready,
    null_resource.cluster_api_ready
  ]
}

# NFS Storage Class
resource "kubernetes_storage_class" "nfs_storage_class" {
  count = var.bootstrap_cluster ? 1 : 0

  metadata {
    name = "nfs-storage"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "nfs.csi.k8s.io"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    server = var.nfs_storage_server
    share  = var.nfs_storage_path
  }

  depends_on = [
    helm_release.nfs_csi_driver
  ]
}

# Remove default annotation from any existing storage classes (only if cluster is accessible)
resource "null_resource" "remove_default_storage_class" {
  count = var.bootstrap_cluster ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      # Only run if cluster is accessible and we're bootstrapping
      if kubectl cluster-info >/dev/null 2>&1; then
        echo "Removing default annotations from existing storage classes..."
        kubectl get storageclass -o name 2>/dev/null | xargs -I {} kubectl annotate {} storageclass.kubernetes.io/is-default-class- 2>/dev/null || true
      else
        echo "Cluster not accessible, skipping storage class cleanup"
      fi
    EOT
  }

  depends_on = [
    null_resource.kubeconfig_ready,
    null_resource.cluster_api_ready
  ]
}

# Check NFS storage and existing service data
resource "null_resource" "check_nfs_storage" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "🔍 Checking NFS storage and existing service data..."
      
      # Check NFS server accessibility and create directories
      NFS_SSH_USER="${var.nfs_ssh_user != "" ? var.nfs_ssh_user : var.ssh_user}"
      NFS_SSH_KEY="${var.nfs_ssh_private_key_path != "" ? var.nfs_ssh_private_key_path : var.ssh_private_key_path}"
      
      timeout 20s ssh \
        -i $NFS_SSH_KEY \
        -o BatchMode=yes \
        -o PasswordAuthentication=no \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        $NFS_SSH_USER@${var.nfs_storage_server} "
          set -e
          
          # Create main NFS path if it doesn't exist
          if [ ! -d '${var.nfs_storage_path}' ]; then
            echo '📁 Creating main NFS directory: ${var.nfs_storage_path}'
            sudo mkdir -p '${var.nfs_storage_path}'
            sudo chmod 755 '${var.nfs_storage_path}'
            sudo chown nobody:nogroup '${var.nfs_storage_path}' || sudo chown nobody:nobody '${var.nfs_storage_path}' || true
          else
            echo '✅ NFS path exists: ${var.nfs_storage_path}'
          fi
          
          # Check for existing service data directories
          echo '🔍 Checking for existing service data...'
          
          # Check Prometheus data
          if [ -d '${var.nfs_storage_path}/monitoring-prometheus-storage-pvc-*' ] || [ -d '${var.nfs_storage_path}/prometheus-data' ]; then
            echo '📊 Found existing Prometheus data'
            echo 'prometheus_data_exists=true' > /tmp/nfs_check_results
          else
            echo '📊 No existing Prometheus data found'
            echo 'prometheus_data_exists=false' > /tmp/nfs_check_results
          fi
          
          # Check Grafana data
          if [ -d '${var.nfs_storage_path}/monitoring-grafana-storage-pvc-*' ] || [ -d '${var.nfs_storage_path}/grafana-data' ]; then
            echo '📈 Found existing Grafana data'
            echo 'grafana_data_exists=true' >> /tmp/nfs_check_results
          else
            echo '📈 No existing Grafana data found'
            echo 'grafana_data_exists=false' >> /tmp/nfs_check_results
          fi
          
          # Check Loki data
          if [ -d '${var.nfs_storage_path}/monitoring-loki-storage-pvc-*' ] || [ -d '${var.nfs_storage_path}/loki-data' ]; then
            echo '📝 Found existing Loki data'
            echo 'loki_data_exists=true' >> /tmp/nfs_check_results
          else
            echo '📝 No existing Loki data found'
            echo 'loki_data_exists=false' >> /tmp/nfs_check_results
          fi
          
          # Check Mimir data
          if [ -d '${var.nfs_storage_path}/monitoring-mimir-*-pvc-*' ] || [ -d '${var.nfs_storage_path}/mimir-data' ]; then
            echo '🎯 Found existing Mimir data'
            echo 'mimir_data_exists=true' >> /tmp/nfs_check_results
          else
            echo '🎯 No existing Mimir data found'
            echo 'mimir_data_exists=false' >> /tmp/nfs_check_results
          fi
          
          # List all directories for reference
          echo '📋 Current NFS directory contents:'
          ls -la '${var.nfs_storage_path}' || echo 'Directory is empty or inaccessible'
          
          # Copy results back
          cat /tmp/nfs_check_results
        " || echo "⚠️  Best-effort: could not fully check ${var.nfs_storage_path} on ${var.nfs_storage_server}. Proceeding with caution."
    EOT
  }

  triggers = {
    nfs_server = var.nfs_storage_server
    nfs_path   = var.nfs_storage_path
    timestamp  = timestamp()
  }
}

# Check cluster connectivity and existing PVCs
resource "null_resource" "check_cluster_connectivity" {
  depends_on = [null_resource.kubeconfig_ready]

  provisioner "local-exec" {
    command = <<-EOT
      echo "🔍 Checking cluster connectivity..."
      
      # Test cluster connectivity with timeout
      if timeout 30s kubectl cluster-info >/dev/null 2>&1; then
        echo "✅ Cluster is accessible"
        echo "CLUSTER_ACCESSIBLE=true" > /tmp/cluster_status
        
        echo "📋 Checking existing PVCs..."
        kubectl get pvc -n monitoring 2>/dev/null || echo "No monitoring namespace or PVCs found"
        kubectl get pvc -n media 2>/dev/null || echo "No media namespace or PVCs found"
        
        # Check for specific service PVCs
        if kubectl get pvc prometheus-storage -n monitoring >/dev/null 2>&1; then
          echo "✅ Found existing prometheus-storage PVC"
          echo "PROMETHEUS_PVC_EXISTS=true" >> /tmp/cluster_status
        else
          echo "❌ No prometheus-storage PVC found"
          echo "PROMETHEUS_PVC_EXISTS=false" >> /tmp/cluster_status
        fi
        
        if kubectl get pvc grafana-storage -n monitoring >/dev/null 2>&1; then
          echo "✅ Found existing grafana-storage PVC"
          echo "GRAFANA_PVC_EXISTS=true" >> /tmp/cluster_status
        else
          echo "❌ No grafana-storage PVC found"
          echo "GRAFANA_PVC_EXISTS=false" >> /tmp/cluster_status
        fi
        
      else
        echo "❌ Cluster not accessible or timed out"
        echo "CLUSTER_ACCESSIBLE=false" > /tmp/cluster_status
        echo "⚠️  Terraform will skip Kubernetes resource creation"
        echo "💡 To fix this:"
        echo "   1. Ensure you're on the right network (192.168.0.x)"
        echo "   2. Check if the cluster is running: ping 192.168.0.32"
        echo "   3. Verify kubeconfig: kubectl config current-context"
        echo "   4. Or set bootstrap_cluster=true to create a new cluster"
      fi
      
      cat /tmp/cluster_status 2>/dev/null || echo "CLUSTER_ACCESSIBLE=false"
    EOT
  }

  triggers = {
    timestamp = timestamp()
  }
}

# Service data validation - checks if services should preserve existing data
resource "null_resource" "validate_service_data" {
  depends_on = [
    null_resource.check_nfs_storage,
    null_resource.check_cluster_connectivity
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "🔍 Validating service data consistency..."
      
      # Read cluster status from previous check
      CLUSTER_ACCESSIBLE=$(grep "CLUSTER_ACCESSIBLE=" /tmp/cluster_status 2>/dev/null | cut -d'=' -f2 || echo "false")
      
      echo "📊 Service Data Availability Summary:"
      echo "===================================="
      
      if [ "$CLUSTER_ACCESSIBLE" = "true" ]; then
        echo "✅ Cluster is accessible - checking service data..."
        
        # Check Prometheus
        PROMETHEUS_EXISTS=$(grep "PROMETHEUS_PVC_EXISTS=" /tmp/cluster_status 2>/dev/null | cut -d'=' -f2 || echo "false")
        if [ "$PROMETHEUS_EXISTS" = "true" ]; then
          PVC_STATUS=$(timeout 10s kubectl get pvc prometheus-storage -n monitoring -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
          echo "📊 Prometheus: PVC exists (Status: $PVC_STATUS)"
        else
          echo "📊 Prometheus: No PVC found - will create new"
        fi
        
        # Check Grafana
        GRAFANA_EXISTS=$(grep "GRAFANA_PVC_EXISTS=" /tmp/cluster_status 2>/dev/null | cut -d'=' -f2 || echo "false")
        if [ "$GRAFANA_EXISTS" = "true" ]; then
          PVC_STATUS=$(timeout 10s kubectl get pvc grafana-storage -n monitoring -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
          echo "📈 Grafana: PVC exists (Status: $PVC_STATUS)"
        else
          echo "📈 Grafana: No PVC found - will create new"
        fi
        
        # Check for running services
        echo ""
        echo "🔄 Currently running services:"
        timeout 10s kubectl get pods -n monitoring -l 'app in (prometheus,grafana)' 2>/dev/null || echo "No monitoring services running"
        
      else
        echo "❌ Cluster not accessible - skipping service data validation"
        echo "💡 Service data checks will be performed when cluster becomes available"
      fi
      
      echo ""
      echo "✅ Service data validation complete"
    EOT
  }

  triggers = {
    timestamp = timestamp()
  }
}

# Test PVC to verify NFS storage works
resource "kubernetes_persistent_volume_claim" "nfs_test_pvc" {
  count = var.bootstrap_cluster ? 1 : 0

  metadata {
    name      = "nfs-test-pvc"
    namespace = "default"
  }

  spec {
    access_modes = ["ReadWriteMany"]

    resources {
      requests = {
        storage = "1Gi"
      }
    }

    storage_class_name = kubernetes_storage_class.nfs_storage_class[0].metadata[0].name
  }

  depends_on = [
    kubernetes_storage_class.nfs_storage_class
  ]

  timeouts {
    create = "10m"
  }
}

# Output NFS storage information
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