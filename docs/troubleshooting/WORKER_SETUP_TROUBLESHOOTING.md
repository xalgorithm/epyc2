# Worker Setup Troubleshooting Guide

## Issue

Workers are failing to join the Kubernetes cluster with error:
```
Error: remote-exec provisioner error
error executing "/tmp/terraform_*.sh": Process exited with status 1
```

## Enhanced Error Checking

The worker setup script now includes detailed diagnostics to help identify the exact issue:

1. **SSH key verification** - Checks if the key exists
2. **SSH connectivity test** - Tests connection to control plane
3. **Join command retrieval** - Verifies the file exists on control plane
4. **Detailed error messages** - Shows exactly what failed

## Common Issues and Solutions

### Issue 1: SSH Key Not Found on Worker

**Symptoms:**
```
ERROR: SSH private key not found at /home/ubuntu/.ssh/maint-rsa
```

**Solution:**
The SSH key wasn't copied to the worker. Check if the file provisioners ran successfully in the Terraform output.

### Issue 2: Cannot SSH from Worker to Control Plane

**Symptoms:**
```
ERROR: Cannot SSH to control plane at 192.168.0.32
```

**Possible Causes:**
1. Control plane isn't ready yet
2. SSH key mismatch
3. Network connectivity issues
4. Firewall blocking SSH

**Solution:**
```bash
# Test SSH from your local machine to control plane
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.32

# If that works, test from worker to control plane
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.34  # Log into worker
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.32  # Try to reach control plane
```

### Issue 3: Join Command Not Found

**Symptoms:**
```
ERROR: Failed to retrieve join command from control plane
Join command file not found on control plane!
```

**Possible Causes:**
1. Control plane setup didn't complete
2. The join command wasn't generated
3. File permissions issue

**Solution:**
```bash
# SSH to control plane and check
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.32

# Check if join command exists
ls -la /tmp/kubeadm-join-command.sh

# Check control plane setup logs
sudo tail -100 /var/log/k8s-control-plane-setup.log

# If join command is missing, regenerate it
sudo kubeadm token create --print-join-command > /tmp/kubeadm-join-command.sh
sudo chmod +x /tmp/kubeadm-join-command.sh
```

### Issue 4: Cloud-Init Still Running

**Symptoms:**
Script times out or packages fail to install

**Solution:**
Wait for cloud-init to complete before worker setup runs. The script already includes a wait, but if it's taking too long:

```bash
# SSH to worker
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.34

# Check cloud-init status
cloud-init status

# If it's still running, wait for it
sudo cloud-init status --wait

# Check for errors
cat /var/log/cloud-init-output.log
```

## Viewing Logs

### Worker Setup Logs

```bash
# SSH to worker
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.34

# View worker setup log
sudo tail -100 /var/log/k8s-worker-setup.log

# View common setup log
sudo tail -100 /var/log/k8s-common-setup.log
```

### Control Plane Setup Logs

```bash
# SSH to control plane
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.32

# View control plane setup log
sudo tail -100 /var/log/k8s-control-plane-setup.log

# View common setup log
sudo tail -100 /var/log/k8s-common-setup.log

# Check Kubernetes cluster status
kubectl get nodes
kubectl get pods -A
```

## Re-running the Deployment

After making any fixes, you can retry the worker setup:

### Option 1: Retry Just Worker Setup

```bash
terraform apply \
  -target=null_resource.worker_setup \
  -var="bootstrap_cluster=true"
```

### Option 2: Full Stage 1 Deployment

```bash
terraform apply \
  -target=proxmox_virtual_environment_file.cloud_init_user_data \
  -target=proxmox_virtual_environment_vm.bumblebee \
  -target=proxmox_virtual_environment_vm.prime \
  -target=proxmox_virtual_environment_vm.wheeljack \
  -target=null_resource.prepare_kubeconfig \
  -target=null_resource.wait_for_vms \
  -target=null_resource.control_plane_setup \
  -target=null_resource.worker_setup \
  -target=null_resource.copy_kubeconfig \
  -target=null_resource.kubeconfig_ready \
  -target=null_resource.cluster_api_ready \
  -var="bootstrap_cluster=true"
```

## Manual Worker Join (Last Resort)

If Terraform continues to fail, you can manually join workers:

### Step 1: Get Join Command from Control Plane

```bash
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.32
sudo kubeadm token create --print-join-command
```

### Step 2: Join Each Worker

```bash
# For prime (192.168.0.34)
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.34
sudo <paste the join command here>

# For wheeljack (192.168.0.33)
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.33
sudo <paste the join command here>
```

### Step 3: Verify

```bash
ssh -i ~/.ssh/maint-rsa ubuntu@192.168.0.32
kubectl get nodes
```

Should show all 3 nodes (bumblebee, prime, wheeljack) in Ready state.

## Verification Commands

After successful deployment:

```bash
# Check all nodes are Ready
kubectl get nodes -o wide

# Check all system pods are running
kubectl get pods -A

# Check node details
kubectl describe node prime
kubectl describe node wheeljack

# Verify Flannel CNI is working
kubectl get pods -n kube-flannel
```

## Common Terraform Apply Output Analysis

### Good Output (Worker Joining)

```
Testing SSH connectivity to control plane 192.168.0.32...
SSH connection successful
Retrieving join command from control plane...
Join command content:
kubeadm join 192.168.0.32:6443 --token...
Joining the Kubernetes cluster...
[kubelet] Joining node...
Worker node setup completed successfully!
```

### Bad Output (SSH Failure)

```
Testing SSH connectivity to control plane 192.168.0.32...
ERROR: Cannot SSH to control plane at 192.168.0.32
```

### Bad Output (Missing Join Command)

```
ERROR: Failed to retrieve join command from control plane
Checking if join command exists on control plane...
ls: cannot access '/tmp/kubeadm-join-command.sh': No such file or directory
```

## Prevention

To avoid these issues in future deployments:

1. ✅ Ensure cloud-init completes before provisioners run
2. ✅ Verify SSH keys are properly distributed
3. ✅ Check control plane is fully initialized before joining workers
4. ✅ Use explicit dependencies in Terraform
5. ✅ Add timeouts and retries where appropriate

All of these are now implemented in the current configuration!

