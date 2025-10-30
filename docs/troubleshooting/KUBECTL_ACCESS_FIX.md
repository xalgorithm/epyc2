# kubectl Access Fix for Manual Backup Jobs

## Problem
The manual backup job was failing with "kubectl is not available, please ensure kubeconfig is set up" because the Alpine Linux container didn't have kubectl installed.

## Root Cause
The `trigger-manual-backup.sh` script was using `alpine:3.18` image which doesn't include kubectl. The manual backup script requires kubectl to interact with the Kubernetes cluster to backup application data.

## Solution Applied

### 1. Changed Container Image
**Before**: `alpine:3.18` (no kubectl)
**After**: `bitnami/kubectl:latest` (kubectl pre-installed)

### 2. Updated Job Configuration
- Changed from `/bin/sh` to `/bin/bash` (bitnami/kubectl uses bash)
- Added explicit `KUBECONFIG` environment variable
- Enhanced kubectl connectivity checks in the backup script

### 3. Enhanced Error Handling
- Added better kubectl version and connectivity checks
- Improved error messages for troubleshooting
- Added current context information for debugging

## Files Modified

### `scripts/trigger-manual-backup.sh`
```yaml
# Before
image: alpine:3.18
command: ["/bin/sh"]

# After  
image: bitnami/kubectl:latest
command: ["/bin/bash"]
env:
- name: KUBECONFIG
  value: "/root/.kube/config"
```

### `scripts/manual-backup-comprehensive.sh`
- Enhanced prerequisites check with better error messages
- Added kubectl version and context information
- Improved cluster connectivity testing

### `backup.tf`
- Added new test script to ConfigMap for kubectl verification

## Verification Steps

### 1. Test kubectl Access
```bash
# Test kubectl access in manual backup environment
./scripts/test-manual-backup-kubectl.sh
```

### 2. Test Manual Backup
```bash
# Try a simple manual backup
./scripts/trigger-manual-backup.sh apps

# Try full backup
./scripts/trigger-manual-backup.sh all
```

### 3. Check Job Logs
```bash
# Monitor job execution
kubectl get jobs -n backup -l app=manual-backup

# View job logs
kubectl logs -l app=manual-backup -n backup
```

## How It Works Now

1. **Job Creation**: `trigger-manual-backup.sh` creates a Kubernetes Job
2. **Container**: Uses `bitnami/kubectl:latest` with kubectl pre-installed
3. **Kubeconfig**: Mounts backup service account kubeconfig at `/root/.kube/config`
4. **Environment**: Sets `KUBECONFIG` environment variable
5. **Execution**: Runs `manual-backup-comprehensive.sh` with kubectl access
6. **Backup**: Script can now access all Kubernetes resources for backup

## Container Images Used

| Component | Image | Purpose |
|-----------|-------|---------|
| Scheduled Backups | `alpine:3.18` | Installs kubectl during execution |
| Manual Backups | `bitnami/kubectl:latest` | kubectl pre-installed |
| ETCD Backups | `k8s.gcr.io/etcd:3.5.9-0` | ETCD tools |

## Troubleshooting

### If kubectl Still Not Available
1. **Check image pull**: Verify `bitnami/kubectl:latest` can be pulled
2. **Check kubeconfig mount**: Ensure backup-kubeconfig secret exists
3. **Check service account**: Verify backup service account has proper permissions

### If Cluster Access Fails
1. **Check service account**: `kubectl get serviceaccount backup -n backup`
2. **Check kubeconfig secret**: `kubectl get secret backup-kubeconfig -n backup`
3. **Check cluster role**: `kubectl get clusterrolebinding backup`

### Manual Verification
```bash
# Test kubectl in a manual pod
kubectl run test-kubectl --rm -i --tty \
  --image=bitnami/kubectl:latest \
  --serviceaccount=backup \
  --namespace=backup \
  -- bash

# Inside the pod:
kubectl version --client
kubectl cluster-info
kubectl get namespaces
```

## Benefits of the Fix

1. **Reliable kubectl Access**: No need to install kubectl during job execution
2. **Faster Job Startup**: kubectl is pre-installed in the image
3. **Better Error Handling**: Clear error messages for troubleshooting
4. **Consistent Environment**: Same kubectl version across all manual backups
5. **Reduced Complexity**: No network dependencies for kubectl installation

The manual backup system should now work reliably with proper kubectl access for backing up all Kubernetes resources and application data.

## Next Steps

After applying this fix:

1. **Apply Terraform changes**: `terraform apply`
2. **Test kubectl access**: `./scripts/test-manual-backup-kubectl.sh`
3. **Test manual backup**: `./scripts/trigger-manual-backup.sh apps`
4. **Monitor scheduled backups**: Ensure they still work with Alpine + kubectl install