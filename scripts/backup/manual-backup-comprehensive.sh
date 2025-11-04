#!/bin/bash

set -e

echo "🔄 Comprehensive Manual Kubernetes Backup Script"
echo "==============================================="

# Configuration
BACKUP_TYPE=${1:-"all"}
BACKUP_BASE_DIR=${2:-"/tmp/k8s-backup"}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_BASE_DIR}/${TIMESTAMP}"
START_TIME=$(date +%s)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not available. Please ensure kubeconfig is set up."
        exit 1
    fi
    
    log_info "kubectl found: $(kubectl version --client --short 2>/dev/null || echo 'version check failed')"
    
    # Test kubectl connectivity
    log_info "Testing Kubernetes cluster connectivity..."
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        log_info "Kubeconfig location: ${KUBECONFIG:-~/.kube/config}"
        log_info "Current context: $(kubectl config current-context 2>/dev/null || echo 'none')"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
    log_info "Connected to cluster: $(kubectl config current-context 2>/dev/null || echo 'unknown')"
}

# Create backup directory structure
setup_backup_directory() {
    log_info "Setting up backup directory structure..."
    
    # Test if backup base directory is writable
    if [ ! -w "$(dirname "${BACKUP_DIR}")" ]; then
        log_error "Cannot write to backup base directory: $(dirname "${BACKUP_DIR}")"
        log_info "Check NFS mount permissions and server configuration"
        exit 1
    fi
    
    # Create directory structure with error handling
    if ! mkdir -p "${BACKUP_DIR}"/{etcd,resources,persistent-data} 2>/dev/null; then
        log_error "Failed to create backup directory structure"
        log_info "Backup directory: ${BACKUP_DIR}"
        log_info "Parent directory permissions: $(ls -ld "$(dirname "${BACKUP_DIR}")" 2>/dev/null || echo 'Cannot access')"
        log_info "Check NFS server permissions for: 192.168.1.7:/data/kubernetes/backups"
        exit 1
    fi
    
    if ! mkdir -p "${BACKUP_DIR}/persistent-data"/{grafana,prometheus,loki,mimir} 2>/dev/null; then
        log_error "Failed to create application data directories"
        exit 1
    fi
    
    # Test write permissions
    TEST_FILE="${BACKUP_DIR}/write-test-$(date +%s).tmp"
    if ! echo "Write test" > "$TEST_FILE" 2>/dev/null; then
        log_error "Cannot write to backup directory: ${BACKUP_DIR}"
        log_info "Check NFS server permissions and 'no_root_squash' option"
        exit 1
    fi
    rm -f "$TEST_FILE" 2>/dev/null || true
    
    log_success "Backup directory created: ${BACKUP_DIR}"
    log_info "Directory permissions: $(ls -ld "${BACKUP_DIR}" 2>/dev/null || echo 'Cannot access')"
}

# Backup ETCD (if running on control plane)
backup_etcd() {
    log_info "Backing up ETCD..."
    
    # Check if we're on a control plane node
    if kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers | grep -q "$(hostname)" 2>/dev/null; then
        log_info "Running on control plane node, creating ETCD backup..."
        
        mkdir -p "${BACKUP_DIR}/etcd"
        
        # Create ETCD snapshot
        if command -v etcdctl &> /dev/null; then
            ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
                --cacert=/etc/kubernetes/pki/etcd/ca.crt \
                --cert=/etc/kubernetes/pki/etcd/server.crt \
                --key=/etc/kubernetes/pki/etcd/server.key \
                snapshot save "${BACKUP_DIR}/etcd/etcd-snapshot-${TIMESTAMP}.db" 2>/dev/null || {
                log_warning "Could not create ETCD snapshot directly"
            }
        fi
        
        # Copy PKI certificates
        if [ -d "/etc/kubernetes/pki" ]; then
            cp -r /etc/kubernetes/pki "${BACKUP_DIR}/etcd/" 2>/dev/null || log_warning "Could not copy PKI certificates"
        fi
        
        log_success "ETCD backup completed"
    else
        log_warning "Not running on control plane node, skipping ETCD backup"
        log_info "To backup ETCD, run this script on a control plane node or use the scheduled backup"
    fi
}

# Backup Kubernetes resources
backup_kubernetes_resources() {
    log_info "Backing up Kubernetes resources..."
    
    mkdir -p "${BACKUP_DIR}/resources"
    
    # Backup all namespaces
    log_info "Backing up namespaces..."
    kubectl get namespaces -o yaml > "${BACKUP_DIR}/resources/namespaces.yaml"
    
    # Backup critical resources by namespace
    NAMESPACES="monitoring media backup metallb-system kube-system default"
    
    for ns in $NAMESPACES; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            log_info "Backing up namespace: $ns"
            mkdir -p "${BACKUP_DIR}/resources/${ns}"
            
            # Backup deployments
            kubectl get deployments -n "$ns" -o yaml > "${BACKUP_DIR}/resources/${ns}/deployments.yaml" 2>/dev/null || echo "No deployments in $ns"
            
            # Backup services
            kubectl get services -n "$ns" -o yaml > "${BACKUP_DIR}/resources/${ns}/services.yaml" 2>/dev/null || echo "No services in $ns"
            
            # Backup configmaps
            kubectl get configmaps -n "$ns" -o yaml > "${BACKUP_DIR}/resources/${ns}/configmaps.yaml" 2>/dev/null || echo "No configmaps in $ns"
            
            # Backup secrets (excluding service account tokens)
            kubectl get secrets -n "$ns" -o yaml | grep -v "kubernetes.io/service-account-token" > "${BACKUP_DIR}/resources/${ns}/secrets.yaml" 2>/dev/null || echo "No secrets in $ns"
            
            # Backup persistent volume claims
            kubectl get pvc -n "$ns" -o yaml > "${BACKUP_DIR}/resources/${ns}/pvc.yaml" 2>/dev/null || echo "No PVCs in $ns"
            
            # Backup daemonsets
            kubectl get daemonsets -n "$ns" -o yaml > "${BACKUP_DIR}/resources/${ns}/daemonsets.yaml" 2>/dev/null || echo "No daemonsets in $ns"
            
            # Backup statefulsets
            kubectl get statefulsets -n "$ns" -o yaml > "${BACKUP_DIR}/resources/${ns}/statefulsets.yaml" 2>/dev/null || echo "No statefulsets in $ns"
            
            # Backup cronjobs
            kubectl get cronjobs -n "$ns" -o yaml > "${BACKUP_DIR}/resources/${ns}/cronjobs.yaml" 2>/dev/null || echo "No cronjobs in $ns"
        else
            log_warning "Namespace $ns does not exist, skipping..."
        fi
    done
    
    # Backup cluster-wide resources
    log_info "Backing up cluster-wide resources..."
    mkdir -p "${BACKUP_DIR}/resources/cluster"
    
    kubectl get clusterroles -o yaml > "${BACKUP_DIR}/resources/cluster/clusterroles.yaml" 2>/dev/null || echo "No clusterroles"
    kubectl get clusterrolebindings -o yaml > "${BACKUP_DIR}/resources/cluster/clusterrolebindings.yaml" 2>/dev/null || echo "No clusterrolebindings"
    kubectl get persistentvolumes -o yaml > "${BACKUP_DIR}/resources/cluster/persistentvolumes.yaml" 2>/dev/null || echo "No persistent volumes"
    kubectl get storageclasses -o yaml > "${BACKUP_DIR}/resources/cluster/storageclasses.yaml" 2>/dev/null || echo "No storage classes"
    kubectl get nodes -o yaml > "${BACKUP_DIR}/resources/cluster/nodes.yaml" 2>/dev/null || echo "No nodes"
    
    log_success "Kubernetes resources backup completed"
}



# Backup Grafana data
backup_grafana() {
    log_info "Backing up Grafana data..."
    
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        GRAFANA_POD=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ -n "$GRAFANA_POD" ] && [ "$GRAFANA_POD" != "null" ]; then
            log_info "Found Grafana pod: $GRAFANA_POD"
            
            # Backup Grafana database
            kubectl exec -n monitoring "$GRAFANA_POD" -- sh -c 'if [ -f /var/lib/grafana/grafana.db ]; then cat /var/lib/grafana/grafana.db; else echo "Database not found"; fi' > "${BACKUP_DIR}/persistent-data/grafana/grafana.db" 2>/dev/null || log_warning "Could not backup Grafana database"
            
            # Backup Grafana data directory
            kubectl exec -n monitoring "$GRAFANA_POD" -- sh -c 'if [ -d /var/lib/grafana ]; then tar -czf - /var/lib/grafana --exclude="*.log" 2>/dev/null; else echo "Data directory not found"; fi' > "${BACKUP_DIR}/persistent-data/grafana/grafana-data.tar.gz" 2>/dev/null || log_warning "Could not backup Grafana data"
            
            # Create backup info
            GRAFANA_DB_SIZE=$(kubectl exec -n monitoring "$GRAFANA_POD" -- sh -c 'if [ -f /var/lib/grafana/grafana.db ]; then ls -la /var/lib/grafana/grafana.db | awk "{print \$5}"; else echo "0"; fi' 2>/dev/null || echo "0")
            
            cat > "${BACKUP_DIR}/persistent-data/grafana/backup-info.txt" << EOF
Grafana Backup Information
=========================
Backup Date: $(date)
Pod Name: ${GRAFANA_POD}
Database Size: ${GRAFANA_DB_SIZE} bytes
Database Path: /var/lib/grafana/grafana.db
Data Path: /var/lib/grafana
EOF
            
            log_success "Grafana data backup completed"
        else
            log_warning "Grafana pod not found or not running"
        fi
    else
        log_warning "Monitoring namespace not found"
    fi
}

# Backup Prometheus data
backup_prometheus() {
    log_info "Backing up Prometheus data..."
    
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        PROMETHEUS_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ -n "$PROMETHEUS_POD" ] && [ "$PROMETHEUS_POD" != "null" ]; then
            log_info "Found Prometheus pod: $PROMETHEUS_POD"
            
            # Try to create a snapshot first
            log_info "Creating Prometheus snapshot..."
            SNAPSHOT_NAME=$(kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c 'curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot 2>/dev/null | grep -o "\"name\":\"[^\"]*\"" | cut -d"\"" -f4' 2>/dev/null || echo "")
            
            if [ -n "$SNAPSHOT_NAME" ]; then
                log_info "Backing up Prometheus snapshot: $SNAPSHOT_NAME"
                kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c "if [ -d /prometheus/snapshots/$SNAPSHOT_NAME ]; then tar -czf - /prometheus/snapshots/$SNAPSHOT_NAME 2>/dev/null; else echo 'Snapshot not found'; fi" > "${BACKUP_DIR}/persistent-data/prometheus/prometheus-snapshot.tar.gz" 2>/dev/null || log_warning "Could not backup Prometheus snapshot"
                
                PROMETHEUS_SIZE=$(kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c "if [ -d /prometheus/snapshots/$SNAPSHOT_NAME ]; then du -sb /prometheus/snapshots/$SNAPSHOT_NAME | cut -f1; else echo '0'; fi" 2>/dev/null || echo "0")
            else
                log_warning "Could not create Prometheus snapshot, backing up data directory..."
                kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c 'if [ -d /prometheus ]; then tar -czf - /prometheus --exclude="*.tmp" --exclude="queries.active" 2>/dev/null; else echo "Data directory not found"; fi' > "${BACKUP_DIR}/persistent-data/prometheus/prometheus-data.tar.gz" 2>/dev/null || log_warning "Could not backup Prometheus data"
                PROMETHEUS_SIZE=$(kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c 'if [ -d /prometheus ]; then du -sb /prometheus | cut -f1; else echo "0"; fi' 2>/dev/null || echo "0")
            fi
            
            # Create backup info
            cat > "${BACKUP_DIR}/persistent-data/prometheus/backup-info.txt" << EOF
Prometheus Backup Information
============================
Backup Date: $(date)
Pod Name: ${PROMETHEUS_POD}
Snapshot Name: ${SNAPSHOT_NAME:-"N/A"}
Data Size: ${PROMETHEUS_SIZE} bytes
Data Path: /prometheus
EOF
            
            log_success "Prometheus data backup completed"
        else
            log_warning "Prometheus pod not found or not running"
        fi
    else
        log_warning "Monitoring namespace not found"
    fi
}

# Backup Loki data
backup_loki() {
    log_info "Backing up Loki data..."
    
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        LOKI_POD=$(kubectl get pods -n monitoring -l app=loki -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ -n "$LOKI_POD" ] && [ "$LOKI_POD" != "null" ]; then
            log_info "Found Loki pod: $LOKI_POD"
            
            # Backup Loki data
            kubectl exec -n monitoring "$LOKI_POD" -- sh -c 'if [ -d /loki ]; then tar -czf - /loki 2>/dev/null; else echo "Data directory not found"; fi' > "${BACKUP_DIR}/persistent-data/loki/loki-data.tar.gz" 2>/dev/null || log_warning "Could not backup Loki data"
            
            # Create backup info
            LOKI_SIZE=$(kubectl exec -n monitoring "$LOKI_POD" -- sh -c 'if [ -d /loki ]; then du -sb /loki | cut -f1; else echo "0"; fi' 2>/dev/null || echo "0")
            
            cat > "${BACKUP_DIR}/persistent-data/loki/backup-info.txt" << EOF
Loki Backup Information
======================
Backup Date: $(date)
Pod Name: ${LOKI_POD}
Data Size: ${LOKI_SIZE} bytes
Data Path: /loki
EOF
            
            log_success "Loki data backup completed"
        else
            log_warning "Loki pod not found or not running"
        fi
    else
        log_warning "Monitoring namespace not found"
    fi
}

# Backup Mimir data
backup_mimir() {
    log_info "Backing up Mimir data..."
    
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        MIMIR_POD=$(kubectl get pods -n monitoring -l app=mimir -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ -n "$MIMIR_POD" ] && [ "$MIMIR_POD" != "null" ]; then
            log_info "Found Mimir pod: $MIMIR_POD"
            
            # Backup Mimir data
            kubectl exec -n monitoring "$MIMIR_POD" -- sh -c 'if [ -d /data ]; then tar -czf - /data 2>/dev/null; else echo "Data directory not found"; fi' > "${BACKUP_DIR}/persistent-data/mimir/mimir-data.tar.gz" 2>/dev/null || log_warning "Could not backup Mimir data"
            
            # Create backup info
            MIMIR_SIZE=$(kubectl exec -n monitoring "$MIMIR_POD" -- sh -c 'if [ -d /data ]; then du -sb /data | cut -f1; else echo "0"; fi' 2>/dev/null || echo "0")
            
            cat > "${BACKUP_DIR}/persistent-data/mimir/backup-info.txt" << EOF
Mimir Backup Information
=======================
Backup Date: $(date)
Pod Name: ${MIMIR_POD}
Data Size: ${MIMIR_SIZE} bytes
Data Path: /data
EOF
            
            log_success "Mimir data backup completed"
        else
            log_warning "Mimir pod not found or not running"
        fi
    else
        log_warning "Monitoring namespace not found"
    fi
}

# Create comprehensive backup summary
create_backup_summary() {
    log_info "Creating backup summary..."
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    BACKUP_SIZE=$(du -sb "${BACKUP_DIR}" | cut -f1)
    
    cat > "${BACKUP_DIR}/backup-summary.txt" << EOF
Comprehensive Kubernetes Backup Summary
=======================================
Backup Date: $(date)
Backup Type: ${BACKUP_TYPE}
Backup Duration: ${DURATION} seconds
Backup Location: ${BACKUP_DIR}
Total Backup Size: $(du -sh "${BACKUP_DIR}" | cut -f1) (${BACKUP_SIZE} bytes)
Kubernetes Version: $(kubectl version --short --client 2>/dev/null || echo "N/A")

Cluster Information:
===================
Nodes: $(kubectl get nodes --no-headers 2>/dev/null | wc -l)
Namespaces: $(kubectl get namespaces --no-headers 2>/dev/null | wc -l)
Pods: $(kubectl get pods --all-namespaces --no-headers 2>/dev/null | wc -l)
Services: $(kubectl get svc --all-namespaces --no-headers 2>/dev/null | wc -l)
PVCs: $(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l)

Backup Contents:
===============
Resource Files: $(find "${BACKUP_DIR}/resources" -name "*.yaml" 2>/dev/null | wc -l)
Application Data Files: $(find "${BACKUP_DIR}/persistent-data" -type f 2>/dev/null | wc -l)

Application Backup Status:
=========================

Grafana: $(if [ -f "${BACKUP_DIR}/persistent-data/grafana/grafana.db" ]; then echo "✅ Success"; else echo "❌ Failed"; fi)
Prometheus: $(if [ -f "${BACKUP_DIR}/persistent-data/prometheus/prometheus-snapshot.tar.gz" ] || [ -f "${BACKUP_DIR}/persistent-data/prometheus/prometheus-data.tar.gz" ]; then echo "✅ Success"; else echo "❌ Failed"; fi)
Loki: $(if [ -f "${BACKUP_DIR}/persistent-data/loki/loki-data.tar.gz" ]; then echo "✅ Success"; else echo "❌ Failed"; fi)
Mimir: $(if [ -f "${BACKUP_DIR}/persistent-data/mimir/mimir-data.tar.gz" ]; then echo "✅ Success"; else echo "❌ Failed"; fi)

Directory Structure:
===================
$(find "${BACKUP_DIR}" -type d | sort)

File Listing:
============
$(find "${BACKUP_DIR}" -type f -exec ls -lh {} \; | sort -k5 -hr)
EOF
    
    log_success "Backup summary created"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [BACKUP_TYPE] [BACKUP_DIR]"
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
    echo "BACKUP_DIR: Directory to store backups (default: /tmp/k8s-backup)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Backup everything to /tmp/k8s-backup"
    echo "  $0 all /backup               # Backup everything to /backup"
    echo "  $0 apps                      # Backup only application data"
    echo "  $0 grafana /home/user/backup # Backup only Grafana to custom directory"
}

# Main execution
main() {
    echo "🚀 Starting comprehensive backup process..."
    echo "📅 Timestamp: ${TIMESTAMP}"
    echo "📦 Backup type: ${BACKUP_TYPE}"
    echo "📁 Backup directory: ${BACKUP_DIR}"
    echo ""
    
    check_prerequisites
    setup_backup_directory
    
    case $BACKUP_TYPE in
        "all")
            backup_etcd
            backup_kubernetes_resources
            backup_grafana
            backup_prometheus
            backup_loki
            backup_mimir
            ;;
        "etcd")
            backup_etcd
            ;;
        "resources")
            backup_kubernetes_resources
            ;;
        "apps")
            backup_grafana
            backup_prometheus
            backup_loki
            backup_mimir
            ;;
        "grafana")
            backup_grafana
            ;;
        "prometheus")
            backup_prometheus
            ;;
        "loki")
            backup_loki
            ;;
        "mimir")
            backup_mimir
            ;;
        "help"|"-h"|"--help")
            show_usage
            exit 0
            ;;
        *)
            log_error "Invalid backup type: $BACKUP_TYPE"
            show_usage
            exit 1
            ;;
    esac
    
    create_backup_summary
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    log_success "Comprehensive backup completed successfully!"
    echo "📍 Backup location: ${BACKUP_DIR}"
    echo "📊 Backup size: $(du -sh "${BACKUP_DIR}" | cut -f1)"
    echo "⏱️  Duration: ${DURATION} seconds"
    echo ""
    echo "📋 Quick Stats:"
    echo "   Resource files: $(find "${BACKUP_DIR}/resources" -name "*.yaml" 2>/dev/null | wc -l)"
    echo "   Application data files: $(find "${BACKUP_DIR}/persistent-data" -type f 2>/dev/null | wc -l)"
    echo ""
    echo "💡 Next Steps:"
    echo "   📦 Create archive: tar czf k8s-backup-${TIMESTAMP}.tar.gz -C ${BACKUP_BASE_DIR} ${TIMESTAMP}"
    echo "   📋 View summary: cat ${BACKUP_DIR}/backup-summary.txt"
    echo "   🔄 Restore help: See BACKUP_GUIDE.md for restore procedures"
    echo ""
    echo "🔗 Related Commands:"
    echo "   kubectl get pods --all-namespaces  # Check cluster status"
    echo "   kubectl get pv                     # Check persistent volumes"
    echo "   df -h ${BACKUP_BASE_DIR}          # Check backup storage space"
}

# Handle script arguments
if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# Run main function
main