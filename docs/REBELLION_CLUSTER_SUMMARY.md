# Rebellion Kubernetes Cluster - Quick Reference

## Cluster Information

| Property | Value |
|----------|-------|
| **Cluster Name** | rebellion |
| **Kubernetes Version** | 1.31 |
| **Distribution** | kubeadm (standard Kubernetes) |
| **CNI** | Calico |
| **Ingress** | Istio Gateway API |
| **Load Balancer** | MetalLB (L2) |
| **GitOps** | Flux v2 |

## Node Information

| Node | IP | Role | CPU | Memory | Disk | VM ID |
|------|-----|------|-----|--------|------|-------|
| **Luke** | 192.168.0.40 | Control Plane | 4 cores | 8GB | 128GB | 120 |
| **Leia** | 192.168.0.41 | Worker | 4 cores | 8GB | 128GB | 121 |
| **Han** | 192.168.0.42 | Worker | 4 cores | 8GB | 128GB | 122 |

## Network Configuration

| Component | Value |
|-----------|-------|
| **Pod CIDR** | 10.244.0.0/16 |
| **Service CIDR** | 10.96.0.0/12 |
| **MetalLB Pool** | 192.168.0.43 - 192.168.0.49 |
| **Gateway** | 192.168.0.1 |

## Quick Start Commands

### Access the Cluster

```bash
# Set kubeconfig
export KUBECONFIG=~/.kube/configs/rebellion-config

# Check nodes
kubectl get nodes

# Check all pods
kubectl get pods -A
```

### Deployment Commands

```bash
# Deploy VMs
terraform apply \
  -target=proxmox_virtual_environment_vm.luke \
  -target=proxmox_virtual_environment_vm.leia \
  -target=proxmox_virtual_environment_vm.han

# Install Kubernetes
./scripts/rebellion/install-kubernetes.sh
./scripts/rebellion/bootstrap-control-plane.sh
./scripts/rebellion/join-workers.sh

# Deploy MetalLB
terraform apply -target=helm_release.rebellion_metallb

# Deploy Istio Gateway API
./scripts/rebellion/deploy-istio-gateway.sh

# Bootstrap Flux
./scripts/rebellion/bootstrap-flux.sh
```

## Component Access

### Kubernetes Dashboard

```bash
# Port-forward (if dashboard is installed)
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443
```

### Prometheus

```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-rebellion 9090:9090
# Access: http://localhost:9090
```

### Grafana (Main Cluster)

```
URL: http://grafana.home
Username: admin
Password: admin

Dashboards:
  - Rebellion Cluster Overview
  - Rebellion Istio Gateway Metrics
```

### Istio Gateway

```bash
# Get gateway IP
export KUBECONFIG=~/.kube/configs/rebellion-config
GATEWAY_IP=$(kubectl get svc -n istio-ingress istio-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $GATEWAY_IP

# Test with httpbin demo
curl -H "Host: httpbin.rebellion.local" http://$GATEWAY_IP/
```

## File Locations

### Terraform Files

```
infrastructure-rebellion.tf           - VM definitions
kubernetes-rebellion-cluster.tf       - Cluster bootstrap orchestration
kubernetes-rebellion-metallb.tf       - MetalLB deployment
kubernetes-rebellion-monitoring.tf    - Monitoring integration
terraform.tfvars                      - Configuration values
```

### Scripts

```
scripts/deployment/
  ├── deploy-rebellion-vms.sh        - Deploy all VMs
  └── test-rebellion-vms.sh          - Test VM deployment

scripts/rebellion/
  ├── install-kubernetes.sh          - Install Kubernetes on all nodes
  ├── bootstrap-control-plane.sh     - Initialize control plane
  ├── join-workers.sh                - Join worker nodes
  ├── deploy-istio-gateway.sh        - Deploy Istio with Pulumi
  └── bootstrap-flux.sh              - Bootstrap Flux GitOps
```

### Configuration Files

```
configs/
  ├── prometheus/prometheus-rebellion.yml  - Prometheus config
  └── grafana/
      ├── rebellion-cluster-dashboard.json
      └── rebellion-istio-dashboard.json

flux/rebellion/
  ├── infrastructure/                - Base infrastructure manifests
  ├── monitoring/                    - Monitoring stack
  └── apps/                          - Application deployments

pulumi/rebellion-cluster/
  ├── index.ts                       - Istio Gateway API deployment
  ├── package.json                   - Node dependencies
  └── Pulumi.yaml                    - Pulumi configuration
```

### Documentation

```
docs/
  ├── deployment/REBELLION_CLUSTER_SETUP.md  - Complete setup guide
  └── monitoring/REBELLION_MONITORING.md     - Monitoring architecture

REBELLION_CLUSTER_SUMMARY.md                 - This file
```

## Common Operations

### Cluster Management

```bash
# Check cluster health
export KUBECONFIG=~/.kube/configs/rebellion-config
kubectl get componentstatuses
kubectl get nodes
kubectl get pods -A

# Drain a node for maintenance
kubectl drain han --ignore-daemonsets --delete-emptydir-data

# Uncordon node
kubectl uncordon han
```

### Application Deployment

```bash
# Create an HTTPRoute
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: apps
spec:
  parentRefs:
    - name: rebellion-gateway
      namespace: istio-ingress
  hostnames:
    - myapp.rebellion.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-service
          port: 80
EOF
```

### Monitoring

```bash
# Check node metrics
kubectl top nodes

# Check pod metrics
kubectl top pods -A

# View Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-rebellion 9090:9090
# Open http://localhost:9090/targets

# Check logs in Loki (via Grafana)
# URL: http://grafana.home/explore
# Query: {cluster="rebellion"}
```

### Flux Operations

```bash
# Check Flux status
flux check

# View sources
flux get sources git
flux get sources helm

# View HelmReleases
flux get helmreleases -A

# Reconcile manually
flux reconcile source git flux-system
flux reconcile kustomization infrastructure

# Suspend/resume
flux suspend kustomization apps
flux resume kustomization apps
```

## Troubleshooting

### Node Issues

```bash
# Check node logs
ssh xalg@192.168.0.40 "sudo journalctl -u kubelet -f"

# Check containerd
ssh xalg@192.168.0.40 "sudo systemctl status containerd"

# Restart kubelet
ssh xalg@192.168.0.40 "sudo systemctl restart kubelet"
```

### Pod Issues

```bash
# Describe pod
kubectl describe pod <pod-name> -n <namespace>

# View logs
kubectl logs <pod-name> -n <namespace>

# Get events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### MetalLB Issues

```bash
# Check MetalLB logs
kubectl logs -n metallb-system -l app=metallb,component=controller

# Check IP pool
kubectl describe ipaddresspool -n metallb-system rebellion-pool

# Check service
kubectl get svc -A | grep LoadBalancer
```

### Istio Issues

```bash
# Check Istiod logs
kubectl logs -n istio-system -l app=istiod

# Check gateway logs
kubectl logs -n istio-ingress -l app=istio-gateway

# Check Gateway status
kubectl describe gateway -n istio-ingress rebellion-gateway

# Analyze configuration
istioctl analyze -n istio-ingress
```

## Backup and Recovery

### Backup etcd

```bash
# SSH to control plane
ssh xalg@192.168.0.40

# Backup etcd
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-backup.db

# Copy backup
scp xalg@192.168.0.40:/tmp/etcd-backup.db ./
```

### Backup kubeconfig

```bash
cp ~/.kube/configs/rebellion-config ~/.kube/configs/rebellion-config.backup
```

### Restore from Backup

See [Kubernetes etcd restore documentation](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#restoring-an-etcd-cluster)

## Monitoring Endpoints

| Component | Endpoint | Port |
|-----------|----------|------|
| **Node Exporter (Luke)** | 192.168.0.40:9100 | 9100 |
| **Node Exporter (Leia)** | 192.168.0.41:9100 | 9100 |
| **Node Exporter (Han)** | 192.168.0.42:9100 | 9100 |
| **Prometheus** | prometheus-rebellion.monitoring.svc | 9090 |
| **Istio Gateway** | LoadBalancer IP | 80, 443 |

## Useful Queries

### PromQL

```promql
# CPU usage by node
100 - (avg by (instance) (irate(node_cpu_seconds_total{cluster="rebellion",mode="idle"}[5m])) * 100)

# Memory usage by node
100 - ((node_memory_MemAvailable_bytes{cluster="rebellion"} / node_memory_MemTotal_bytes{cluster="rebellion"}) * 100)

# Pod count
count(kube_pod_info{cluster="rebellion"})

# Istio request rate
sum(rate(istio_requests_total{cluster="rebellion"}[5m]))
```

### LogQL

```logql
# All rebellion logs
{cluster="rebellion"}

# Errors
{cluster="rebellion"} |= "error"

# Istio logs
{cluster="rebellion",namespace="istio-system"}

# Specific pod
{cluster="rebellion",pod="my-pod-name"}
```

## Resource Limits

### Default Resource Quotas

No default quotas are set. Consider adding ResourceQuotas for namespaces:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: apps
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
```

## Security Considerations

1. **Network Policies**: Not configured by default - consider implementing
2. **Pod Security**: Enforce PodSecurityStandards
3. **RBAC**: Review and restrict service account permissions
4. **Secrets**: Use external secrets management (e.g., Sealed Secrets)
5. **Istio mTLS**: Enable strict mTLS for service-to-service communication

## Upgrading

### Kubernetes Upgrade

```bash
# Upgrade control plane
ssh xalg@192.168.0.40
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt update && sudo apt install -y kubeadm=1.32.x-00
sudo kubeadm upgrade apply v1.32.x
sudo apt install -y kubelet=1.32.x-00 kubectl=1.32.x-00
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Upgrade workers
ssh xalg@192.168.0.41
sudo apt-mark unhold kubeadm kubelet
sudo apt update && sudo apt install -y kubeadm=1.32.x-00 kubelet=1.32.x-00
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

### Istio Upgrade

```bash
cd pulumi/rebellion-cluster
# Edit index.ts and update version
pulumi up
```

## Performance Tuning

### Node Performance

```bash
# Increase file descriptors
echo "fs.file-max = 2097152" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Optimize network
echo "net.core.somaxconn = 32768" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Kubernetes Performance

```yaml
# Increase API server request limits
# Edit /etc/kubernetes/manifests/kube-apiserver.yaml
--max-requests-inflight=400
--max-mutating-requests-inflight=200
```

## Support and References

- **Documentation**: `docs/deployment/REBELLION_CLUSTER_SETUP.md`
- **Monitoring Guide**: `docs/monitoring/REBELLION_MONITORING.md`
- **Kubernetes Docs**: https://kubernetes.io/docs/
- **Istio Docs**: https://istio.io/latest/docs/
- **Flux Docs**: https://fluxcd.io/docs/

---

**Last Updated**: 2025-11-14  
**Cluster Version**: rebellion v1.0
**Kubernetes**: 1.31
**Istio**: 1.21.0

