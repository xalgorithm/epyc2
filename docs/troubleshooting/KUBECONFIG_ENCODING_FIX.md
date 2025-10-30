# Kubeconfig Secret Encoding Fix

## Problem
The manual backup jobs were failing with a kubeconfig parsing error:
```
error loading config file "/root/.kube/config": couldn't get version/kind; json parse error: json: cannot unmarshal string into Go value of type struct
```

## Root Cause
The `backup-kubeconfig` secret was being **double-encoded**:
1. Terraform's `base64encode()` function encoded the kubeconfig file
2. Kubernetes secrets automatically base64 encode their data
3. Result: The kubeconfig was base64 encoded twice, making it unreadable

## Solution Applied

### 1. Fixed Terraform Configuration
**Before** (double encoding):
```hcl
data = {
  "config" = base64encode(file("~/.kube/config"))
}
```

**After** (correct encoding):
```hcl
data = {
  "config" = file("~/.kube/config")
}
```

### 2. Created Fix Script
- `scripts/fix-kubeconfig-secret.sh` - Detects and fixes double-encoded secrets
- Validates kubeconfig format and connectivity
- Tests the secret in a pod environment

## How to Apply the Fix

### Option 1: Terraform Apply (Recommended)
```bash
# This will recreate the secret with correct encoding
terraform apply
```

### Option 2: Manual Fix Script
```bash
# Detect and fix existing double-encoded secret
./scripts/fix-kubeconfig-secret.sh
```

### Option 3: Manual Recreation
```bash
# Delete the corrupted secret
kubectl delete secret backup-kubeconfig -n backup

# Recreate with correct encoding
kubectl create secret generic backup-kubeconfig -n backup --from-file=config=~/.kube/config
```

## Verification Steps

### 1. Test Kubeconfig Secret
```bash
./scripts/fix-kubeconfig-secret.sh
```

### 2. Test kubectl Access
```bash
./scripts/test-manual-backup-kubectl.sh
```

### 3. Test Manual Backup
```bash
./scripts/trigger-manual-backup.sh apps
```

## Understanding the Issue

### What Happened
1. **Terraform**: `base64encode(file("~/.kube/config"))` → Base64 encoded kubeconfig
2. **Kubernetes**: Automatically base64 encodes secret data → Double encoded
3. **Pod**: Tries to decode once → Gets base64 string instead of YAML
4. **kubectl**: Fails to parse base64 string as YAML kubeconfig

### What Should Happen
1. **Terraform**: `file("~/.kube/config")` → Raw kubeconfig YAML
2. **Kubernetes**: Automatically base64 encodes secret data → Single encoded
3. **Pod**: Kubernetes automatically decodes → Gets YAML kubeconfig
4. **kubectl**: Successfully parses YAML kubeconfig

## Files Modified

1. **`backup.tf`** - Removed `base64encode()` wrapper from kubeconfig secret
2. **`scripts/fix-kubeconfig-secret.sh`** - New script to detect and fix encoding issues
3. **Backup ConfigMap** - Added fix script for future use

## Testing the Fix

### Before Fix
```bash
# Inside backup pod
cat /root/.kube/config
# Output: YXBpVmVyc2lvbjogdjEKY2x1c3RlcnM6Ci0gY2x1c3RlcjoK... (base64)

kubectl cluster-info
# Error: json parse error
```

### After Fix
```bash
# Inside backup pod
cat /root/.kube/config
# Output: 
# apiVersion: v1
# clusters:
# - cluster:
#     certificate-authority-data: LS0t...

kubectl cluster-info
# Output: Kubernetes control plane is running at https://...
```

## Prevention

This issue is now prevented by:
1. **Correct Terraform configuration** - No double encoding
2. **Validation script** - Detects encoding issues
3. **Test scripts** - Verify kubeconfig works in pod environment

## Related Issues

This fix resolves:
- Manual backup jobs failing with kubeconfig errors
- kubectl commands not working in backup pods
- "json parse error" when loading kubeconfig
- Authentication failures in backup operations

The scheduled backup jobs (using Alpine + kubectl install) were not affected by this issue since they don't use the kubeconfig secret.

## Next Steps

After applying this fix:
1. **Apply Terraform**: `terraform apply`
2. **Test kubectl**: `./scripts/test-manual-backup-kubectl.sh`
3. **Test backup**: `./scripts/trigger-manual-backup.sh apps`
4. **Monitor jobs**: `kubectl get jobs -n backup`

The manual backup system should now work correctly with proper kubeconfig access.