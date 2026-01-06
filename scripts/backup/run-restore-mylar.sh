#!/bin/bash

# Helper script to run Mylar restore interactively in Kubernetes

set -e

echo "🔄 Starting Mylar Restore Process"
echo "=================================="
echo ""
echo "This will create an interactive pod to restore Mylar configuration."
echo ""

# Create the restore pod
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: restore-mylar
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
    args: ["/scripts/restore-mylar.sh"]
    volumeMounts:
    - name: backup-scripts
      mountPath: /scripts
    - name: backup-storage
      mountPath: /backup
    - name: mylar-config
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
  - name: mylar-config
    nfs:
      server: 192.168.0.2
      path: /volume1/Apps/mylar
EOF

echo ""
echo "⏳ Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/restore-mylar -n backup --timeout=60s

echo ""
echo "🚀 Starting interactive restore session..."
echo "   Follow the prompts to select which backup to restore."
echo ""

# Attach to the pod
kubectl attach -it restore-mylar -n backup

echo ""
echo "🧹 Cleaning up restore pod..."
kubectl delete pod restore-mylar -n backup --wait=false

echo ""
echo "✅ Restore process completed!"

