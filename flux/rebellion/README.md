# Flux GitOps - Rebellion Cluster

This directory contains Flux GitOps manifests for the Rebellion Kubernetes cluster.

## Structure

```
flux/rebellion/
├── infrastructure/         # Core infrastructure components
│   ├── sources/           # Helm repository sources
│   └── base/              # Base manifests (namespaces, etc.)
├── monitoring/            # Monitoring stack (Prometheus, Grafana, Loki)
├── apps/                  # Application deployments
└── README.md
```

## Bootstrap

To bootstrap Flux on the rebellion cluster:

```bash
./scripts/rebellion/bootstrap-flux.sh
```

## Deployment

After Flux is bootstrapped, deploy the infrastructure:

```bash
# Set kubeconfig
export KUBECONFIG=~/.kube/configs/rebellion-config

# Apply infrastructure
kubectl apply -k flux/rebellion/infrastructure/

# Apply monitoring
kubectl apply -k flux/rebellion/monitoring/

# Apply apps
kubectl apply -k flux/rebellion/apps/
```

## Monitor Flux

```bash
# Check Flux components
flux check

# View GitRepository sources
flux get sources git

# View HelmRepository sources
flux get sources helm

# View HelmReleases
flux get helmreleases -A

# View Kustomizations
flux get kustomizations

# Follow Flux logs
flux logs --follow
```

## Reconcile Manually

```bash
# Reconcile a specific source
flux reconcile source helm prometheus-community

# Reconcile a HelmRelease
flux reconcile helmrelease -n monitoring prometheus

# Reconcile all
flux reconcile kustomization --all
```

## Troubleshooting

```bash
# Check Flux system pods
kubectl get pods -n flux-system

# View controller logs
kubectl logs -n flux-system -l app=source-controller
kubectl logs -n flux-system -l app=kustomize-controller
kubectl logs -n flux-system -l app=helm-controller

# Suspend/resume reconciliation
flux suspend kustomization infrastructure
flux resume kustomization infrastructure
```

## GitOps Workflow

1. Make changes to manifests in this directory
2. Commit and push to Git repository
3. Flux automatically detects changes and applies them
4. Monitor reconciliation: `flux get kustomizations`

## Adding New Resources

### Add a Helm Repository

Create a new file in `infrastructure/sources/`:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: my-repo
  namespace: flux-system
spec:
  interval: 1h
  url: https://my-helm-repo.example.com
```

### Deploy an Application

Create a new file in `apps/`:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: my-app
  namespace: apps
spec:
  interval: 5m
  chart:
    spec:
      chart: my-chart
      sourceRef:
        kind: HelmRepository
        name: my-repo
        namespace: flux-system
      version: 1.0.0
  values:
    # Your values here
```

Then update the kustomization.yaml to include the new resource.

