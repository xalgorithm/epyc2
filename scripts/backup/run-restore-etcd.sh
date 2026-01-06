#!/bin/bash

# Helper script to run ETCD restore interactively in Kubernetes

set -e

echo "🔄 Starting ETCD Restore Process"
echo "================================="
echo ""
echo "⚠️  WARNING: ETCD restore is a critical operation!"
echo "⚠️  This will restore the entire Kubernetes cluster state."
echo "⚠️  Only proceed if you understand the implications."
echo ""
echo "This will create an interactive pod on the control plane to restore ETCD."
echo ""

# Create the restore pod
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: restore-etcd
  namespace: backup
spec:
  restartPolicy: Never
  hostNetwork: true
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
  tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  containers:
  - name: restore
    image: k8s.gcr.io/etcd:3.5.9-0
    stdin: true
    tty: true
    command: ["/bin/sh"]
    args: ["/scripts/restore-etcd-kube.sh"]
    securityContext:
      privileged: true
    env:
    - name: ETCDCTL_API
      value: "3"
    volumeMounts:
    - name: backup-scripts
      mountPath: /scripts
    - name: backup-storage
      mountPath: /backup
    - name: etcd-certs
      mountPath: /etc/kubernetes/pki/etcd
    - name: etcd-data
      mountPath: /var/lib/etcd
  volumes:
  - name: backup-scripts
    configMap:
      name: backup-scripts
      defaultMode: 0755
  - name: backup-storage
    nfs:
      server: 192.168.0.2
      path: /volume1/Apps/kube-backups
  - name: etcd-certs
    hostPath:
      path: /etc/kubernetes/pki/etcd
      type: Directory
  - name: etcd-data
    hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
EOF

echo ""
echo "⏳ Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/restore-etcd -n backup --timeout=60s

echo ""
echo "🚀 Starting interactive restore session..."
echo "   Follow the prompts to select which backup to restore."
echo ""
echo "⚠️  IMPORTANT: Before proceeding with the restore, you must:"
echo "   1. SSH to the control plane node"
echo "   2. Stop kubelet: systemctl stop kubelet"
echo "   3. Stop containerd: systemctl stop containerd"
echo ""

# Attach to the pod
kubectl attach -it restore-etcd -n backup

echo ""
echo "🧹 Cleaning up restore pod..."
kubectl delete pod restore-etcd -n backup --wait=false

echo ""
echo "✅ Restore process completed!"
echo ""
echo "⚠️  Remember to start services on the control plane:"
echo "   systemctl start containerd"
echo "   systemctl start kubelet"

