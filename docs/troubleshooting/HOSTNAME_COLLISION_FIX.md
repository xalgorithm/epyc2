# Hostname Collision Fix

## Problem

All three VMs (bumblebee, prime, wheeljack) have the hostname "ubuntu" instead of their proper names. This prevents workers from joining the Kubernetes cluster with the error:

```
error execution phase kubelet-start: a Node with name "ubuntu" and status "Ready" already exists in the cluster
```

## Root Cause

The Terraform configuration sets VM names in Proxmox but doesn't configure cloud-init to set the actual hostname inside the VMs. The `initialization` blocks in `proxmox-vms.tf` only set IP addresses, not hostnames.

## Immediate Fix (For Existing VMs)

### Step 1: Fix Hostnames on All VMs

```bash
# Fix control plane hostname
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.32 \
  "sudo hostnamectl set-hostname bumblebee && echo 'Hostname set to bumblebee'"

# Fix worker 1 hostname
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.34 \
  "sudo hostnamectl set-hostname prime && echo 'Hostname set to prime'"

# Fix worker 2 hostname
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.33 \
  "sudo hostnamectl set-hostname wheeljack && echo 'Hostname set to wheeljack'"
```

### Step 2: Verify Hostnames

```bash
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.32 "hostname"
# Should output: bumblebee

ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.34 "hostname"
# Should output: prime

ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.33 "hostname"
# Should output: wheeljack
```

### Step 3: Update Control Plane Node Name in Kubernetes

The control plane is already registered in the cluster with the name "ubuntu". We need to update it:

```bash
# First, drain the control plane node (if possible)
kubectl drain ubuntu --ignore-daemonsets --delete-emptydir-data || true

# Delete the old node from the cluster
kubectl delete node ubuntu

# Restart kubelet on control plane to rejoin with new hostname
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.32 \
  "sudo systemctl restart kubelet"

# Wait a moment for the node to rejoin
sleep 30

# Verify the node rejoined with correct name
kubectl get nodes
# Should now show "bumblebee" instead of "ubuntu"
```

**Note**: If the control plane node doesn't automatically rejoin, you may need to re-initialize it. See "Nuclear Option" below.

### Step 4: Reset and Rejoin Workers

```bash
# Reset worker 1 (prime)
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.34 \
  "sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d && sudo ip link delete flannel.1 || true"

# Reset worker 2 (wheeljack)
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.33 \
  "sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d && sudo ip link delete flannel.1 || true"
```

### Step 5: Generate New Join Command

```bash
# Get fresh join command from control plane
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.32 \
  "sudo kubeadm token create --print-join-command | sudo tee /tmp/kubeadm-join-command.sh && sudo chmod +x /tmp/kubeadm-join-command.sh"
```

### Step 6: Join Workers

```bash
# Join prime (worker 1)
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.34 \
  "sudo scp -o StrictHostKeyChecking=no -i ~/.ssh/maint-rsa ubuntu@192.168.0.32:/tmp/kubeadm-join-command.sh /tmp/ && \
   sudo chmod +x /tmp/kubeadm-join-command.sh && \
   sudo /tmp/kubeadm-join-command.sh"

# Join wheeljack (worker 2)
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.33 \
  "sudo scp -o StrictHostKeyChecking=no -i ~/.ssh/maint-rsa ubuntu@192.168.0.32:/tmp/kubeadm-join-command.sh /tmp/ && \
   sudo chmod +x /tmp/kubeadm-join-command.sh && \
   sudo /tmp/kubeadm-join-command.sh"
```

### Step 7: Verify Complete Cluster

```bash
kubectl get nodes -o wide
# Should show:
# NAME        STATUS   ROLES           AGE   VERSION   INTERNAL-IP     ...
# bumblebee   Ready    control-plane   ...   v1.28.x   192.168.0.32   ...
# prime       Ready    <none>          ...   v1.28.x   192.168.0.34   ...
# wheeljack   Ready    <none>          ...   v1.28.x   192.168.0.33   ...
```

## Nuclear Option: Full Cluster Re-initialization

If the control plane doesn't rejoin properly after the hostname change:

### 1. Reset All Nodes

```bash
# Reset control plane
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.32 \
  "sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d ~/.kube"

# Reset workers (already done above)
```

### 2. Re-run Control Plane Setup

```bash
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.32

# Re-run control plane setup
sudo env POD_NETWORK_CIDR=10.244.0.0/16 \
  SERVICE_CIDR=10.96.0.0/12 \
  CONTROL_PLANE_IP=192.168.0.32 \
  SSH_USER=ubuntu \
  /tmp/k8s-control-plane-setup.sh

exit
```

### 3. Copy kubeconfig and join workers (Steps 5-7 above)

## Permanent Fix (Terraform Configuration)

Update `proxmox-vms.tf` to set hostnames in the cloud-init `initialization` block:

### For bumblebee (control plane):

```hcl
initialization {
  ip_config {
    ipv4 {
      address = "${var.control_plane_ip}/24"
      gateway = var.vm_gateway
    }
  }
  
  datastore_id      = "local"
  user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data.id
}
```

Actually, the Proxmox provider sets hostname automatically from the `name` parameter when `agent.enabled = true` and the guest agent is running. The issue is timing - the hostname change happens AFTER cloud-init finishes, but Kubernetes setup happens during provisioning.

### Better Solution: Set Hostname in Cloud-Init User Data

Since we use a shared cloud-init file, we need per-VM hostname configuration. We should:

1. Create separate cloud-init files for each VM, OR
2. Use the `hostname` field in the `initialization` block, OR
3. Add hostname to the cloud-init user_data template with a variable

**Option 2 is simplest** - add to each VM's initialization block:

```hcl
# In bumblebee VM
initialization {
  datastore_id = "local"
  
  ip_config {
    ipv4 {
      address = "${var.control_plane_ip}/24"
      gateway = var.vm_gateway
    }
  }
  
  user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data.id
}
```

**Update**: After checking the provider documentation, the `initialization` block doesn't have a direct `hostname` field. The hostname is set by Proxmox based on the VM's `name` parameter when the guest agent reports in.

**The real fix**: Add a `preserve_hostname: false` and `fqdn` setting to each VM's cloud-init config, OR use separate cloud-init files per VM.

### Recommended Approach: Per-VM Cloud-Init Files

Update `proxmox-vms.tf` to create separate cloud-init files:

```hcl
# Cloud-init for bumblebee
resource "proxmox_virtual_environment_file" "cloud_init_bumblebee" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = <<-EOF
      #cloud-config
      hostname: bumblebee
      fqdn: bumblebee.local
      manage_etc_hosts: true
      package_update: true
      package_upgrade: false
      packages:
        - qemu-guest-agent
        - nfs-common
      users:
        - name: ${var.ssh_user}
          sudo: ALL=(ALL) NOPASSWD:ALL
          groups: sudo
          shell: /bin/bash
          ssh_authorized_keys:
            - ${trimspace(file("${var.ssh_private_key_path}.pub"))}
      runcmd:
        - systemctl start qemu-guest-agent
        - systemctl enable qemu-guest-agent
      EOF

    file_name = "cloud-init-bumblebee.yaml"
  }
}

# Similar for prime and wheeljack...
```

Then update each VM to use its own cloud-init file:
```hcl
user_data_file_id = proxmox_virtual_environment_file.cloud_init_bumblebee.id
```

## Verification

After applying the fixes:

```bash
# Check hostnames
for ip in 192.168.0.32 192.168.0.34 192.168.0.33; do
  echo "Checking $ip:"
  ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$ip "hostname"
done

# Check Kubernetes nodes
kubectl get nodes -o wide

# All three nodes should show correct names and be Ready
```

## Prevention

For future deployments:
1. ✅ Use per-VM cloud-init files with hostname settings
2. ✅ Set `manage_etc_hosts: true` in cloud-init
3. ✅ Verify hostnames before Kubernetes initialization
4. ✅ Add hostname validation to pre-flight checks

