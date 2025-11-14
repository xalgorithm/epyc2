# Rebellion Kubernetes Cluster Bootstrap Configuration
# This file orchestrates the Kubernetes cluster setup on rebellion VMs

# =============================================================================
# Cluster Bootstrap Orchestration
# =============================================================================

# Wait for VMs to be fully ready
resource "null_resource" "wait_for_rebellion_vms" {
  depends_on = [
    proxmox_virtual_environment_vm.luke,
    proxmox_virtual_environment_vm.leia,
    proxmox_virtual_environment_vm.han
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for VMs to be ready..."
      sleep 60
      
      # Test SSH connectivity
      for i in {1..30}; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ${var.ssh_private_key_path} \
          ${var.ssh_user}@${var.rebellion_control_plane_ip} "echo ok" >/dev/null 2>&1; then
          echo "Luke is ready"
          break
        fi
        echo "Waiting for Luke... attempt $i/30"
        sleep 10
      done
    EOT
  }
}

# Install Kubernetes on all nodes
resource "null_resource" "install_kubernetes_rebellion" {
  depends_on = [null_resource.wait_for_rebellion_vms]

  triggers = {
    luke_id = proxmox_virtual_environment_vm.luke.id
    leia_id = proxmox_virtual_environment_vm.leia.id
    han_id  = proxmox_virtual_environment_vm.han.id
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/rebellion/install-kubernetes.sh"
  }
}

# Bootstrap control plane on Luke
resource "null_resource" "bootstrap_rebellion_control_plane" {
  depends_on = [null_resource.install_kubernetes_rebellion]

  triggers = {
    luke_id = proxmox_virtual_environment_vm.luke.id
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/rebellion/bootstrap-control-plane.sh"
  }

  # Copy kubeconfig after bootstrap
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ~/.kube/configs
      echo "Kubeconfig will be copied by bootstrap script"
    EOT
  }
}

# Join worker nodes to the cluster
resource "null_resource" "join_rebellion_workers" {
  depends_on = [null_resource.bootstrap_rebellion_control_plane]

  triggers = {
    leia_id = proxmox_virtual_environment_vm.leia.id
    han_id  = proxmox_virtual_environment_vm.han.id
    luke_id = proxmox_virtual_environment_vm.luke.id
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/rebellion/join-workers.sh"
  }
}

# Output cluster information
output "rebellion_kubeconfig" {
  description = "Path to rebellion cluster kubeconfig"
  value       = "~/.kube/configs/rebellion-config"
  depends_on  = [null_resource.bootstrap_rebellion_control_plane]
}

output "rebellion_cluster_access" {
  description = "Commands to access rebellion cluster"
  value = {
    kubeconfig = "export KUBECONFIG=~/.kube/configs/rebellion-config"
    get_nodes  = "kubectl get nodes"
    get_pods   = "kubectl get pods -A"
  }
  depends_on = [null_resource.join_rebellion_workers]
}

