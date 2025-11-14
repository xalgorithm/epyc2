# MetalLB Load Balancer for Rebellion Cluster
# This file deploys MetalLB on the rebellion cluster

# =============================================================================
# Helm Provider for Rebellion Cluster
# =============================================================================

provider "helm" {
  alias = "rebellion"

  kubernetes {
    config_path = pathexpand("~/.kube/configs/rebellion-config")
  }
}

provider "kubernetes" {
  alias       = "rebellion"
  config_path = pathexpand("~/.kube/configs/rebellion-config")
}

# =============================================================================
# MetalLB Installation
# =============================================================================

# Install MetalLB using Helm
resource "helm_release" "rebellion_metallb" {
  provider = helm.rebellion

  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = "0.14.3"
  namespace  = "metallb-system"

  create_namespace = true

  values = [
    yamlencode({
      speaker = {
        frr = {
          enabled = false
        }
      }
    })
  ]

  depends_on = [null_resource.join_rebellion_workers]
}

# Wait for MetalLB controller to be ready
resource "null_resource" "wait_for_metallb_rebellion" {
  depends_on = [helm_release.rebellion_metallb]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=~/.kube/configs/rebellion-config
      echo "Waiting for MetalLB controller..."
      kubectl wait --for=condition=Available --timeout=300s deployment/metallb-controller -n metallb-system
      
      echo "Waiting for MetalLB CRDs to be established..."
      for i in {1..30}; do
        if kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1; then
          echo "IPAddressPool CRD is available"
          break
        fi
        echo "Waiting for CRDs... attempt $i/30"
        sleep 5
      done
      
      # Additional wait for API server to recognize the CRD
      sleep 15
    EOT
  }
}

# =============================================================================
# MetalLB IPAddressPool
# =============================================================================

resource "null_resource" "rebellion_metallb_ippool" {
  depends_on = [
    helm_release.rebellion_metallb,
    null_resource.wait_for_metallb_rebellion
  ]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=~/.kube/configs/rebellion-config
      
      cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: rebellion-pool
  namespace: metallb-system
spec:
  addresses:
    - ${var.rebellion_metallb_pool_start}-${var.rebellion_metallb_pool_end}
EOF
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      export KUBECONFIG=~/.kube/configs/rebellion-config
      kubectl delete ipaddresspool rebellion-pool -n metallb-system --ignore-not-found=true
    EOT
  }
}

# =============================================================================
# MetalLB L2Advertisement
# =============================================================================

resource "null_resource" "rebellion_metallb_l2_advertisement" {
  depends_on = [null_resource.rebellion_metallb_ippool]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=~/.kube/configs/rebellion-config
      
      cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: rebellion-l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
    - rebellion-pool
EOF
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      export KUBECONFIG=~/.kube/configs/rebellion-config
      kubectl delete l2advertisement rebellion-l2-advert -n metallb-system --ignore-not-found=true
    EOT
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "rebellion_metallb_info" {
  description = "Rebellion MetalLB configuration"
  value = {
    namespace     = "metallb-system"
    ip_pool_start = var.rebellion_metallb_pool_start
    ip_pool_end   = var.rebellion_metallb_pool_end
    pool_name     = "rebellion-pool"
  }
  depends_on = [null_resource.rebellion_metallb_l2_advertisement]
}

