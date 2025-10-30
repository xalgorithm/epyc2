# Proxmox API Token Configuration

This document explains how to configure and use Proxmox API tokens for secure authentication.

## 🔑 Why Use API Tokens?

API tokens provide several advantages over password authentication:

- **Security**: No need to store passwords in configuration files
- **Granular Permissions**: Tokens can have specific permissions
- **Audit Trail**: Token usage is logged separately
- **Revocable**: Tokens can be disabled without changing passwords
- **Automation Friendly**: Better for CI/CD and automated deployments

## 📋 Current Configuration

Your terraform.tfvars is configured with:

```hcl
# API Token Authentication (Primary)
proxmox_api_token_id      = "your-username@pam!your-token-name"
proxmox_api_token_secret  = "your-token-secret"

# Password Authentication (Fallback)
proxmox_user              = "your-username@pam"
proxmox_password          = "your-password"
```

## 🔧 Provider Configuration

The Terraform provider automatically uses API tokens when available:

```hcl
provider "proxmox" {
  endpoint = var.proxmox_api_url
  
  # Use API token if provided, otherwise fall back to username/password
  api_token = var.proxmox_api_token_id != "" ? "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}" : null
  username  = var.proxmox_api_token_id != "" ? null : var.proxmox_user
  password  = var.proxmox_api_token_id != "" ? null : var.proxmox_password
  
  insecure = var.proxmox_tls_insecure
}
```

## ✅ Testing API Token

Test your API token configuration:

```bash
# Test API token authentication
./scripts/test-proxmox-api-token.sh

# Test Terraform plan
terraform plan -target=proxmox_virtual_environment_vm.bumblebee
```

## 🛠️ API Token Management

### Verify Token in Proxmox Web UI

1. Log into Proxmox web interface
2. Go to **Datacenter** → **Permissions** → **API Tokens**
3. Look for token: `your-username@pam!your-token`
4. Ensure it's **enabled** and has proper permissions

### Check Token Permissions

The token should have:

- **Path**: `/` (root)
- **Role**: `Administrator` or custom role with VM management permissions
- **Privilege Separation**: Disabled (for full access)

### Create New Token (if needed)

If the token doesn't exist or needs to be recreated:

```bash
# SSH to Proxmox host
ssh root@YOUR_PROXMOX_IP

# Create API token
pveum user token add your-username@pam your-token --privsep=0

# The command will output the secret - update terraform.tfvars with it
```

### Token Permissions Required

For VM management, the token needs these permissions:

- `VM.Allocate` - Create/delete VMs
- `VM.Config.Disk` - Manage VM disks
- `VM.Config.Memory` - Manage VM memory
- `VM.Config.Network` - Manage VM network
- `VM.Config.Options` - Manage VM options
- `VM.Monitor` - Monitor VM status
- `VM.PowerMgmt` - Start/stop VMs
- `Datastore.Allocate` - Use storage
- `SDN.Use` - Use network bridges

## 🔍 Troubleshooting

### API Token Authentication Failed

If you see authentication errors:

1. **Check token exists**:

   ```bash
   ssh root@PROXMOX_IP 'pveum user token list your-username@pam'
   ```

2. **Verify token is enabled**:
   - In Proxmox web UI, check the token isn't disabled

3. **Check permissions**:

   ```bash
   ssh root@PROXMOX_IP 'pveum user permissions your-username@pam'
   ```

4. **Test token manually**:

   ```bash
   curl -k -H "Authorization: PVEAPIToken=your-username@pam!your-token=your-token-secret" \
        "https://YOUR_PROXMOX_IP:8006/api2/json/version"
   ```

### Fallback to Password Authentication

If API token fails, the provider will automatically fall back to password authentication:

```bash
# Check if password auth works
curl -k -d "username=your-username@pam&password=your-password!" \
     "https://YOUR_PROXMOX_IP:8006/api2/json/access/ticket"
```

### Common Issues

1. **Token Expired**: Tokens don't expire by default, but check if it was manually disabled
2. **Insufficient Permissions**: Ensure token has Administrator role or required permissions
3. **Privilege Separation**: If enabled, token inherits user permissions (may be limited)
4. **Network Issues**: Ensure Proxmox API is accessible on port 8006

## 📚 Best Practices

1. **Use API Tokens**: Prefer tokens over passwords for automation
2. **Minimal Permissions**: Create tokens with only required permissions
3. **Regular Rotation**: Rotate tokens periodically for security
4. **Secure Storage**: Store token secrets securely (not in version control)
5. **Monitor Usage**: Check Proxmox logs for token usage

## 🔗 References

- [Proxmox API Token Documentation](https://pve.proxmox.com/pve-docs/pveum.1.html)
- [Proxmox API Reference](https://pve.proxmox.com/pve-docs/api-viewer/)
- [BPG Proxmox Provider Authentication](https://registry.terraform.io/providers/bpg/proxmox/latest/docs#authentication)

---

API token authentication provides secure and reliable access to your Proxmox infrastructure! 🔐
