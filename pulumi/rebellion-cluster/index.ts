import * as pulumi from "@pulumi/pulumi";
import * as k8s from "@pulumi/kubernetes";
import * as path from "path";

// Get configuration
const config = new pulumi.Config();
const kubeconfigPath = config.get("kubernetes:kubeconfig") || "~/.kube/configs/rebellion-config";

// Create Kubernetes provider for rebellion cluster
const provider = new k8s.Provider("rebellion", {
    kubeconfig: kubeconfigPath.replace("~", process.env.HOME || ""),
});

// =============================================================================
// Gateway API CRDs
// =============================================================================

// Install Gateway API CRDs
const gatewayAPICRDs = new k8s.yaml.ConfigFile("gateway-api-crds", {
    file: "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml",
}, { provider });

// =============================================================================
// Istio Installation
// =============================================================================

// Create istio-system namespace
const istioNamespace = new k8s.core.v1.Namespace("istio-system", {
    metadata: {
        name: "istio-system",
        labels: {
            "istio-injection": "disabled",
        },
    },
}, { provider });

// Install Istio base (CRDs and cluster roles)
const istioBase = new k8s.helm.v3.Release("istio-base", {
    chart: "base",
    version: "1.21.0",
    namespace: istioNamespace.metadata.name,
    repositoryOpts: {
        repo: "https://istio-release.storage.googleapis.com/charts",
    },
    values: {
        defaultRevision: "default",
    },
}, { provider, dependsOn: [gatewayAPICRDs] });

// Install Istiod (control plane)
const istiod = new k8s.helm.v3.Release("istiod", {
    chart: "istiod",
    version: "1.21.0",
    namespace: istioNamespace.metadata.name,
    repositoryOpts: {
        repo: "https://istio-release.storage.googleapis.com/charts",
    },
    values: {
        pilot: {
            env: {
                // Enable Gateway API support
                PILOT_ENABLE_GATEWAY_API: "true",
                PILOT_ENABLE_GATEWAY_API_STATUS: "true",
            },
        },
        meshConfig: {
            accessLogFile: "/dev/stdout",
            enablePrometheusMerge: true,
        },
        global: {
            proxy: {
                resources: {
                    requests: {
                        cpu: "100m",
                        memory: "128Mi",
                    },
                    limits: {
                        cpu: "2000m",
                        memory: "1024Mi",
                    },
                },
            },
        },
    },
}, { provider, dependsOn: [istioBase] });

// Create istio-ingress namespace
const istioIngressNamespace = new k8s.core.v1.Namespace("istio-ingress", {
    metadata: {
        name: "istio-ingress",
        labels: {
            "istio-injection": "enabled",
        },
    },
}, { provider, dependsOn: [istiod] });

// Install Istio Ingress Gateway with minimal configuration
const istioGateway = new k8s.helm.v3.Release("istio-gateway", {
    chart: "gateway",
    version: "1.21.0",
    namespace: istioIngressNamespace.metadata.name,
    repositoryOpts: {
        repo: "https://istio-release.storage.googleapis.com/charts",
    },
    // Use empty values - the chart will use defaults
    values: {},
}, { provider, dependsOn: [istioIngressNamespace] });

// Create LoadBalancer Service for the gateway
// The default gateway chart creates a Deployment with app=istio-gateway label
const gatewayService = new k8s.core.v1.Service("istio-gateway-lb", {
    metadata: {
        name: "istio-gateway-lb",
        namespace: istioIngressNamespace.metadata.name,
        annotations: {
            "metallb.universe.tf/allow-shared-ip": "istio-gateway",
        },
    },
    spec: {
        type: "LoadBalancer",
        selector: {
            "app": "istio-gateway",  // Match default chart label
        },
        ports: [
            {
                name: "http",
                port: 80,
                targetPort: 8080,
                protocol: "TCP",
            },
            {
                name: "https",
                port: 443,
                targetPort: 8443,
                protocol: "TCP",
            },
        ],
    },
}, { provider, dependsOn: [istioGateway] });

// =============================================================================
// Gateway API Resources
// =============================================================================

// Create Gateway resource
const gateway = new k8s.apiextensions.CustomResource("rebellion-gateway", {
    apiVersion: "gateway.networking.k8s.io/v1",
    kind: "Gateway",
    metadata: {
        name: "rebellion-gateway",
        namespace: istioIngressNamespace.metadata.name,
    },
    spec: {
        gatewayClassName: "istio",
        listeners: [
            {
                name: "http",
                protocol: "HTTP",
                port: 80,
                allowedRoutes: {
                    namespaces: {
                        from: "All",
                    },
                },
            },
            {
                name: "https",
                protocol: "HTTPS",
                port: 443,
                allowedRoutes: {
                    namespaces: {
                        from: "All",
                    },
                },
                tls: {
                    mode: "Terminate",
                    certificateRefs: [
                        {
                            name: "gateway-cert",
                            kind: "Secret",
                        },
                    ],
                },
            },
        ],
    },
}, { provider, dependsOn: [istioGateway, gatewayAPICRDs] });

// =============================================================================
// Example Application and HTTPRoute
// =============================================================================

// Create demo namespace
const demoNamespace = new k8s.core.v1.Namespace("demo", {
    metadata: {
        name: "demo",
        labels: {
            "istio-injection": "enabled",
        },
    },
}, { provider });

// Deploy sample application (httpbin)
const httpbinDeployment = new k8s.apps.v1.Deployment("httpbin", {
    metadata: {
        name: "httpbin",
        namespace: demoNamespace.metadata.name,
    },
    spec: {
        replicas: 2,
        selector: {
            matchLabels: {
                app: "httpbin",
                version: "v1",
            },
        },
        template: {
            metadata: {
                labels: {
                    app: "httpbin",
                    version: "v1",
                },
            },
            spec: {
                containers: [
                    {
                        name: "httpbin",
                        image: "kennethreitz/httpbin:latest",
                        ports: [
                            {
                                containerPort: 80,
                            },
                        ],
                        resources: {
                            requests: {
                                cpu: "50m",
                                memory: "64Mi",
                            },
                            limits: {
                                cpu: "500m",
                                memory: "256Mi",
                            },
                        },
                    },
                ],
            },
        },
    },
}, { provider, dependsOn: [demoNamespace] });

// Create service for httpbin
const httpbinService = new k8s.core.v1.Service("httpbin-service", {
    metadata: {
        name: "httpbin",
        namespace: demoNamespace.metadata.name,
        labels: {
            app: "httpbin",
        },
    },
    spec: {
        ports: [
            {
                name: "http",
                port: 8000,
                targetPort: 80,
            },
        ],
        selector: {
            app: "httpbin",
        },
    },
}, { provider, dependsOn: [httpbinDeployment] });

// Create HTTPRoute for the sample app
const httpRoute = new k8s.apiextensions.CustomResource("httpbin-route", {
    apiVersion: "gateway.networking.k8s.io/v1",
    kind: "HTTPRoute",
    metadata: {
        name: "httpbin",
        namespace: demoNamespace.metadata.name,
    },
    spec: {
        parentRefs: [
            {
                name: "rebellion-gateway",
                namespace: istioIngressNamespace.metadata.name,
            },
        ],
        hostnames: ["httpbin.rebellion.local"],
        rules: [
            {
                matches: [
                    {
                        path: {
                            type: "PathPrefix",
                            value: "/",
                        },
                    },
                ],
                backendRefs: [
                    {
                        name: httpbinService.metadata.name,
                        port: 8000,
                    },
                ],
            },
        ],
    },
}, { provider, dependsOn: [gateway, httpbinService, gatewayAPICRDs] });

// =============================================================================
// Outputs
// =============================================================================

// Export gateway external IP
export const gatewayIP = gatewayService.status.loadBalancer.ingress.apply(ingress => 
    ingress?.[0]?.ip || "pending"
);

export const gatewayName = gateway.metadata.name;
export const gatewayNamespace = istioIngressNamespace.metadata.name;

export const istioVersion = "1.21.0";

export const testCommand = pulumi.interpolate`curl -H "Host: httpbin.rebellion.local" http://${gatewayIP}/`;

export const dashboardCommands = {
    kiali: `kubectl port-forward -n istio-system svc/kiali 20001:20001`,
    grafana: `kubectl port-forward -n istio-system svc/grafana 3000:3000`,
    jaeger: `kubectl port-forward -n istio-system svc/tracing 16686:16686`,
};

export const info = pulumi.interpolate`
Istio Gateway API deployed successfully!

Gateway IP: ${gatewayIP}
Gateway Name: ${gatewayName}
Gateway Namespace: ${gatewayNamespace}

Test the demo application:
  ${testCommand}

Or add to /etc/hosts:
  ${gatewayIP} httpbin.rebellion.local

Then visit: http://httpbin.rebellion.local/

View Gateway status:
  kubectl --kubeconfig ${kubeconfigPath} get gateway -n ${gatewayNamespace}

View HTTPRoutes:
  kubectl --kubeconfig ${kubeconfigPath} get httproute -A

View Istio pods:
  kubectl --kubeconfig ${kubeconfigPath} get pods -n istio-system
`;

