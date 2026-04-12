#!/bin/bash
set -e

echo "=========================================="
echo "BoxCo Kubernetes Complete Setup"
echo "=========================================="

# ── Phase 1: Cleanup ──────────────────────────────────────────────────────
echo ""
echo "🧹 Phase 1: Cleanup"
echo "-------------------"
pkill -f "port-forward" 2>/dev/null || true
echo "  ✓ Killed old port-forwards"

minikube stop 2>/dev/null || true
echo "  ✓ Stopped Minikube"

minikube delete 2>/dev/null || true
echo "  ✓ Deleted Minikube cluster"

docker rm -f minikube-preload-sidecar minikube 2>/dev/null || true
docker volume rm minikube 2>/dev/null || true
echo "  ✓ Cleaned up Docker artifacts"

# ── Phase 2: Fresh Install ────────────────────────────────────────────────
echo ""
echo "🚀 Phase 2: Infrastructure Setup"
echo "---------------------------------"

minikube start \
  --memory=8192 \
  --cpus=4 \
  --insecure-registry="192.168.49.2:30500" \
  --insecure-registry="10.0.0.0/8"
echo "  ✓ Minikube started"

eval $(minikube docker-env)
MINIKUBE_IP=$(minikube ip)
echo "  ✓ Minikube IP: $MINIKUBE_IP"

# Create namespaces
kubectl create namespace boxco
kubectl create namespace observability
kubectl create namespace registry
kubectl create namespace jenkins
echo "  ✓ Created namespaces"

# Deploy registry
kubectl apply -f k8s/registry/
echo "  ✓ Registry deployed"

# Wait for registry with retry logic
echo "  ⏳ Waiting for registry..."
for i in {1..30}; do
  if kubectl get pods -n registry -l app=registry 2>/dev/null | grep -q Running; then
    kubectl wait --for=condition=ready pod -l app=registry -n registry --timeout=10s 2>/dev/null && break
  fi
  sleep 2
done
echo "  ✓ Registry ready"

# Deploy infrastructure
kubectl apply -f k8s/config/
kubectl apply -f k8s/databases/
kubectl apply -f k8s/kafka/
echo "  ✓ Infrastructure deployed"

echo "  ⏳ Waiting for databases..."
kubectl wait --for=condition=ready pod -l app=postgres -n boxco --timeout=180s
kubectl wait --for=condition=ready pod -l app=dynamodb -n boxco --timeout=180s
kubectl wait --for=condition=ready pod -l app=kafka -n boxco --timeout=180s
echo "  ✓ Databases ready"

# ── Phase 3: Database Initialization ──────────────────────────────────────
echo ""
echo "💾 Phase 3: Database Setup"
echo "--------------------------"

POSTGRES_POD=$(kubectl get pod -n boxco -l app=postgres -o jsonpath='{.items[0].metadata.name}')

# Create database user and database
kubectl exec -n boxco $POSTGRES_POD -- psql -U boxco -d sales -c \
  "CREATE USER boxco_user WITH PASSWORD 'boxco_pass';" 2>/dev/null || echo "  ℹ User already exists"

kubectl exec -n boxco $POSTGRES_POD -- psql -U boxco -d sales -c \
  "CREATE DATABASE boxco_db OWNER boxco_user;" 2>/dev/null || echo "  ℹ Database already exists"

# Create schema
kubectl exec -n boxco $POSTGRES_POD -- psql -U boxco -d boxco_db -c "
CREATE TABLE IF NOT EXISTS customers (
  id VARCHAR PRIMARY KEY,
  name VARCHAR NOT NULL,
  email VARCHAR,
  phone VARCHAR,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orders (
  id VARCHAR PRIMARY KEY,
  order_number VARCHAR UNIQUE NOT NULL,
  customer_id VARCHAR NOT NULL,
  payment_method VARCHAR NOT NULL,
  status VARCHAR NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS order_items (
  id VARCHAR PRIMARY KEY,
  order_id VARCHAR NOT NULL,
  product_id VARCHAR NOT NULL,
  product_name VARCHAR NOT NULL,
  quantity INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS error_reports (
  id VARCHAR PRIMARY KEY,
  order_number VARCHAR,
  reported_by VARCHAR NOT NULL,
  issue_type VARCHAR NOT NULL,
  description TEXT NOT NULL,
  notify_teams TEXT[],
  status VARCHAR NOT NULL DEFAULT 'open',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);"
echo "  ✓ Database schema created"

# Grant permissions
kubectl exec -n boxco $POSTGRES_POD -- psql -U boxco -d boxco_db -c "
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO boxco_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO boxco_user;
GRANT USAGE ON SCHEMA public TO boxco_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO boxco_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO boxco_user;"
echo "  ✓ Database permissions granted"

# ── Phase 4: Monitoring Stack ─────────────────────────────────────────────
echo ""
echo "📊 Phase 4: Monitoring Setup"
echo "----------------------------"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update > /dev/null
echo "  ✓ Helm repo updated"

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --values grafana-values.yaml \
  --wait \
  --timeout 5m
echo "  ✓ Prometheus & Grafana installed"

kubectl apply -f k8s/observability-servicemonitor.yaml
kubectl apply -f k8s/grafana-dashboards/grafana-dashboard-configmap.yaml
echo "  ✓ ServiceMonitors deployed"

# ── Phase 5: Application Services ─────────────────────────────────────────
echo ""
echo "🏗️  Phase 5: Building & Deploying Services"
echo "-------------------------------------------"

./build-and-deploy.sh
echo "  ✓ Images built and pushed"

kubectl apply -f k8s/services/
echo "  ✓ Services deployed"

# Patch service ports for Prometheus
kubectl patch svc sales-api -n boxco -p '{"spec":{"ports":[{"name":"http","port":3001,"protocol":"TCP","targetPort":3001,"nodePort":30001}]}}'
kubectl patch svc inventory-api -n boxco -p '{"spec":{"ports":[{"name":"http","port":3003,"protocol":"TCP","targetPort":3003,"nodePort":30003}]}}'
kubectl patch svc shipment-api -n boxco -p '{"spec":{"ports":[{"name":"http","port":3002,"protocol":"TCP","targetPort":3002,"nodePort":30002}]}}'
echo "  ✓ Service ports configured"

echo "  ⏳ Waiting for services..."
kubectl wait --for=condition=ready pod -l app=sales-api -n boxco --timeout=120s
kubectl wait --for=condition=ready pod -l app=inventory-api -n boxco --timeout=120s
kubectl wait --for=condition=ready pod -l app=shipment-api -n boxco --timeout=120s
kubectl wait --for=condition=ready pod -l app=notification-service -n boxco --timeout=120s
echo "  ✓ All services ready"

# ── Phase 6: Final Configuration ──────────────────────────────────────────
echo ""
echo "🔧 Phase 6: Final Configuration"
echo "--------------------------------"

kubectl delete pod -n observability -l app.kubernetes.io/name=prometheus 2>/dev/null || true
echo "  ✓ Restarted Prometheus"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n observability --timeout=180s 2>/dev/null || true

# Set up port-forwards for all services
kubectl port-forward -n boxco svc/sales-api 3001:3001 > /dev/null 2>&1 &
kubectl port-forward -n boxco svc/inventory-api 3003:3003 > /dev/null 2>&1 &
kubectl port-forward -n boxco svc/shipment-api 3002:3002 > /dev/null 2>&1 &
kubectl port-forward -n registry svc/registry 5000:5000 > /dev/null 2>&1 &
kubectl port-forward -n observability svc/prometheus-grafana 3000:80 > /dev/null 2>&1 &
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090 > /dev/null 2>&1 &
sleep 5
echo "  ✓ Port-forwards established"

# ── Complete ──────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "✅ Setup Complete!"
echo "=========================================="
echo ""
echo "📍 Access Points:"
echo "  Sales Portal:    http://localhost:3001"
echo "  Inventory Portal: http://localhost:3003"
echo "  Shipment Portal:  http://localhost:3002"
echo "  Registry:        http://localhost:5000/v2/_catalog"
echo "  Grafana:         http://localhost:3000 (admin/admin)"
echo "  Prometheus:      http://localhost:9090"
echo ""
echo "🔍 Verify:"
echo "  kubectl get pods -n boxco"
echo "  kubectl get pods -n observability"
echo ""
