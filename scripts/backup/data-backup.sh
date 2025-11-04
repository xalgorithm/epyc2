#!/bin/sh

set -e

echo "🔄 Starting Kubernetes data backup process..."

# Record start time for duration calculation
BACKUP_START_TIME=$(date +%s)

# Install kubectl
apk add --no-cache curl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Configuration
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_DATE}"

# Create backup directory
mkdir -p "${BACKUP_PATH}"

echo "📁 Backup directory: ${BACKUP_PATH}"

# Backup Kubernetes resources
echo "📦 Backing up Kubernetes resources..."

# Create resource backup directories
mkdir -p "${BACKUP_PATH}/resources"
mkdir -p "${BACKUP_PATH}/persistent-data"

# Backup all namespaces
echo "🏷️  Backing up namespaces..."
kubectl get namespaces -o yaml > "${BACKUP_PATH}/resources/namespaces.yaml"

# Backup critical resources by namespace
NAMESPACES="monitoring media backup metallb-system kube-system"

for ns in $NAMESPACES; do
    echo "📂 Backing up namespace: $ns"
    mkdir -p "${BACKUP_PATH}/resources/${ns}"
    
    # Skip if namespace doesn't exist
    if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
        echo "⚠️  Namespace $ns does not exist, skipping..."
        continue
    fi
    
    # Backup deployments
    kubectl get deployments -n "$ns" -o yaml > "${BACKUP_PATH}/resources/${ns}/deployments.yaml" 2>/dev/null || echo "No deployments in $ns"
    
    # Backup services
    kubectl get services -n "$ns" -o yaml > "${BACKUP_PATH}/resources/${ns}/services.yaml" 2>/dev/null || echo "No services in $ns"
    
    # Backup configmaps
    kubectl get configmaps -n "$ns" -o yaml > "${BACKUP_PATH}/resources/${ns}/configmaps.yaml" 2>/dev/null || echo "No configmaps in $ns"
    
    # Backup secrets (excluding service account tokens)
    kubectl get secrets -n "$ns" -o yaml | grep -v "kubernetes.io/service-account-token" > "${BACKUP_PATH}/resources/${ns}/secrets.yaml" 2>/dev/null || echo "No secrets in $ns"
    
    # Backup persistent volume claims
    kubectl get pvc -n "$ns" -o yaml > "${BACKUP_PATH}/resources/${ns}/pvc.yaml" 2>/dev/null || echo "No PVCs in $ns"
    
    # Backup daemonsets
    kubectl get daemonsets -n "$ns" -o yaml > "${BACKUP_PATH}/resources/${ns}/daemonsets.yaml" 2>/dev/null || echo "No daemonsets in $ns"
    
    # Backup statefulsets
    kubectl get statefulsets -n "$ns" -o yaml > "${BACKUP_PATH}/resources/${ns}/statefulsets.yaml" 2>/dev/null || echo "No statefulsets in $ns"
    
    # Backup cronjobs
    kubectl get cronjobs -n "$ns" -o yaml > "${BACKUP_PATH}/resources/${ns}/cronjobs.yaml" 2>/dev/null || echo "No cronjobs in $ns"
done

# Backup cluster-wide resources
echo "🌐 Backing up cluster-wide resources..."
mkdir -p "${BACKUP_PATH}/resources/cluster"

kubectl get clusterroles -o yaml > "${BACKUP_PATH}/resources/cluster/clusterroles.yaml" 2>/dev/null || echo "No clusterroles"
kubectl get clusterrolebindings -o yaml > "${BACKUP_PATH}/resources/cluster/clusterrolebindings.yaml" 2>/dev/null || echo "No clusterrolebindings"
kubectl get persistentvolumes -o yaml > "${BACKUP_PATH}/resources/cluster/persistentvolumes.yaml" 2>/dev/null || echo "No persistent volumes"
kubectl get storageclasses -o yaml > "${BACKUP_PATH}/resources/cluster/storageclasses.yaml" 2>/dev/null || echo "No storage classes"
kubectl get nodes -o yaml > "${BACKUP_PATH}/resources/cluster/nodes.yaml" 2>/dev/null || echo "No nodes"

# Backup application data (if accessible)
echo "💾 Backing up application data..."



# Backup Grafana data
echo "📊 Backing up Grafana data..."
mkdir -p "${BACKUP_PATH}/persistent-data/grafana"

# Check if monitoring namespace exists
if kubectl get namespace monitoring >/dev/null 2>&1; then
    # Get Grafana pod name
    GRAFANA_POD=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$GRAFANA_POD" ] && [ "$GRAFANA_POD" != "null" ]; then
        echo "📱 Found Grafana pod: $GRAFANA_POD"
        
        # Backup Grafana database and configuration
        echo "🗄️  Backing up Grafana database..."
        kubectl exec -n monitoring "$GRAFANA_POD" -- sh -c 'if [ -f /var/lib/grafana/grafana.db ]; then cat /var/lib/grafana/grafana.db; else echo "Database not found"; fi' > "${BACKUP_PATH}/persistent-data/grafana/grafana.db" 2>/dev/null || echo "⚠️  Could not backup Grafana database"
        
        # Backup Grafana plugins and data
        echo "🔌 Backing up Grafana plugins and data..."
        kubectl exec -n monitoring "$GRAFANA_POD" -- sh -c 'if [ -d /var/lib/grafana ]; then tar -czf - /var/lib/grafana --exclude="*.log" 2>/dev/null; else echo "Data directory not found"; fi' > "${BACKUP_PATH}/persistent-data/grafana/grafana-data.tar.gz" 2>/dev/null || echo "⚠️  Could not backup Grafana data"
        
        # Get database info
        GRAFANA_DB_SIZE=$(kubectl exec -n monitoring "$GRAFANA_POD" -- sh -c 'if [ -f /var/lib/grafana/grafana.db ]; then ls -la /var/lib/grafana/grafana.db | awk "{print \$5}"; else echo "0"; fi' 2>/dev/null || echo "0")
        echo "📊 Grafana database size: ${GRAFANA_DB_SIZE} bytes"
        
        # Create Grafana backup info
        cat > "${BACKUP_PATH}/persistent-data/grafana/backup-info.txt" << EOF
Grafana Backup Information
=========================
Backup Date: $(date)
Pod Name: ${GRAFANA_POD}
Database Size: ${GRAFANA_DB_SIZE} bytes
Database Path: /var/lib/grafana/grafana.db
Data Path: /var/lib/grafana

Files Backed Up:
- grafana.db (Grafana database)
- grafana-data.tar.gz (Grafana data directory archive)
EOF
        
        echo "✅ Grafana data backup completed"
    else
        echo "⚠️  Grafana pod not found or not running"
        echo "📝 Creating placeholder for Grafana backup..."
        echo "Grafana pod not available during backup" > "${BACKUP_PATH}/persistent-data/grafana/backup-unavailable.txt"
    fi
else
    echo "⚠️  Monitoring namespace not found"
fi

# Backup Prometheus data
echo "📈 Backing up Prometheus data..."
mkdir -p "${BACKUP_PATH}/persistent-data/prometheus"

if kubectl get namespace monitoring >/dev/null 2>&1; then
    # Get Prometheus pod name
    PROMETHEUS_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$PROMETHEUS_POD" ] && [ "$PROMETHEUS_POD" != "null" ]; then
        echo "📱 Found Prometheus pod: $PROMETHEUS_POD"
        
        # Backup Prometheus TSDB data (create snapshot)
        echo "📸 Creating Prometheus snapshot..."
        SNAPSHOT_NAME=$(kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c 'curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot 2>/dev/null | grep -o "\"name\":\"[^\"]*\"" | cut -d"\"" -f4' 2>/dev/null || echo "")
        
        if [ -n "$SNAPSHOT_NAME" ]; then
            echo "📦 Backing up Prometheus snapshot: $SNAPSHOT_NAME"
            kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c "if [ -d /prometheus/snapshots/$SNAPSHOT_NAME ]; then tar -czf - /prometheus/snapshots/$SNAPSHOT_NAME 2>/dev/null; else echo 'Snapshot not found'; fi" > "${BACKUP_PATH}/persistent-data/prometheus/prometheus-snapshot.tar.gz" 2>/dev/null || echo "⚠️  Could not backup Prometheus snapshot"
            
            # Get snapshot size
            PROMETHEUS_SIZE=$(kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c "if [ -d /prometheus/snapshots/$SNAPSHOT_NAME ]; then du -sb /prometheus/snapshots/$SNAPSHOT_NAME | cut -f1; else echo '0'; fi" 2>/dev/null || echo "0")
            echo "📊 Prometheus snapshot size: ${PROMETHEUS_SIZE} bytes"
        else
            echo "⚠️  Could not create Prometheus snapshot, backing up current data..."
            kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c 'if [ -d /prometheus ]; then tar -czf - /prometheus --exclude="*.tmp" --exclude="queries.active" 2>/dev/null; else echo "Data directory not found"; fi' > "${BACKUP_PATH}/persistent-data/prometheus/prometheus-data.tar.gz" 2>/dev/null || echo "⚠️  Could not backup Prometheus data"
            PROMETHEUS_SIZE=$(kubectl exec -n monitoring "$PROMETHEUS_POD" -- sh -c 'if [ -d /prometheus ]; then du -sb /prometheus | cut -f1; else echo "0"; fi' 2>/dev/null || echo "0")
        fi
        
        # Create Prometheus backup info
        cat > "${BACKUP_PATH}/persistent-data/prometheus/backup-info.txt" << EOF
Prometheus Backup Information
============================
Backup Date: $(date)
Pod Name: ${PROMETHEUS_POD}
Snapshot Name: ${SNAPSHOT_NAME:-"N/A"}
Data Size: ${PROMETHEUS_SIZE} bytes
Data Path: /prometheus

Files Backed Up:
- prometheus-snapshot.tar.gz (Prometheus TSDB snapshot)
- prometheus-data.tar.gz (Prometheus data directory - fallback)
EOF
        
        echo "✅ Prometheus data backup completed"
    else
        echo "⚠️  Prometheus pod not found or not running"
        echo "📝 Creating placeholder for Prometheus backup..."
        echo "Prometheus pod not available during backup" > "${BACKUP_PATH}/persistent-data/prometheus/backup-unavailable.txt"
    fi
fi

# Backup Loki data
echo "📝 Backing up Loki data..."
mkdir -p "${BACKUP_PATH}/persistent-data/loki"

if kubectl get namespace monitoring >/dev/null 2>&1; then
    # Get Loki pod name
    LOKI_POD=$(kubectl get pods -n monitoring -l app=loki -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$LOKI_POD" ] && [ "$LOKI_POD" != "null" ]; then
        echo "📱 Found Loki pod: $LOKI_POD"
        
        # Backup Loki data directory
        echo "📦 Backing up Loki data..."
        kubectl exec -n monitoring "$LOKI_POD" -- sh -c 'if [ -d /loki ]; then tar -czf - /loki 2>/dev/null; else echo "Data directory not found"; fi' > "${BACKUP_PATH}/persistent-data/loki/loki-data.tar.gz" 2>/dev/null || echo "⚠️  Could not backup Loki data"
        
        # Get data size
        LOKI_SIZE=$(kubectl exec -n monitoring "$LOKI_POD" -- sh -c 'if [ -d /loki ]; then du -sb /loki | cut -f1; else echo "0"; fi' 2>/dev/null || echo "0")
        echo "📊 Loki data size: ${LOKI_SIZE} bytes"
        
        # Create Loki backup info
        cat > "${BACKUP_PATH}/persistent-data/loki/backup-info.txt" << EOF
Loki Backup Information
======================
Backup Date: $(date)
Pod Name: ${LOKI_POD}
Data Size: ${LOKI_SIZE} bytes
Data Path: /loki

Files Backed Up:
- loki-data.tar.gz (Loki data directory archive)
EOF
        
        echo "✅ Loki data backup completed"
    else
        echo "⚠️  Loki pod not found or not running"
        echo "📝 Creating placeholder for Loki backup..."
        echo "Loki pod not available during backup" > "${BACKUP_PATH}/persistent-data/loki/backup-unavailable.txt"
    fi
fi

# Backup Mimir data
echo "🎯 Backing up Mimir data..."
mkdir -p "${BACKUP_PATH}/persistent-data/mimir"

if kubectl get namespace monitoring >/dev/null 2>&1; then
    # Get Mimir pod name
    MIMIR_POD=$(kubectl get pods -n monitoring -l app=mimir -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$MIMIR_POD" ] && [ "$MIMIR_POD" != "null" ]; then
        echo "📱 Found Mimir pod: $MIMIR_POD"
        
        # Backup Mimir data directory
        echo "📦 Backing up Mimir data..."
        kubectl exec -n monitoring "$MIMIR_POD" -- sh -c 'if [ -d /data ]; then tar -czf - /data 2>/dev/null; else echo "Data directory not found"; fi' > "${BACKUP_PATH}/persistent-data/mimir/mimir-data.tar.gz" 2>/dev/null || echo "⚠️  Could not backup Mimir data"
        
        # Get data size
        MIMIR_SIZE=$(kubectl exec -n monitoring "$MIMIR_POD" -- sh -c 'if [ -d /data ]; then du -sb /data | cut -f1; else echo "0"; fi' 2>/dev/null || echo "0")
        echo "📊 Mimir data size: ${MIMIR_SIZE} bytes"
        
        # Create Mimir backup info
        cat > "${BACKUP_PATH}/persistent-data/mimir/backup-info.txt" << EOF
Mimir Backup Information
=======================
Backup Date: $(date)
Pod Name: ${MIMIR_POD}
Data Size: ${MIMIR_SIZE} bytes
Data Path: /data

Files Backed Up:
- mimir-data.tar.gz (Mimir data directory archive)
EOF
        
        echo "✅ Mimir data backup completed"
    else
        echo "⚠️  Mimir pod not found or not running"
        echo "📝 Creating placeholder for Mimir backup..."
        echo "Mimir pod not available during backup" > "${BACKUP_PATH}/persistent-data/mimir/backup-unavailable.txt"
    fi
fi

# Create application data backup script
cat > "${BACKUP_PATH}/backup-app-data.sh" << 'EOF'
#!/bin/sh
# This script can be run manually to backup application data
# that requires specific procedures

echo "🔄 Manual application data backup script"
echo "========================================"

echo "📊 Backing up Grafana dashboards and data sources..."
# Grafana data is backed up automatically in the main backup process
# This includes: grafana.db, plugins, dashboards, and data directory

echo "📈 Backing up Prometheus data..."
# Prometheus data is backed up automatically using snapshots
# This includes: TSDB snapshots and data directory

echo "📝 Backing up Loki data..."
# Loki data is backed up automatically in the main backup process
# This includes: log data and indexes

echo "🎯 Backing up Mimir data..."
# Mimir data is backed up automatically in the main backup process
# This includes: metrics data and indexes



echo "✅ All application data is backed up automatically!"
echo "📁 Check the persistent-data directory for individual service backups"
EOF

chmod +x "${BACKUP_PATH}/backup-app-data.sh"

# Create cluster state summary
echo "📊 Creating cluster state summary..."
cat > "${BACKUP_PATH}/cluster-state.txt" << EOF
Cluster State Summary
====================
Backup Date: $(date)
Kubernetes Version: $(kubectl version --short 2>/dev/null || echo "N/A")

Nodes:
$(kubectl get nodes -o wide 2>/dev/null || echo "Unable to get nodes")

Namespaces:
$(kubectl get namespaces 2>/dev/null || echo "Unable to get namespaces")

Persistent Volumes:
$(kubectl get pv 2>/dev/null || echo "No persistent volumes")

Storage Classes:
$(kubectl get storageclass 2>/dev/null || echo "No storage classes")

Services (LoadBalancer):
$(kubectl get svc --all-namespaces | grep LoadBalancer 2>/dev/null || echo "No LoadBalancer services")

Pod Status Summary:
$(kubectl get pods --all-namespaces --field-selector=status.phase!=Running 2>/dev/null || echo "All pods running or unable to check")



Observability Stack Status:
$(kubectl get pods -n monitoring 2>/dev/null || echo "Monitoring namespace not found")

Monitoring Persistent Volumes:
$(kubectl get pvc -n monitoring 2>/dev/null || echo "No monitoring PVCs found")

Grafana Status:
$(kubectl get pods -n monitoring -l app=grafana 2>/dev/null || echo "Grafana not deployed")

Prometheus Status:
$(kubectl get pods -n monitoring -l app=prometheus 2>/dev/null || echo "Prometheus not deployed")

Loki Status:
$(kubectl get pods -n monitoring -l app=loki 2>/dev/null || echo "Loki not deployed")

Mimir Status:
$(kubectl get pods -n monitoring -l app=mimir 2>/dev/null || echo "Mimir not deployed")
EOF

# Create backup metadata
echo "📋 Creating backup metadata..."
cat > "${BACKUP_PATH}/backup-info.txt" << EOF
Backup Date: $(date)
Backup Type: Kubernetes Resources and Data
Kubernetes Version: $(kubectl version --short --client 2>/dev/null || echo "N/A")
Backup Size: $(du -sh "${BACKUP_PATH}" | cut -f1)
Namespaces Backed Up: ${NAMESPACES}
Resource Types: deployments, services, configmaps, secrets, pvc, daemonsets, statefulsets, cronjobs
Cluster Resources: clusterroles, clusterrolebindings, persistentvolumes, storageclasses, nodes
Application Data: Grafana, Prometheus, Loki, Mimir
Persistent Data: 

  - Grafana: grafana.db, data directory archive
  - Prometheus: TSDB snapshots, data directory archive
  - Loki: data directory archive
  - Mimir: data directory archive
EOF

# Create success marker
touch "${BACKUP_PATH}/backup-success"

# Update metrics
echo "📊 Updating backup metrics..."

# Calculate backup duration
BACKUP_END_TIME=$(date +%s)
BACKUP_DURATION=$((BACKUP_END_TIME - BACKUP_START_TIME))

# Calculate sizes and counts
BACKUP_SIZE=$(du -sb "${BACKUP_PATH}" | cut -f1)

GRAFANA_DB_SIZE=$(if [ -f "${BACKUP_PATH}/persistent-data/grafana/grafana.db" ]; then ls -la "${BACKUP_PATH}/persistent-data/grafana/grafana.db" | awk '{print $5}'; else echo "0"; fi)
PROMETHEUS_SIZE=$(if [ -f "${BACKUP_PATH}/persistent-data/prometheus/prometheus-snapshot.tar.gz" ]; then ls -la "${BACKUP_PATH}/persistent-data/prometheus/prometheus-snapshot.tar.gz" | awk '{print $5}'; elif [ -f "${BACKUP_PATH}/persistent-data/prometheus/prometheus-data.tar.gz" ]; then ls -la "${BACKUP_PATH}/persistent-data/prometheus/prometheus-data.tar.gz" | awk '{print $5}'; else echo "0"; fi)
LOKI_SIZE=$(if [ -f "${BACKUP_PATH}/persistent-data/loki/loki-data.tar.gz" ]; then ls -la "${BACKUP_PATH}/persistent-data/loki/loki-data.tar.gz" | awk '{print $5}'; else echo "0"; fi)
MIMIR_SIZE=$(if [ -f "${BACKUP_PATH}/persistent-data/mimir/mimir-data.tar.gz" ]; then ls -la "${BACKUP_PATH}/persistent-data/mimir/mimir-data.tar.gz" | awk '{print $5}'; else echo "0"; fi)
RESOURCE_COUNT=$(find "${BACKUP_PATH}/resources" -name "*.yaml" | wc -l)

# Count total backup files and directories
TOTAL_BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}" | wc -l)
TOTAL_BACKUP_FILES=$(find "${BACKUP_DIR}" -type f | wc -l)

# Backup success status

GRAFANA_BACKUP_STATUS=$(if [ -f "${BACKUP_PATH}/persistent-data/grafana/grafana.db" ]; then echo "1"; else echo "0"; fi)
PROMETHEUS_BACKUP_STATUS=$(if [ -f "${BACKUP_PATH}/persistent-data/prometheus/prometheus-snapshot.tar.gz" ] || [ -f "${BACKUP_PATH}/persistent-data/prometheus/prometheus-data.tar.gz" ]; then echo "1"; else echo "0"; fi)
LOKI_BACKUP_STATUS=$(if [ -f "${BACKUP_PATH}/persistent-data/loki/loki-data.tar.gz" ]; then echo "1"; else echo "0"; fi)
MIMIR_BACKUP_STATUS=$(if [ -f "${BACKUP_PATH}/persistent-data/mimir/mimir-data.tar.gz" ]; then echo "1"; else echo "0"; fi)

cat > /tmp/data_backup_metrics.prom << EOF
# HELP k8s_data_backup_last_success_timestamp Last successful data backup timestamp
# TYPE k8s_data_backup_last_success_timestamp gauge
k8s_data_backup_last_success_timestamp $(date +%s)

# HELP k8s_data_backup_size_bytes Size of the last data backup in bytes
# TYPE k8s_data_backup_size_bytes gauge
k8s_data_backup_size_bytes ${BACKUP_SIZE}

# HELP k8s_data_backup_resources_count Number of resource types backed up
# TYPE k8s_data_backup_resources_count gauge
k8s_data_backup_resources_count ${RESOURCE_COUNT}



# Grafana backup metrics
# HELP grafana_backup_database_size_bytes Size of Grafana database backup in bytes
# TYPE grafana_backup_database_size_bytes gauge
grafana_backup_database_size_bytes ${GRAFANA_DB_SIZE}

# HELP grafana_backup_success Grafana backup success status (1=success, 0=failed)
# TYPE grafana_backup_success gauge
grafana_backup_success ${GRAFANA_BACKUP_STATUS}

# Prometheus backup metrics
# HELP prometheus_backup_size_bytes Size of Prometheus backup in bytes
# TYPE prometheus_backup_size_bytes gauge
prometheus_backup_size_bytes ${PROMETHEUS_SIZE}

# HELP prometheus_backup_success Prometheus backup success status (1=success, 0=failed)
# TYPE prometheus_backup_success gauge
prometheus_backup_success ${PROMETHEUS_BACKUP_STATUS}

# Loki backup metrics
# HELP loki_backup_size_bytes Size of Loki backup in bytes
# TYPE loki_backup_size_bytes gauge
loki_backup_size_bytes ${LOKI_SIZE}

# HELP loki_backup_success Loki backup success status (1=success, 0=failed)
# TYPE loki_backup_success gauge
loki_backup_success ${LOKI_BACKUP_STATUS}

# Mimir backup metrics
# HELP mimir_backup_size_bytes Size of Mimir backup in bytes
# TYPE mimir_backup_size_bytes gauge
mimir_backup_size_bytes ${MIMIR_SIZE}

# HELP mimir_backup_success Mimir backup success status (1=success, 0=failed)
# TYPE mimir_backup_success gauge
mimir_backup_success ${MIMIR_BACKUP_STATUS}

# Backup operation metrics
# HELP k8s_data_backup_duration_seconds Duration of the last data backup in seconds
# TYPE k8s_data_backup_duration_seconds gauge
k8s_data_backup_duration_seconds ${BACKUP_DURATION}

# HELP k8s_backup_total_count Total number of backup directories
# TYPE k8s_backup_total_count gauge
k8s_backup_total_count ${TOTAL_BACKUP_COUNT}

# HELP k8s_backup_total_files Total number of backup files
# TYPE k8s_backup_total_files gauge
k8s_backup_total_files ${TOTAL_BACKUP_FILES}
EOF

echo "✅ Kubernetes data backup completed successfully!"
echo "📍 Backup location: ${BACKUP_PATH}"
echo "📊 Backup size: $(du -sh "${BACKUP_PATH}" | cut -f1)"
echo "⏱️  Backup duration: ${BACKUP_DURATION} seconds"
echo "📦 Resource files: $(find "${BACKUP_PATH}/resources" -name "*.yaml" | wc -l)"
echo "📁 Total backups: ${TOTAL_BACKUP_COUNT} directories, ${TOTAL_BACKUP_FILES} files"
echo ""
echo "📋 Application Backup Summary:"

echo "📊 Grafana: $(if [ -f "${BACKUP_PATH}/persistent-data/grafana/grafana.db" ]; then echo "✅ Success ($(ls -lh "${BACKUP_PATH}/persistent-data/grafana/grafana.db" | awk '{print $5}'))"; else echo "❌ Failed or unavailable"; fi)"
echo "📈 Prometheus: $(if [ -f "${BACKUP_PATH}/persistent-data/prometheus/prometheus-snapshot.tar.gz" ]; then echo "✅ Snapshot ($(ls -lh "${BACKUP_PATH}/persistent-data/prometheus/prometheus-snapshot.tar.gz" | awk '{print $5}'))"; elif [ -f "${BACKUP_PATH}/persistent-data/prometheus/prometheus-data.tar.gz" ]; then echo "✅ Data ($(ls -lh "${BACKUP_PATH}/persistent-data/prometheus/prometheus-data.tar.gz" | awk '{print $5}'))"; else echo "❌ Failed or unavailable"; fi)"
echo "📝 Loki: $(if [ -f "${BACKUP_PATH}/persistent-data/loki/loki-data.tar.gz" ]; then echo "✅ Success ($(ls -lh "${BACKUP_PATH}/persistent-data/loki/loki-data.tar.gz" | awk '{print $5}'))"; else echo "❌ Failed or unavailable"; fi)"
echo "🎯 Mimir: $(if [ -f "${BACKUP_PATH}/persistent-data/mimir/mimir-data.tar.gz" ]; then echo "✅ Success ($(ls -lh "${BACKUP_PATH}/persistent-data/mimir/mimir-data.tar.gz" | awk '{print $5}'))"; else echo "❌ Failed or unavailable"; fi)"

# List recent backups
echo "📚 Recent backups:"
ls -la "${BACKUP_DIR}" | tail -5