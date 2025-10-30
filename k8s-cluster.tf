# Wait for VMs to be fully ready
resource "null_resource" "wait_for_vms" {
  count = var.bootstrap_cluster ? 1 : 0

  depends_on = [
    proxmox_virtual_environment_vm.bumblebee,
    proxmox_virtual_environment_vm.prime,
    proxmox_virtual_environment_vm.wheeljack
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for VMs to be accessible..."
      for ip in ${var.control_plane_ip} ${join(" ", var.worker_ips)}; do
        echo "Waiting for $ip to be accessible..."
        timeout 300 bash -c "until nc -z $ip 22; do sleep 5; done"
        echo "VM at $ip is accessible"
      done
      echo "All VMs are ready"
    EOT
  }
}

# Remote execution for control plane setup
resource "null_resource" "control_plane_setup" {
  count      = var.bootstrap_cluster ? 1 : 0
  depends_on = [null_resource.wait_for_vms]
  connection {
    type        = "ssh"
    host        = var.control_plane_ip
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
  }

  # Copy SSH key for inter-node communication
  provisioner "file" {
    source      = var.ssh_private_key_path
    destination = "/home/${var.ssh_user}/.ssh/maint-rsa"
  }

  provisioner "file" {
    source      = "${var.ssh_private_key_path}.pub"
    destination = "/home/${var.ssh_user}/.ssh/maint-rsa.pub"
  }

  # Also provide alias name 'naint-rsa' if referenced elsewhere
  provisioner "file" {
    source      = var.ssh_private_key_path
    destination = "/home/${var.ssh_user}/.ssh/naint-rsa"
  }

  provisioner "file" {
    source      = "${var.ssh_private_key_path}.pub"
    destination = "/home/${var.ssh_user}/.ssh/naint-rsa.pub"
  }

  # Set SSH key permissions
  provisioner "remote-exec" {
    inline = [
      "chmod 600 ~/.ssh/maint-rsa",
      "chmod 644 ~/.ssh/maint-rsa.pub",
      "chmod 600 ~/.ssh/naint-rsa || true",
      "chmod 644 ~/.ssh/naint-rsa.pub || true"
    ]
  }

  # Copy setup scripts
  provisioner "file" {
    source      = "scripts/k8s-common-setup.sh"
    destination = "/tmp/k8s-common-setup.sh"
  }

  provisioner "file" {
    source      = "scripts/k8s-control-plane-setup.sh"
    destination = "/tmp/k8s-control-plane-setup.sh"
  }

  # Wait for cloud-init and run common setup
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "sudo cloud-init status --wait",
      "echo 'Waiting for apt locks to be released...'",
      "timeout 300 bash -c 'while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do echo \"Waiting for apt lock...\"; sleep 5; done'",
      "timeout 300 bash -c 'while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do echo \"Waiting for dpkg lock...\"; sleep 5; done'",
      "echo 'System ready, starting Kubernetes setup...'",
      "sudo chmod +x /tmp/k8s-common-setup.sh",
      "sudo K8S_VERSION=${var.k8s_version} /tmp/k8s-common-setup.sh"
    ]
  }

  # Run control plane setup
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/k8s-control-plane-setup.sh",
      "sudo POD_NETWORK_CIDR=${var.pod_network_cidr} SERVICE_CIDR=${var.service_cidr} CONTROL_PLANE_IP=${var.control_plane_ip} SSH_USER=${var.ssh_user} /tmp/k8s-control-plane-setup.sh"
    ]
  }

  triggers = {
    control_plane_ip = var.control_plane_ip
    k8s_version      = var.k8s_version
  }
}

# Remote execution for worker nodes setup
resource "null_resource" "worker_setup" {
  count      = var.bootstrap_cluster ? length(var.worker_ips) : 0
  depends_on = [null_resource.wait_for_vms, null_resource.control_plane_setup]

  connection {
    type        = "ssh"
    host        = var.worker_ips[count.index]
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
  }

  # Copy SSH key for inter-node communication
  provisioner "file" {
    source      = var.ssh_private_key_path
    destination = "/home/${var.ssh_user}/.ssh/maint-rsa"
  }

  provisioner "file" {
    source      = "${var.ssh_private_key_path}.pub"
    destination = "/home/${var.ssh_user}/.ssh/maint-rsa.pub"
  }

  # Also provide alias name 'naint-rsa'
  provisioner "file" {
    source      = var.ssh_private_key_path
    destination = "/home/${var.ssh_user}/.ssh/naint-rsa"
  }

  provisioner "file" {
    source      = "${var.ssh_private_key_path}.pub"
    destination = "/home/${var.ssh_user}/.ssh/naint-rsa.pub"
  }

  # Set SSH key permissions
  provisioner "remote-exec" {
    inline = [
      "chmod 600 ~/.ssh/maint-rsa",
      "chmod 644 ~/.ssh/maint-rsa.pub",
      "chmod 600 ~/.ssh/naint-rsa || true",
      "chmod 644 ~/.ssh/naint-rsa.pub || true"
    ]
  }

  # Copy setup scripts
  provisioner "file" {
    source      = "scripts/k8s-common-setup.sh"
    destination = "/tmp/k8s-common-setup.sh"
  }

  provisioner "file" {
    source      = "scripts/k8s-worker-setup.sh"
    destination = "/tmp/k8s-worker-setup.sh"
  }

  # Wait for cloud-init and run common setup
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "sudo cloud-init status --wait",
      "echo 'Waiting for apt locks to be released...'",
      "timeout 300 bash -c 'while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do echo \"Waiting for apt lock...\"; sleep 5; done'",
      "timeout 300 bash -c 'while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do echo \"Waiting for dpkg lock...\"; sleep 5; done'",
      "echo 'System ready, starting Kubernetes setup...'",
      "sudo chmod +x /tmp/k8s-common-setup.sh",
      "sudo K8S_VERSION=${var.k8s_version} /tmp/k8s-common-setup.sh"
    ]
  }

  # Run worker setup
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/k8s-worker-setup.sh",
      "sudo CONTROL_PLANE_IP=${var.control_plane_ip} SSH_USER=${var.ssh_user} SSH_PRIVATE_KEY_PATH=/home/${var.ssh_user}/.ssh/maint-rsa /tmp/k8s-worker-setup.sh"
    ]
  }

  triggers = {
    worker_ip        = var.worker_ips[count.index]
    control_plane_ip = var.control_plane_ip
    k8s_version      = var.k8s_version
  }
}

# Copy kubeconfig locally
resource "null_resource" "copy_kubeconfig" {
  count      = var.bootstrap_cluster ? 1 : 0
  depends_on = [null_resource.control_plane_setup]

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} ${var.ssh_user}@${var.control_plane_ip}:~/.kube/config ~/.kube/config"
  }

  triggers = {
    control_plane_ip = var.control_plane_ip
  }
}

# Marker resource to gate Kubernetes resources when bootstrapping
resource "null_resource" "kubeconfig_ready" {
  depends_on = [
    proxmox_virtual_environment_vm.bumblebee,
    proxmox_virtual_environment_vm.prime,
    proxmox_virtual_environment_vm.wheeljack,
    null_resource.control_plane_setup,
    null_resource.copy_kubeconfig
  ]

  provisioner "local-exec" {
    command = var.bootstrap_cluster ? "i=0; while [ ! -f ~/.kube/config ] && [ $i -lt 300 ]; do sleep 2; i=$((i+2)); done; [ -f ~/.kube/config ] || exit 1" : "echo 'Using existing kubeconfig'"
  }

  triggers = {
    mode      = var.bootstrap_cluster ? "bootstrap" : "external"
    timestamp = timestamp()
  }
}

# Gate: API server reachable using current kubeconfig
resource "null_resource" "cluster_api_ready" {
  provisioner "local-exec" {
    command = "i=0; until curl -sk --max-time 2 https://${var.control_plane_ip}:6443/healthz >/dev/null 2>&1; do [ $i -ge 900 ] && exit 1; sleep 3; i=$((i+3)); done"
  }

  depends_on = [
    null_resource.kubeconfig_ready,
    null_resource.control_plane_setup,
    null_resource.worker_setup
  ]
}
