#!/bin/bash

set -e

echo "🔧 Fix Kubeconfig Secret Encoding"
echo "================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not available"
    exit 1
fi

# Check if backup namespace exists
if ! kubectl get namespace backup >/dev/null 2>&1; then
    log_error "Backup namespace not found"
    exit 1
fi

# Check if backup-kubeconfig secret exists
if ! kubectl get secret backup-kubeconfig -n backup >/dev/null 2>&1; then
    log_error "backup-kubeconfig secret not found"
    log_info "Run 'terraform apply' to create it"
    exit 1
fi

log_info "Checking current kubeconfig secret..."

# Get the current secret data
CURRENT_CONFIG=$(kubectl get secret backup-kubeconfig -n backup -o jsonpath='{.data.config}' | base64 -d)

# Check if it's double-encoded (starts with base64 encoded data)
if echo "$CURRENT_CONFIG" | head -1 | grep -q "^[A-Za-z0-9+/]*={0,2}$"; then
    log_warning "Kubeconfig appears to be double-encoded (base64 inside base64)"
    
    # Try to decode it again
    DECODED_CONFIG=$(echo "$CURRENT_CONFIG" | base64 -d 2>/dev/null || echo "")
    
    if [ -n "$DECODED_CONFIG" ] && echo "$DECODED_CONFIG" | grep -q "apiVersion"; then
        log_info "Successfully decoded double-encoded kubeconfig"
        
        read -p "Do you want to fix the kubeconfig secret? (y/N): " -n 1 -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Creating corrected kubeconfig secret..."
            
            # Create a temporary file with the correct kubeconfig
            TEMP_CONFIG=$(mktemp)
            echo "$DECODED_CONFIG" > "$TEMP_CONFIG"
            
            # Delete the old secret
            kubectl delete secret backup-kubeconfig -n backup
            
            # Create new secret with correct encoding
            kubectl create secret generic backup-kubeconfig -n backup --from-file=config="$TEMP_CONFIG"
            
            # Clean up
            rm -f "$TEMP_CONFIG"
            
            log_success "Kubeconfig secret fixed!"
        else
            log_info "Skipping fix"
        fi
    else
        log_error "Could not decode the kubeconfig properly"
    fi
elif echo "$CURRENT_CONFIG" | grep -q "apiVersion"; then
    log_success "Kubeconfig secret appears to be correctly encoded"
    
    # Validate the kubeconfig
    TEMP_CONFIG=$(mktemp)
    echo "$CURRENT_CONFIG" > "$TEMP_CONFIG"
    
    if kubectl --kubeconfig="$TEMP_CONFIG" cluster-info >/dev/null 2>&1; then
        log_success "Kubeconfig is valid and can connect to cluster"
    else
        log_warning "Kubeconfig is formatted correctly but cannot connect to cluster"
        log_info "This might be due to network access or authentication issues"
    fi
    
    rm -f "$TEMP_CONFIG"
else
    log_error "Kubeconfig secret contains invalid data"
    log_info "First few lines of config:"
    echo "$CURRENT_CONFIG" | head -5
fi

# Test the secret in a pod
log_info "Testing kubeconfig secret in a pod..."

# Create a test job
JOB_NAME="test-kubeconfig-$(date +%s)"

cat > /tmp/${JOB_NAME}.yaml << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: backup
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      serviceAccountName: backup
      restartPolicy: Never
      containers:
      - name: test-kubeconfig
        image: bitnami/kubectl:latest
        command: ["/bin/bash"]
        args: ["-c", "echo 'Testing kubeconfig...' && ls -la /root/.kube/ && echo 'Config file content type:' && file /root/.kube/config && echo 'First few lines:' && head -5 /root/.kube/config && echo 'Testing kubectl...' && kubectl version --client && kubectl cluster-info"]
        env:
        - name: KUBECONFIG
          value: "/root/.kube/config"
        volumeMounts:
        - name: kubectl-config
          mountPath: /root/.kube
          readOnly: true
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
      volumes:
      - name: kubectl-config
        secret:
          secretName: backup-kubeconfig
EOF

# Apply the job
kubectl apply -f /tmp/${JOB_NAME}.yaml

# Wait for job to complete
log_info "Waiting for test job to complete..."
kubectl wait --for=condition=complete job/${JOB_NAME} -n backup --timeout=60s || log_warning "Job may still be running"

# Get pod name and show logs
POD_NAME=$(kubectl get pods -n backup -l job-name=${JOB_NAME} -o jsonpath='{.items[0].metadata.name}')

if [ -n "$POD_NAME" ]; then
    log_info "Test job logs:"
    echo "=================================================================="
    kubectl logs ${POD_NAME} -n backup
    echo "=================================================================="
else
    log_error "Could not find test job pod"
fi

# Cleanup
kubectl delete job ${JOB_NAME} -n backup
rm -f /tmp/${JOB_NAME}.yaml

echo ""
log_info "Kubeconfig secret test completed"
echo ""
log_info "If the test showed kubectl errors, the secret needs to be fixed."
log_info "You can fix it by:"
echo "  1. Running this script again and choosing to fix it"
echo "  2. Or running: terraform apply (to recreate with correct encoding)"