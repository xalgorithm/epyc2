# Mylar Troubleshooting and Fix Summary

**Date:** December 15, 2025  
**Issue:** Mylar not responding  
**Status:** ✅ RESOLVED

## Problem Identified

### Root Cause: DNS Resolution Failure on Kubernetes Nodes

The Kubernetes nodes were unable to resolve external domain names due to misconfigured DNS settings. The systemd-resolved service on each node was using `127.0.0.53` which was unable to resolve external domains including:
- `lscr.io` (LinuxServer.io container registry)
- `docker.io` / `registry-1.docker.io` (Docker Hub)
- `walksoftly.itsaninja.party` (Mylar pull-list source)
- `comicvine.gamespot.com` (Comic metadata API)

### Symptoms Observed

1. **Image Pull Failures:**
   - New pods stuck in `ImagePullBackOff` state
   - Error: `dial tcp: lookup lscr.io on 127.0.0.53:53: server misbehaving`
   
2. **Application Issues:**
   - Mylar unable to fetch weekly pull lists
   - Unable to retrieve comic metadata from ComicVine
   - DNS resolution warnings in application logs

3. **Cluster-wide Impact:**
   - CoreDNS pods unable to pull new images
   - All deployments unable to pull container images from external registries

## Solution Implemented

### 1. Created DNS Fix Script

Created `/Users/xalg/dev/terraform/epyc2/scripts/maintenance/fix-node-dns.sh` to:
- Update systemd-resolved configuration on all nodes
- Configure Cloudflare DNS (1.1.1.1, 1.0.0.1) as primary
- Configure Google DNS (8.8.8.8, 8.8.4.4) as fallback
- Restart systemd-resolved service
- Verify DNS resolution for key registries

### 2. Applied Fix to All Nodes

Successfully updated DNS configuration on:
- **bumblebee** (192.168.0.32) - Control plane
- **prime** (192.168.0.34) - Worker node
- **wheeljack** (192.168.0.33) - Worker node

### 3. Restarted Affected Pods

- Deleted and recreated CoreDNS pods to pick up new DNS
- Deleted and recreated mylar pods to retry image pulls
- All pods successfully started with new DNS configuration

## Current Status

### Mylar Deployment
- **Status:** Running and healthy ✅
- **Pod:** `mylar-64d4b674f8-5gx86`
- **Node:** wheeljack
- **Image:** `linuxserver/mylar3:latest`
- **Memory:** 512Mi request / 2Gi limit (increased from 1Gi)

### Service Access
- **Internal:** ClusterIP `10.109.224.25:8090`
- **External:** http://mylar.home via NGINX ingress
- **Ingress IP:** 192.168.0.35
- **HTTP Status:** 303 (redirect to /home) ✅

### Application Health
- ✅ Pod is running and responsive
- ✅ HTTP endpoints working
- ✅ Successfully fetching weekly pull lists (120-139 issues)
- ✅ DNS resolution working for external APIs
- ⚠️ ComicVine API key not configured (optional)

## DNS Configuration Details

### New DNS Settings Applied

File: `/etc/systemd/resolved.conf` on all nodes

```ini
[Resolve]
DNS=1.1.1.1 1.0.0.1
FallbackDNS=8.8.8.8 8.8.4.4
```

### Verified Resolution

All nodes can now resolve:
- ✅ lscr.io
- ✅ registry-1.docker.io  
- ✅ docker.io
- ✅ walksoftly.itsaninja.party
- ✅ comicvine.gamespot.com

## Files Created/Modified

1. **Created:** `scripts/maintenance/fix-node-dns.sh`
   - Automated script to fix DNS on all Kubernetes nodes
   - Can be rerun if DNS issues occur again

2. **Backed up:** `/etc/systemd/resolved.conf.backup-*` on each node
   - Original DNS configuration saved before changes

## Testing Performed

1. **Pod Status:**
   ```bash
   kubectl get pods -n media -l app=mylar
   # NAME                     READY   STATUS    RESTARTS   AGE
   # mylar-64d4b674f8-5gx86   1/1     Running   0          57s
   ```

2. **HTTP Response:**
   ```bash
   curl -H "Host: mylar.home" http://192.168.0.35/
   # HTTP/1.1 303 See Other (working correctly)
   ```

3. **Application Logs:**
   - Successfully loading weekly pull lists
   - No DNS resolution errors
   - Normal operation resumed

## Recommendations

### Immediate
- ✅ Complete - DNS fixed on all nodes
- ✅ Complete - Mylar redeployed and operational

### Optional Improvements
1. **Configure ComicVine API Key:**
   - Get API key from http://api.comicvine.com
   - Add to mylar configuration for comic metadata

2. **Update Terraform Configuration:**
   - Current deployment uses increased memory (512Mi/2Gi)
   - Consider updating `applications-media.tf` to match

3. **Monitor Memory Usage:**
   - Previous OOMKilled incidents (1Gi limit was too low)
   - Current 2Gi limit should be sufficient

4. **DNS Persistence:**
   - DNS fix is permanent on current nodes
   - Include in VM provisioning/cloud-init for new nodes

## Access Information

- **URL:** http://mylar.home
- **Namespace:** media
- **Service:** mylar (ClusterIP)
- **Ingress:** NGINX (192.168.0.35)
- **Pod IP:** 10.244.2.28

## Commands for Future Reference

```bash
# Check mylar status
kubectl get pods -n media -l app=mylar
kubectl logs -n media -l app=mylar --tail=50

# Test connectivity
curl -H "Host: mylar.home" http://192.168.0.35/

# Restart if needed
kubectl delete pod -n media -l app=mylar

# Rerun DNS fix if issues recur
./scripts/maintenance/fix-node-dns.sh
```

## Conclusion

The DNS resolution issue has been completely resolved. All Kubernetes nodes now use reliable Cloudflare DNS servers, allowing pods to pull images from external registries and mylar to access external APIs. The application is fully operational and responding correctly to HTTP requests.

