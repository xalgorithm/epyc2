# Proxmox Snippets Directory Setup

## Issue

The Proxmox `local` storage needs a `snippets` directory to store cloud-init configuration files.

## Error

```
Error: error transferring file: /usr/bin/tee: /var/lib/vz/snippets/cloud-init-userdata.yaml: No such file or directory
```

## Solution

You need to create the snippets directory on your Proxmox host.

### Method 1: Manual Creation (Recommended)

SSH to your Proxmox host and create the directory:

```bash
ssh xalg@192.168.0.7

# Once logged in to Proxmox:
sudo mkdir -p /var/lib/vz/snippets
sudo chmod 755 /var/lib/vz/snippets

# Verify it was created:
ls -la /var/lib/vz/
```

### Method 2: One-Liner from Your Mac

Run this command from your local machine:

```bash
ssh -t xalg@192.168.0.7 "sudo mkdir -p /var/lib/vz/snippets && sudo chmod 755 /var/lib/vz/snippets && ls -la /var/lib/vz/"
```

This will prompt you for your password once.

### Method 3: Configure Passwordless Sudo (Optional)

If you want Terraform to handle this automatically in the future, configure passwordless sudo for directory creation:

```bash
ssh xalg@192.168.0.7

# Add this to sudoers
sudo visudo -f /etc/sudoers.d/terraform

# Add this line:
xalg ALL=(ALL) NOPASSWD: /bin/mkdir -p /var/lib/vz/snippets, /bin/chmod 755 /var/lib/vz/snippets
```

## Verification

After creating the directory, verify it exists:

```bash
ssh xalg@192.168.0.7 "ls -la /var/lib/vz/snippets"
```

Expected output:
```
drwxr-xr-x 2 root root 4096 ... snippets
```

## After Directory is Created

Once the directory exists, run your Terraform apply command again:

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

## Alternative: Enable Snippets in Proxmox Storage

If the above doesn't work, you may need to enable snippets content type for the `local` storage in Proxmox:

### Via Proxmox Web UI

1. Go to **Datacenter** → **Storage**
2. Click on **local**
3. In the **Content** field, ensure **Snippets** is checked
4. Click **OK**

### Via Command Line

```bash
ssh xalg@192.168.0.7

# Check current storage configuration:
pvesm status

# Add snippets content to local storage:
sudo pvesm set local --content vztmpl,iso,backup,snippets
```

## Why This is Needed

The Proxmox provider uploads cloud-init configuration files to the `local` storage's snippets directory. This directory must exist and be writable by the user specified in the Terraform Proxmox provider SSH configuration.

The cloud-init file contains:
- Package installations (qemu-guest-agent, nfs-common)
- Service startup commands
- Initial VM configuration

Without this, VMs cannot be configured automatically during creation.

