# Control Plane Setup Not Running

## Issue Discovered

The control plane setup never executed. Investigation shows:

- ✅ Cloud-init completed successfully
- ✅ VMs are accessible via SSH
- ❌ Setup scripts were never copied to `/tmp`
- ❌ kubectl/kubeadm not installed
- ❌ Kubernetes cluster not initialized
- ❌ Join command never generated

## Root Cause

The `null_resource.control_plane_setup` provisioners failed to run, likely because:

1. Terraform lost connection during file provisioning
2. The resource was skipped due to an earlier error
3. The control plane resource has a trigger that prevented execution

## Immediate Fix: Manually Run Control Plane Setup

### Step 1: Copy Setup Scripts to Control Plane

From your local machine:

```bash
# Copy common setup script
scp -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
  scripts/deployment/k8s-common-setup.sh ubuntu@192.168.0.32:/tmp/

# Copy control plane setup script
scp -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
  scripts/deployment/k8s-control-plane-setup.sh ubuntu@192.168.0.32:/tmp/

# Copy SSH keys for inter-node communication
scp -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
  ~/.ssh/maint-rsa ubuntu@192.168.0.32:~/.ssh/
  
scp -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
  ~/.ssh/maint-rsa.pub ubuntu@192.168.0.32:~/.ssh/
```

### Step 2: Run Common Setup on Control Plane

```bash
# SSH to control plane
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.32

# Make scripts executable
chmod +x /tmp/k8s-common-setup.sh
chmod +x /tmp/k8s-control-plane-setup.sh

# Fix SSH key permissions
chmod 600 ~/.ssh/maint-rsa
chmod 644 ~/.ssh/maint-rsa.pub

# Run common setup (installs kubectl, kubeadm, containerd, etc.)
sudo env K8S_VERSION=1.28 /tmp/k8s-common-setup.sh
```

This will take 5-10 minutes. Watch for any errors.

### Step 3: Run Control Plane Setup

Still on the control plane:

```bash
# Run control plane setup (initializes Kubernetes cluster)
sudo env POD_NETWORK_CIDR=10.244.0.0/16 \
  SERVICE_CIDR=10.96.0.0/12 \
  CONTROL_PLANE_IP=192.168.0.32 \
  SSH_USER=ubuntu \
  /tmp/k8s-control-plane-setup.sh
```

This will take 5-10 minutes. It will:
- Initialize the Kubernetes cluster
- Install Flannel CNI
- Generate the join command
- Save it to `/tmp/kubeadm-join-command.sh`

### Step 4: Verify Control Plane

```bash
# Check cluster status
kubectl get nodes

# Should show:
# NAME        STATUS   ROLES           AGE   VERSION
# bumblebee   Ready    control-plane   ...   v1.28.x

# Check system pods
kubectl get pods -A
```

### Step 5: Verify Join Command Exists

```bash
# Check join command was created
ls -la /tmp/kubeadm-join-command.sh
cat /tmp/kubeadm-join-command.sh
```

### Step 6: Copy Kubeconfig Locally

From your local machine:

```bash
# Copy kubeconfig to your machine
mkdir -p ~/.kube
scp -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
  ubuntu@192.168.0.32:~/.kube/config ~/.kube/config

# Test it works
kubectl get nodes
```

## Now Re-run Worker Setup

### Option 1: Let Terraform Join Workers

```bash
terraform apply \
  -target=null_resource.worker_setup \
  -var="bootstrap_cluster=true"
```

### Option 2: Manually Join Workers

If Terraform continues to have issues:

```bash
# Get join command from control plane
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.32 \
  "cat /tmp/kubeadm-join-command.sh"

# Copy the output, then for each worker:

# Prime (192.168.0.34)
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.34
sudo <paste join command>
exit

# Wheeljack (192.168.0.33)
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.33
sudo <paste join command>
exit
```

## Verify Complete Cluster

```bash
kubectl get nodes -o wide

# Should show:
# NAME        STATUS   ROLES           AGE   VERSION   INTERNAL-IP     ...
# bumblebee   Ready    control-plane   ...   v1.28.x   192.168.0.32   ...
# prime       Ready    <none>          ...   v1.28.x   192.168.0.34   ...
# wheeljack   Ready    <none>          ...   v1.28.x   192.168.0.33   ...
```

## Why This Happened

The `null_resource.control_plane_setup` has triggers that make it run only when certain values change. If Terraform thinks it already ran (even though it didn't), it won't run again.

Check the Terraform state:

```bash
terraform state show null_resource.control_plane_setup[0]
```

If it shows as "created" but the scripts never actually ran, you'll need to either:
- Manually run the setup (as above)
- Or destroy and recreate the resource

## Prevention for Future

To prevent this in future deployments:

### Option 1: Add Better Error Handling

Update `k8s-cluster.tf` to fail loudly if provisioners don't complete.

### Option 2: Use Separate Apply Targets

Always run in stages:

```bash
# Stage 1: VMs only
terraform apply -target=proxmox_virtual_environment_vm.bumblebee \
  -target=proxmox_virtual_environment_vm.prime \
  -target=proxmox_virtual_environment_vm.wheeljack

# Stage 2: Control plane only
terraform apply -target=null_resource.control_plane_setup

# Stage 3: Workers only
terraform apply -target=null_resource.worker_setup

# Stage 4: Everything else
terraform apply
```

### Option 3: Use Cloud-Init for Initial Setup

Move more of the setup into cloud-init so it runs automatically when VMs boot, reducing reliance on Terraform provisioners.

## Quick Command Summary

```bash
# 1. Copy scripts
scp -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no scripts/deployment/k8s-common-setup.sh ubuntu@192.168.0.32:/tmp/
scp -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no scripts/deployment/k8s-control-plane-setup.sh ubuntu@192.168.0.32:/tmp/

# 2. SSH and setup
ssh -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.32
chmod +x /tmp/*.sh
sudo env K8S_VERSION=1.28 /tmp/k8s-common-setup.sh
sudo env POD_NETWORK_CIDR=10.244.0.0/16 SERVICE_CIDR=10.96.0.0/12 CONTROL_PLANE_IP=192.168.0.32 SSH_USER=ubuntu /tmp/k8s-control-plane-setup.sh
exit

# 3. Copy kubeconfig
scp -i ~/.ssh/maint-rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@192.168.0.32:~/.kube/config ~/.kube/config

# 4. Join workers
terraform apply -target=null_resource.worker_setup -var="bootstrap_cluster=true"
```


