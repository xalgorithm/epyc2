# MetalLB Load Balancer for Kubernetes

# Create MetalLB namespace via kubectl to avoid API validation during plan
resource "null_resource" "metallb_namespace" {
  provisioner "local-exec" {
    command = <<-EOT
      kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f -
      kubectl label namespace metallb-system pod-security.kubernetes.io/enforce=privileged --overwrite
      kubectl label namespace metallb-system pod-security.kubernetes.io/audit=privileged --overwrite
      kubectl label namespace metallb-system pod-security.kubernetes.io/warn=privileged --overwrite
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete namespace metallb-system --ignore-not-found=true"
  }

  depends_on = [
    null_resource.kubeconfig_ready,
    null_resource.cluster_api_ready
  ]
}

# MetalLB Helm release
resource "helm_release" "metallb" {
  name       = "metallb"
  namespace  = "metallb-system"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = "~> 0.13"
  wait       = true
  timeout    = 600

  depends_on = [
    null_resource.metallb_namespace
  ]
}

# Wait for MetalLB controller to be ready
resource "null_resource" "metallb_ready" {
  provisioner "local-exec" {
    command = "kubectl -n metallb-system rollout status deployment/metallb-controller --timeout=300s"
  }

  depends_on = [
    helm_release.metallb
  ]
}

# MetalLB IP Address Pool configuration via kubectl
resource "null_resource" "metallb_ipaddresspool" {
  provisioner "local-exec" {
    command = <<-EOT
      cat <<EOF | kubectl apply -f -
      apiVersion: metallb.io/v1beta1
      kind: IPAddressPool
      metadata:
        name: default-pool
        namespace: metallb-system
      spec:
        addresses:
        - ${var.metallb_pool_start}-${var.metallb_pool_end}
      EOF
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete ipaddresspool default-pool -n metallb-system --ignore-not-found=true"
  }

  depends_on = [
    null_resource.metallb_ready
  ]
}

# MetalLB L2 Advertisement configuration via kubectl
resource "null_resource" "metallb_l2advertisement" {
  provisioner "local-exec" {
    command = <<-EOT
      cat <<EOF | kubectl apply -f -
      apiVersion: metallb.io/v1beta1
      kind: L2Advertisement
      metadata:
        name: default-l2advertisement
        namespace: metallb-system
      spec:
        ipAddressPools:
        - default-pool
      EOF
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete l2advertisement default-l2advertisement -n metallb-system --ignore-not-found=true"
  }

  depends_on = [
    null_resource.metallb_ipaddresspool
  ]
}

# Gate for MetalLB readiness (wait until MetalLB is fully operational)
resource "null_resource" "metallb_operational" {
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for MetalLB speaker DaemonSet to be ready
      kubectl -n metallb-system rollout status daemonset/metallb-speaker --timeout=300s
      
      # Wait a bit more for MetalLB to be fully operational
      sleep 30
      
      # Verify MetalLB is working by checking if the IP pool is available
      kubectl get ipaddresspool -n metallb-system default-pool
      kubectl get l2advertisement -n metallb-system default-l2advertisement
      
      echo "MetalLB is fully operational!"
    EOT
  }

  depends_on = [
    null_resource.metallb_l2advertisement
  ]
}