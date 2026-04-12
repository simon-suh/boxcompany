#!/bin/bash

echo "=========================================="
echo "BoxCo Kubernetes Teardown"
echo "=========================================="

# Kill port-forwards
echo "🔌 Killing port-forwards..."
pkill -f "port-forward" 2>/dev/null || true

# Stop Minikube
echo "🛑 Stopping Minikube..."
minikube stop 2>/dev/null || true

# Delete cluster
echo "🗑️  Deleting Minikube cluster..."
minikube delete 2>/dev/null || true

# Clean up Docker artifacts
echo "🧹 Cleaning up Docker artifacts..."
docker rm -f minikube-preload-sidecar 2>/dev/null || true
docker rm -f minikube 2>/dev/null || true
docker volume rm minikube 2>/dev/null || true

echo ""
echo "✅ Teardown complete!"
echo ""
