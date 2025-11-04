#!/bin/bash

set -e

echo "🔄 Manual Backup Trigger Script"
echo "==============================="

# Configuration
BACKUP_TYPE=${1:-"all"}
BACKUP_LOCATION=${2:-"/tmp/k8s-manual-backup"}

# Get NFS server IP from terraform.tfvars
NFS_SERVER_IP=$(grep nfs_server_ip terraform.tfvars 2>/dev/null | cut -d '"' -f 2 || echo "192.168.1.100")

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

show_usage() {
    echo "Usage: $0 [BACKUP_TYPE] [BACKUP_LOCATION]"
    echo ""
    echo "This script triggers a manual backup by running the comprehensive backup script"
    echo "inside a Kubernetes pod with access to all cluster resources and applications."
    echo ""
    echo "BACKUP_TYPE options:"
    echo "  all         - Backup everything (default)"
    echo "  etcd        - Backup only ETCD"
    echo "  resources   - Backup only Kubernetes resources"
    echo "  apps        - Backup only application data"

    echo "  grafana     - Backup only Grafana"
    echo "  prometheus  - Backup only Prometheus"
    echo "  loki        - Backup only Loki"
    echo "  mimir       - Backup only Mimir"
    echo ""
    echo "BACKUP_LOCATION: Where to store the backup (default: /tmp/k8s-manual-backup)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Full backup to default location"
    echo "  $0 all /backup                       # Full backup to /backup"
    echo "  $0 apps                              # Only application data"
    echo "  $0 grafana /home/user/grafana-backup # Only Grafana to custom location"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}⚠️  kubectl is not available. Please ensure kubeconfig is set up.${NC}"
    exit 1
fi

# Check if backup namespace exists
if ! kubectl get namespace backup >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Backup namespace not found. Please deploy the backup system first.${NC}"
    exit 1
fi

# Handle help
if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

echo -e "${BLUE}ℹ️  Backup type: ${BACKUP_TYPE}${NC}"
echo -e "${BLUE}ℹ️  Backup location: ${BACKUP_LOCATION}${NC}"
echo ""

# Create a manual backup job
JOB_NAME="manual-backup-$(date +%s)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo -e "${BLUE}ℹ️  Creating manual backup job: ${JOB_NAME}${NC}"

# Create the job YAML
cat > /tmp/${JOB_NAME}.yaml << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: backup
  labels:
    app: manual-backup
    backup-type: ${BACKUP_TYPE}
spec:
  ttlSecondsAfterFinished: 3600  # Clean up after 1 hour
  template:
    metadata:
      labels:
        app: manual-backup
    spec:
      serviceAccountName: backup
      restartPolicy: Never
      containers:
      - name: manual-backup
        image: bitnami/kubectl:latest
        command: ["/bin/bash"]
        args: ["/scripts/manual-backup-comprehensive.sh", "${BACKUP_TYPE}", "/backup"]
        env:
        - name: BACKUP_TYPE
          value: "${BACKUP_TYPE}"
        - name: BACKUP_LOCATION
          value: "${BACKUP_LOCATION}"
        - name: KUBECONFIG
          value: "/root/.kube/config"
        volumeMounts:
        - name: backup-scripts
          mountPath: /scripts
        - name: backup-storage
          mountPath: /backup
        - name: kubectl-config
          mountPath: /root/.kube
          readOnly: true
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
      volumes:
      - name: backup-scripts
        configMap:
          name: backup-scripts
          defaultMode: 0755
      - name: backup-storage
        nfs:
          server: "${NFS_SERVER_IP}"
          path: "/data/kubernetes/backups"
      - name: kubectl-config
        secret:
          secretName: backup-kubeconfig
EOF

# Apply the job
echo -e "${BLUE}ℹ️  Starting backup job...${NC}"
kubectl apply -f /tmp/${JOB_NAME}.yaml

# Wait for job to start
echo -e "${BLUE}ℹ️  Waiting for job to start...${NC}"
kubectl wait --for=condition=ready pod -l job-name=${JOB_NAME} -n backup --timeout=60s

# Get pod name
POD_NAME=$(kubectl get pods -n backup -l job-name=${JOB_NAME} -o jsonpath='{.items[0].metadata.name}')

echo -e "${GREEN}✅ Backup job started successfully!${NC}"
echo -e "${BLUE}ℹ️  Pod name: ${POD_NAME}${NC}"
echo ""

# Follow logs
echo -e "${BLUE}ℹ️  Following backup logs (Ctrl+C to stop following, job will continue)...${NC}"
echo "=================================================================="
kubectl logs -f ${POD_NAME} -n backup || true

echo ""
echo "=================================================================="

# Check job status
JOB_STATUS=$(kubectl get job ${JOB_NAME} -n backup -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")

if [ "$JOB_STATUS" = "Complete" ]; then
    echo -e "${GREEN}✅ Backup job completed successfully!${NC}"
    
    # Show backup summary if available
    echo ""
    echo -e "${BLUE}ℹ️  Backup Summary:${NC}"
    kubectl logs ${POD_NAME} -n backup | grep -A 20 "Comprehensive backup completed successfully" || echo "Summary not available"
    
elif [ "$JOB_STATUS" = "Failed" ]; then
    echo -e "${YELLOW}⚠️  Backup job failed. Check logs above for details.${NC}"
else
    echo -e "${BLUE}ℹ️  Backup job is still running. Status: ${JOB_STATUS}${NC}"
    echo -e "${BLUE}ℹ️  Check status with: kubectl get job ${JOB_NAME} -n backup${NC}"
    echo -e "${BLUE}ℹ️  View logs with: kubectl logs ${POD_NAME} -n backup${NC}"
fi

# Cleanup temp file
rm -f /tmp/${JOB_NAME}.yaml

echo ""
echo -e "${BLUE}ℹ️  Useful commands:${NC}"
echo "   kubectl get job ${JOB_NAME} -n backup                    # Check job status"
echo "   kubectl logs ${POD_NAME} -n backup                       # View full logs"
echo "   kubectl delete job ${JOB_NAME} -n backup                 # Clean up job"
echo ""
echo -e "${BLUE}ℹ️  Backup location: ${BACKUP_LOCATION}${NC}"
echo -e "${BLUE}ℹ️  Access backup files via backup pod or NFS mount${NC}"