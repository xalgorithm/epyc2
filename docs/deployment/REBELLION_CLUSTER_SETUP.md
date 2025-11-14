# Rebellion Kubernetes Cluster - Complete Setup Guide

This guide provides step-by-step instructions for deploying the Rebellion Kubernetes cluster using kubeadm, Istio Gateway API, and GitOps with Flux.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Phase 1: VM Deployment](#phase-1-vm-deployment)
5. [Phase 2: Kubernetes Installation](#phase-2-kubernetes-installation)
6. [Phase 3: MetalLB Load Balancer](#phase-3-metallb-load-balancer)
7. [Phase 4: Istio Gateway API](#phase-4-istio-gateway-api)
8. [Phase 5: Flux GitOps](#phase-5-flux-gitops)
9. [Phase 6: Monitoring Integration](#phase-6-monitoring-integration)
10. [Verification](#verification)
11. [Troubleshooting](#troubleshooting)

## Overview

The Rebellion cluster is a production Kubernetes cluster with the following specifications:

**Cluster Name:** rebellion

**Nodes:**
- Luke (192.168.0.40) - Control Plane
- Leia (192.168.0.41) - Worker
- Han (192.168.0.42) - Worker

**Resources per Node:**
- CPU: 4 cores
- Memory: 8GB
- Disk: 128GB

**Key Features:**
- Standard Kubernetes (kubeadm)
- Istio with Gateway API support
- MetalLB load balancer (192.168.0.43-192.168.0.49)
- Flux GitOps for declarative deployments
- Cross-cluster monitoring with main cluster

## Architecture

```
Rebellion Cluster Architecture:

Luke (Control Plane)          Leia (Worker)            Han (Worker)
192.168.0.40                  192.168.0.41             192.168.0.42
┌─────────────────┐          ┌──────────────┐         ┌──────────────┐
│   API Server    │          │  Kubelet     │         │  Kubelet     │
│   etcd          │◄────────►│  Pods        │◄───────►│  Pods        │
│   Controller    │          │  node-export │         │  node-export │
│   Scheduler     │          └──────────────┘         └──────────────┘
└─────────────────┘
        │
        ▼
┌─────────────────────────────────────────┐
│          MetalLB (L2)                   │
│      IP Pool: 192.168.0.43-.49          │
└─────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────┐
│       Istio Gateway API                 │
│    (LoadBalancer via MetalLB)           │
└─────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────┐
│         Application Pods                │
│   (Managed by Flux GitOps)              │
└─────────────────────────────────────────┘
```

## Prerequisites

- Proxmox host with API access
- Ubuntu 22.04 template (VM ID 9000)
- SSH key at `~/.ssh/id_ed25519`
- Terraform installed
- kubectl installed
- Node.js 18+ and npm (for Pulumi)
- Pulumi CLI

## Phase 1: VM Deployment

### 1.1 Deploy VMs with Terraform

```bash
cd /Users/xalg/dev/terraform/epyc2

# Initialize Terraform (if not already done)
terraform init

# Deploy the three VMs
terraform apply \
  -target=proxmox_virtual_environment_vm.luke \
  -target=proxmox_virtual_environment_vm.leia \
  -target=proxmox_virtual_environment_vm.han
```

### 1.2 Verify VM Deployment

```bash
# Check VM status in Proxmox
ssh root@192.168.0.7 "qm list | grep -E 'luke|leia|han'"

# Test SSH connectivity
ssh xalg@192.168.0.40 "hostname"  # luke
ssh xalg@192.168.0.41 "hostname"  # leia
ssh xalg@192.168.0.42 "hostname"  # han
```

### 1.3 Run Automated Tests

```bash
./scripts/deployment/test-rebellion-vms.sh
```

This will verify:
- SSH connectivity
- Required packages installed (git, nfs-common, openssh-server)
- Disk space (128GB)
- CPU count (4 cores)
- Memory (8GB)
- Network connectivity between nodes

## Phase 2: Kubernetes Installation

### 2.1 Install Kubernetes Components

```bash
# Install containerd, kubeadm, kubelet, kubectl on all nodes
./scripts/rebellion/install-kubernetes.sh
```

This script:
- Installs containerd runtime
- Configures kernel modules and sysctl parameters
- Installs Kubernetes 1.31
- Disables swap
- Enables kubelet service

### 2.2 Bootstrap Control Plane

```bash
# Initialize kubeadm on Luke and install Calico CNI
./scripts/rebellion/bootstrap-control-plane.sh
```

This script:
- Initializes kubeadm on Luke
- Installs Calico CNI
- Copies kubeconfig to `~/.kube/configs/rebellion-config`
- Generates join command for workers

### 2.3 Join Worker Nodes

```bash
# Join Leia and Han to the cluster
./scripts/rebellion/join-workers.sh
```

This script:
- Joins worker nodes using the generated token
- Labels nodes appropriately
- Verifies all nodes are Ready

### 2.4 Verify Cluster

```bash
export KUBECONFIG=~/.kube/configs/rebellion-config

# Check nodes
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system

# Check Calico
kubectl get pods -n calico-system
```

## Phase 3: MetalLB Load Balancer

### 3.1 Deploy MetalLB with Terraform

```bash
terraform apply \
  -target=helm_release.rebellion_metallb \
  -target=kubernetes_manifest.rebellion_metallb_ippool \
  -target=kubernetes_manifest.rebellion_metallb_l2_advertisement
```

### 3.2 Verify MetalLB

```bash
export KUBECONFIG=~/.kube/configs/rebellion-config

# Check MetalLB pods
kubectl get pods -n metallb-system

# Check IPAddressPool
kubectl get ipaddresspool -n metallb-system

# Check L2Advertisement
kubectl get l2advertisement -n metallb-system
```

## Phase 4: Istio Gateway API

### 4.1 Deploy Istio with Pulumi

```bash
./scripts/rebellion/deploy-istio-gateway.sh
```

This script:
- Installs Gateway API CRDs
- Deploys Istio base (CRDs and cluster roles)
- Deploys Istiod (control plane)
- Deploys Istio Ingress Gateway with LoadBalancer
- Creates sample Gateway and HTTPRoute

### 4.2 Get Gateway IP

```bash
cd pulumi/rebellion-cluster
pulumi stack output gatewayIP
```

### 4.3 Test Gateway

```bash
# Get the gateway IP
GATEWAY_IP=$(pulumi stack output gatewayIP)

# Test the demo application
curl -H "Host: httpbin.rebellion.local" http://$GATEWAY_IP/

# Or add to /etc/hosts
echo "$GATEWAY_IP httpbin.rebellion.local" | sudo tee -a /etc/hosts

# Then visit in browser
open http://httpbin.rebellion.local/
```

### 4.4 Verify Istio

```bash
export KUBECONFIG=~/.kube/configs/rebellion-config

# Check Istio pods
kubectl get pods -n istio-system

# Check ingress gateway
kubectl get pods -n istio-ingress

# Check Gateway resources
kubectl get gateway -A

# Check HTTPRoutes
kubectl get httproute -A
```

## Phase 5: Flux GitOps

### 5.1 Bootstrap Flux

```bash
./scripts/rebellion/bootstrap-flux.sh
```

Follow the prompts to:
- Install Flux CLI (if needed)
- Configure Git repository (optional)
- Bootstrap Flux to the cluster

### 5.2 Deploy Infrastructure Components

```bash
export KUBECONFIG=~/.kube/configs/rebellion-config

# Apply infrastructure (Helm repos, namespaces)
kubectl apply -k flux/rebellion/infrastructure/

# Apply monitoring stack
kubectl apply -k flux/rebellion/monitoring/
```

### 5.3 Verify Flux

```bash
# Check Flux components
flux check

# View sources
flux get sources helm

# View Kustomizations
flux get kustomizations

# Follow logs
flux logs --follow
```

## Phase 6: Monitoring Integration

### 6.1 Deploy Node Exporters

Node exporters are deployed via Flux:

```bash
export KUBECONFIG=~/.kube/configs/rebellion-config

kubectl get pods -n monitoring -l app=node-exporter
```

### 6.2 Deploy Prometheus

Prometheus is deployed via Flux and configured to:
- Scrape node exporters on all nodes
- Scrape Kubernetes pods with annotations
- Remote write to main cluster Mimir

```bash
kubectl get pods -n monitoring -l app=prometheus
```

### 6.3 Deploy Promtail

Promtail ships logs to the main cluster's Loki:

```bash
kubectl get pods -n monitoring -l app=promtail
```

### 6.4 Access Grafana Dashboards

The rebellion dashboards are added to the main cluster's Grafana:

1. Open Grafana: http://grafana.home
2. Navigate to Dashboards
3. Find "Rebellion Cluster Overview"
4. Find "Rebellion Istio Gateway Metrics"

## Verification

### End-to-End Verification

```bash
# 1. Check all nodes are Ready
export KUBECONFIG=~/.kube/configs/rebellion-config
kubectl get nodes

# 2. Check all system pods are Running
kubectl get pods -A

# 3. Check MetalLB IP pool
kubectl get ipaddresspool -n metallb-system

# 4. Check Istio Gateway has external IP
kubectl get svc -n istio-ingress

# 5. Test Gateway
GATEWAY_IP=$(kubectl get svc -n istio-ingress istio-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -H "Host: httpbin.rebellion.local" http://$GATEWAY_IP/

# 6. Check Flux reconciliation
flux get kustomizations

# 7. Check monitoring
kubectl get pods -n monitoring
```

## Troubleshooting

### VMs Not Accessible

```bash
# Check VM status in Proxmox
ssh root@192.168.0.7 "qm list"

# Check cloud-init logs
ssh xalg@192.168.0.40 "sudo cat /var/log/cloud-init-output.log"
```

### Cluster Not Forming

```bash
# Check kubelet logs on control plane
ssh xalg@192.168.0.40 "sudo journalctl -u kubelet -f"

# Check API server logs
ssh xalg@192.168.0.40 "sudo crictl logs <container-id>"

# Reset and reinitialize (if needed)
ssh xalg@192.168.0.40 "sudo kubeadm reset -f"
./scripts/rebellion/bootstrap-control-plane.sh
```

### MetalLB Not Assigning IPs

```bash
# Check MetalLB controller logs
kubectl logs -n metallb-system -l app=metallb,component=controller

# Check IPAddressPool
kubectl describe ipaddresspool -n metallb-system rebellion-pool

# Verify L2Advertisement
kubectl get l2advertisement -n metallb-system
```

### Istio Gateway Not Working

```bash
# Check Istiod logs
kubectl logs -n istio-system -l app=istiod

# Check gateway pods
kubectl logs -n istio-ingress -l app=istio-gateway

# Check Gateway status
kubectl describe gateway -n istio-ingress rebellion-gateway

# Check HTTPRoute status
kubectl describe httproute -A
```

### Flux Not Reconciling

```bash
# Check Flux system pods
kubectl get pods -n flux-system

# Check source controller logs
kubectl logs -n flux-system -l app=source-controller

# Suspend/resume reconciliation
flux suspend kustomization infrastructure
flux resume kustomization infrastructure

# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization infrastructure
```

### Monitoring Not Working

```bash
# Check Prometheus
kubectl logs -n monitoring -l app=prometheus

# Check node-exporter on nodes
kubectl logs -n monitoring -l app=node-exporter

# Check Promtail
kubectl logs -n monitoring -l app=promtail

# Test Prometheus scraping
kubectl port-forward -n monitoring svc/prometheus-rebellion 9090:9090
# Open http://localhost:9090/targets
```

## Next Steps

After successful deployment:

1. **Deploy Applications**: Create HTTPRoutes for your applications
2. **Configure Monitoring**: Add custom Prometheus scrape configs
3. **Set up Alerting**: Configure Alertmanager rules
4. **Backup Configuration**: Set up etcd backups
5. **Security Hardening**: Implement NetworkPolicies and PodSecurityPolicies

## References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Istio Gateway API](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/)
- [Flux Documentation](https://fluxcd.io/docs/)
- [MetalLB Documentation](https://metallb.universe.tf/)
- [Calico Documentation](https://docs.tigera.io/calico/latest/about/)

## Support

For issues or questions:
- Check the troubleshooting section above
- Review Kubernetes and Istio logs
- Consult the main project documentation

