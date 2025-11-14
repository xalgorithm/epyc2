# Rebellion Cluster - Istio Gateway API

This Pulumi project deploys Istio with Gateway API support to the Rebellion Kubernetes cluster.

## Prerequisites

- Node.js 18+ and npm
- Pulumi CLI
- Rebellion cluster running with kubeconfig at `~/.kube/configs/rebellion-config`
- MetalLB installed and configured

## Installation

```bash
# Install dependencies
npm install

# Initialize Pulumi stack (first time only)
pulumi stack init rebellion

# Deploy
pulumi up

# Destroy
pulumi destroy
```

## Components Deployed

1. **Gateway API CRDs** - Kubernetes Gateway API custom resources
2. **Istio Base** - Istio base Helm chart with CRDs
3. **Istiod** - Istio control plane
4. **Istio Ingress Gateway** - Gateway with LoadBalancer service (MetalLB)
5. **Sample Gateway** - Gateway resource for HTTP/HTTPS traffic
6. **Sample HTTPRoute** - Example route configuration

## Configuration

The kubeconfig path is set in `Pulumi.yaml`:
```yaml
config:
  kubernetes:kubeconfig:
    value: ~/.kube/configs/rebellion-config
```

## Outputs

After deployment, Pulumi will output:
- Gateway external IP
- Istio version
- Gateway API endpoints

## Usage

```bash
# View stack outputs
pulumi stack output

# Get gateway IP
pulumi stack output gatewayIP

# Update deployment
pulumi up

# View resources
pulumi stack
```

## Testing

After deployment, test the gateway:

```bash
# Get gateway IP
GATEWAY_IP=$(pulumi stack output gatewayIP)

# Test HTTP endpoint
curl -H "Host: test.example.com" http://$GATEWAY_IP/
```

## Troubleshooting

```bash
# View Istio pods
kubectl --kubeconfig ~/.kube/configs/rebellion-config get pods -n istio-system

# View gateway status
kubectl --kubeconfig ~/.kube/configs/rebellion-config get gateway -A

# View HTTPRoute status
kubectl --kubeconfig ~/.kube/configs/rebellion-config get httproute -A

# Istio logs
kubectl --kubeconfig ~/.kube/configs/rebellion-config logs -n istio-system -l app=istiod
```

