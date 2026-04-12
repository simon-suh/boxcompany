#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BoxCo Full Stack Setup
# One-time setup script for the complete infrastructure
# Run this ONCE before running demo-setup.sh and demo-run.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse flags
AUTO_YES=false
if [[ "$1" == "-y" || "$1" == "--yes" ]]; then
    AUTO_YES=true
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          BoxCo Full Stack Setup                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 1: Start Minikube
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 1: Minikube ═══${NC}"
if minikube status | grep -q "Running"; then
    echo -e "${GREEN}✓ Minikube already running${NC}"
else
    echo "Starting Minikube..."
    minikube start --memory=4096 --cpus=2
    echo -e "${GREEN}✓ Minikube started${NC}"
fi

# Point docker to minikube
eval $(minikube docker-env)

# ═══════════════════════════════════════════════════════════════════════════════
# Step 2: Create Namespaces
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 2: Namespaces ═══${NC}"
kubectl create namespace boxco --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace registry --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespaces created${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 3: Setup Local Registry
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 3: Local Registry ═══${NC}"
kubectl apply -f k8s/registry/
echo "Waiting for registry to be ready..."
kubectl wait --for=condition=ready pod -l app=registry -n registry --timeout=120s
echo -e "${GREEN}✓ Registry ready${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 4: Install Prometheus & Grafana
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 4: Prometheus & Grafana ═══${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

if helm list -n observability | grep -q prometheus; then
    echo -e "${GREEN}✓ Prometheus already installed${NC}"
else
    helm install prometheus prometheus-community/kube-prometheus-stack \
        -n observability \
        -f grafana-values.yaml \
        --wait
    echo -e "${GREEN}✓ Prometheus & Grafana installed${NC}"
fi

# Apply ServiceMonitors
kubectl apply -f k8s/observability/

# ═══════════════════════════════════════════════════════════════════════════════
# Step 5: Install ArgoCD
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 5: ArgoCD ═══${NC}"
if kubectl get deployment argocd-server -n argocd &>/dev/null; then
    echo -e "${GREEN}✓ ArgoCD already installed${NC}"
else
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    echo "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
    echo -e "${GREEN}✓ ArgoCD installed${NC}"
fi

# Disable ArgoCD auto-sync (we use it as dashboard only)
kubectl patch application boxco-services -n argocd --type=merge -p '{"spec":{"syncPolicy":null}}' 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════════════
# Step 6: Deploy Infrastructure (Databases, Kafka)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 6: Infrastructure ═══${NC}"

# Apply config first (postgres init script)
kubectl apply -f k8s/config/
echo -e "${GREEN}✓ Config applied${NC}"

# Apply Kafka/Zookeeper
kubectl apply -f k8s/kafka/
echo "Waiting for Kafka to be ready..."
kubectl wait --for=condition=ready pod -l app=zookeeper -n boxco --timeout=120s
kubectl wait --for=condition=ready pod -l app=kafka -n boxco --timeout=120s
echo -e "${GREEN}✓ Kafka ready${NC}"

# Apply Databases
kubectl apply -f k8s/databases/postgres.yaml
kubectl apply -f k8s/databases/dynamodb.yaml
echo "Waiting for databases to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres -n boxco --timeout=120s
kubectl wait --for=condition=ready pod -l app=dynamodb -n boxco --timeout=120s
echo -e "${GREEN}✓ Databases ready${NC}"

# Run DynamoDB init job
kubectl delete job dynamodb-init -n boxco --ignore-not-found
kubectl apply -f k8s/databases/dynamodb-init-job.yaml
echo "Waiting for DynamoDB initialization..."
kubectl wait --for=condition=complete job/dynamodb-init -n boxco --timeout=180s
echo -e "${GREEN}✓ DynamoDB initialized${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 7: Start Port Forwards
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 7: Port Forwards ═══${NC}"

# Kill any existing port forwards
pkill -f "port-forward.*5000" || true
pkill -f "port-forward.*3000" || true
pkill -f "port-forward.*9090" || true
pkill -f "port-forward.*8081" || true
sleep 2

# Start port forwards with nohup
nohup kubectl port-forward -n registry svc/registry 5000:5000 > /dev/null 2>&1 &
nohup kubectl port-forward -n observability svc/prometheus-grafana 3000:80 > /dev/null 2>&1 &
nohup kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090 > /dev/null 2>&1 &
nohup kubectl port-forward -n argocd svc/argocd-server 8081:80 > /dev/null 2>&1 &
sleep 3
echo -e "${GREEN}✓ Port forwards started${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Done!
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ✅ Full Stack Setup Complete!                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"

echo -e "\n${BLUE}Infrastructure URLs:${NC}"
echo -e "  Grafana:    http://localhost:3000  (admin/admin)"
echo -e "  Prometheus: http://localhost:9090"
echo -e "  ArgoCD:     http://localhost:8081"

ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
if [ -n "$ARGOCD_PASS" ]; then
    echo -e "              (admin/${ARGOCD_PASS})"
fi


echo ""
if [[ "$AUTO_YES" == true ]]; then
    BUILD_IMAGES="y"
else
    read -p "Do you want to build scenario images now? (~10 min) [y/N]: " BUILD_IMAGES
fi

if [[ "$BUILD_IMAGES" =~ ^[Yy]$ ]]; then
    echo -e "\n${YELLOW}Building scenario images...${NC}"
    if [[ "$AUTO_YES" == true ]]; then
        ./scripts/demo-setup.sh -y
    else
        ./scripts/demo-setup.sh
    fi
    echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          ✅ Ready to Demo!                                 ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${BLUE}Open browser tabs:${NC}"
    echo -e "  - http://localhost:3001 (Sales)"
    echo -e "  - http://localhost:3002 (Shipment)"
    echo -e "  - http://localhost:3003 (Inventory)"
    echo -e "  - http://localhost:3000 (Grafana)"
    echo -e "\n${BLUE}Run the demo:${NC}"
    echo -e "  ${YELLOW}./scripts/demo-run.sh${NC}        # Scenario 1"
    echo -e "  ${YELLOW}./scripts/demo-run.sh 2${NC}      # Scenario 2"
    echo -e "  ${YELLOW}./scripts/demo-run.sh 3${NC}      # Scenario 3"
else
    echo -e "\n${BLUE}When ready, run:${NC}"
    echo -e "  1. ${YELLOW}./scripts/demo-setup.sh${NC}   # Pre-build images (~10 min)"
    echo -e "  2. ${YELLOW}./scripts/demo-run.sh${NC}     # Deploy Scenario 1"
fi
