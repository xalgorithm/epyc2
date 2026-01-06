#!/bin/bash

# Helper script to run Radarr restore interactively in Kubernetes

set -e

echo "🔄 Starting Radarr Restore Process"
echo "==================================="
echo ""
echo "This will create an interactive pod to restore Radarr configuration."
echo ""

# Create the restore pod
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: restore-radarr
  namespace: backup
spec:
  restartPolicy: Never
  securityContext:
    fsGroup: 1000
  containers:
  - name: restore
    image: alpine:3.18
    stdin: true
    tty: true
    command: ["/bin/sh"]
    args: ["/scripts/restore-radarr.sh"]
    volumeMounts:
    - name: backup-scripts
      mountPath: /scripts
    - name: backup-storage
      mountPath: /backup
    - name: radarr-config
      mountPath: /config
  volumes:
  - name: backup-scripts
    configMap:
      name: backup-scripts
      defaultMode: 0755
  - name: backup-storage
    nfs:
      server: 192.168.0.2
      path: /volume1/Apps/kube-backups
  - name: radarr-config
    nfs:
      server: 192.168.0.2
      path: /volume1/Apps/radarr
EOF

echo ""
echo "⏳ Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/restore-radarr -n backup --timeout=60s

echo ""
echo "🚀 Starting interactive restore session..."
echo "   Follow the prompts to select which backup to restore."
echo ""

# Attach to the pod
kubectl attach -it restore-radarr -n backup

echo ""
echo "🧹 Cleaning up restore pod..."
kubectl delete pod restore-radarr -n backup --wait=false

echo ""
echo "✅ Restore process completed!"

