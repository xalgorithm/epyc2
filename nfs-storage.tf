# NFS Storage Configuration
# This configures NFS as the default storage class for the Kubernetes cluster

# NFS CSI Driver Helm Chart
resource "helm_release" "nfs_csi_driver" {
  name       = "csi-driver-nfs"
  repository = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts"
  chart      = "csi-driver-nfs"
  namespace  = "kube-system"
  version    = "v4.5.0"

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

# Remove default annotation from any existing storage classes
resource "null_resource" "remove_default_storage_class" {
  provisioner "local-exec" {
    command = <<-EOT
      # Remove default annotation from existing storage classes
      kubectl get storageclass -o name | xargs -I {} kubectl annotate {} storageclass.kubernetes.io/is-default-class- || true
    EOT
  }

  depends_on = [
    null_resource.kubeconfig_ready
  ]

  triggers = {
    always_run = timestamp()
  }
}

# Create NFS directory on server (if accessible)
resource "null_resource" "create_nfs_directory" {
  provisioner "local-exec" {
    command = <<-EOT
      # Best-effort creation of NFS directory with fast failure and no password prompts
      # Uses existing SSH variables; requires key-based sudo on the NFS server
      timeout 20s ssh \
        -i ${var.ssh_private_key_path} \
        -o BatchMode=yes \
        -o PasswordAuthentication=no \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        ${var.ssh_user}@${var.nfs_storage_server} "
          set -e
          if [ -d '${var.nfs_storage_path}' ]; then
            echo 'NFS path exists: ${var.nfs_storage_path}'
            exit 0
          fi
          sudo mkdir -p '${var.nfs_storage_path}'
          sudo chmod 755 '${var.nfs_storage_path}'
          # Try common ownerships; ignore if groups differ across distros
          sudo chown nobody:nogroup '${var.nfs_storage_path}' || sudo chown nobody:nobody '${var.nfs_storage_path}' || true
        " || echo "Best-effort: could not ensure ${var.nfs_storage_path} on ${var.nfs_storage_server}. Create manually if needed."
    EOT
  }

  triggers = {
    nfs_server = var.nfs_storage_server
    nfs_path   = var.nfs_storage_path
  }
}

# Test PVC to verify NFS storage works
resource "kubernetes_persistent_volume_claim" "nfs_test_pvc" {
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

    storage_class_name = kubernetes_storage_class.nfs_storage_class.metadata[0].name
  }

  depends_on = [
    kubernetes_storage_class.nfs_storage_class
  ]
}

# Output NFS storage information
output "nfs_storage_info" {
  description = "NFS storage configuration details"
  value = {
    storage_class_name = kubernetes_storage_class.nfs_storage_class.metadata[0].name
    nfs_server         = var.nfs_storage_server
    nfs_path           = var.nfs_storage_path
    is_default         = true
  }
}