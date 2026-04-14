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
# Step 2: Enable Ingress Addon
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 2: Ingress Controller ═══${NC}"
if minikube addons list | grep -q "ingress.*enabled"; then
    echo -e "${GREEN}✓ Ingress addon already enabled${NC}"
else
    echo "Enabling ingress addon..."
    minikube addons enable ingress
    echo "Waiting for ingress controller to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=120s
    echo -e "${GREEN}✓ Ingress controller ready${NC}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Step 3: Create Namespaces
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 3: Namespaces ═══${NC}"
kubectl create namespace boxco --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace registry --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespaces created${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 4: Setup Local Registry
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 4: Local Registry ═══${NC}"
kubectl apply -f k8s/registry/
echo "Waiting for registry to be ready..."
kubectl wait --for=condition=ready pod -l app=registry -n registry --timeout=120s
echo -e "${GREEN}✓ Registry ready${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 5: Install Prometheus & Grafana
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 5: Prometheus & Grafana ═══${NC}"
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
# Step 6: Install ArgoCD
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 6: ArgoCD ═══${NC}"
if kubectl get deployment argocd-server -n argocd &>/dev/null; then
    echo -e "${GREEN}✓ ArgoCD already installed${NC}"
else
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side
    echo "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
    echo -e "${GREEN}✓ ArgoCD installed${NC}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Step 7: Deploy Infrastructure (Databases, Kafka)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 7: Infrastructure ═══${NC}"

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
# Step 8: Start Port Forwards (Infrastructure Only)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 8: Port Forwards ═══${NC}"

# Kill any existing port forwards
pkill -f "port-forward.*5000" || true
pkill -f "port-forward.*3000" || true
pkill -f "port-forward.*9090" || true
pkill -f "port-forward.*8081" || true
pkill -f "port-forward.*8080" || true
sleep 2

# Start port forwards with nohup (infrastructure + ingress)
nohup kubectl port-forward -n registry svc/registry 5000:5000 > /dev/null 2>&1 &
nohup kubectl port-forward -n observability svc/prometheus-grafana 3000:80 > /dev/null 2>&1 &
nohup kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090 > /dev/null 2>&1 &
nohup kubectl port-forward -n argocd svc/argocd-server 8081:80 > /dev/null 2>&1 &
nohup kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80 > /dev/null 2>&1 &
sleep 3
echo -e "${GREEN}✓ Port forwards started${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 9: Configure Local DNS (Windows Hosts File for WSL2)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 9: Configure Local DNS ═══${NC}"
HOSTS_ENTRY="127.0.0.1  sales.boxco.local shipment.boxco.local inventory.boxco.local"

# Check if running in WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
    echo -e "${YELLOW}WSL2 detected!${NC}"
    echo -e "Please add this line to your ${BLUE}Windows${NC} hosts file:"
    echo -e "${GREEN}${HOSTS_ENTRY}${NC}"
    echo ""
    echo -e "To do this, open ${BLUE}PowerShell as Administrator${NC} and run:"
    echo -e "${YELLOW}Add-Content -Path \"C:\\Windows\\System32\\drivers\\etc\\hosts\" -Value \"${HOSTS_ENTRY}\"${NC}"
    echo ""
else
    # Native Linux - can update /etc/hosts directly
    if grep -q "boxco.local" /etc/hosts; then
        echo -e "${GREEN}✓ Hosts already configured${NC}"
    else
        echo -e "${YELLOW}Adding hostnames to /etc/hosts (requires sudo)...${NC}"
        echo "${HOSTS_ENTRY}" | sudo tee -a /etc/hosts > /dev/null
        echo -e "${GREEN}✓ Hosts configured${NC}"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Step 10: Generate Credentials File
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Step 10: Generate Credentials ═══${NC}"
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "not-yet-available")

cat > credentials.txt << EOF
═══════════════════════════════════════════════════════════════
 BoxCo Local Environment Credentials
═══════════════════════════════════════════════════════════════

 INFRASTRUCTURE
 ─────────────────────────────────────────────────────────────
 Grafana:     http://localhost:3000
              Username: admin
              Password: admin

 Prometheus:  http://localhost:9090
              (no authentication)

 ArgoCD:      http://localhost:8081
              Username: admin
              Password: ${ARGOCD_PASS}

 BOXCO APIS (via Ingress)
 ─────────────────────────────────────────────────────────────
 Sales:       http://sales.boxco.local:8080
 Shipment:    http://shipment.boxco.local:8080
 Inventory:   http://inventory.boxco.local:8080

═══════════════════════════════════════════════════════════════
 Generated: $(date)
═══════════════════════════════════════════════════════════════
EOF

echo -e "${GREEN}✓ Credentials saved to credentials.txt${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Done!
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ✅ Full Stack Setup Complete!                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"

echo -e "\n${BLUE}📄 Credentials saved to:${NC} ./credentials.txt"

echo -e "\n${BLUE}BoxCo APIs (via Ingress):${NC}"
echo -e "  Sales:      http://sales.boxco.local:8080"
echo -e "  Shipment:   http://shipment.boxco.local:8080"
echo -e "  Inventory:  http://inventory.boxco.local:8080"

echo -e "\n${BLUE}Infrastructure:${NC}"
echo -e "  Grafana:    http://localhost:3000  (admin/admin)"
echo -e "  Prometheus: http://localhost:9090"
echo -e "  ArgoCD:     http://localhost:8081  (admin/${ARGOCD_PASS})"

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
    echo -e "\n${BLUE}Run the demo:${NC}"
    echo -e "  ${YELLOW}./scripts/demo-run.sh${NC}        # Scenario 1"
    echo -e "  ${YELLOW}./scripts/demo-run.sh 2${NC}      # Scenario 2"
    echo -e "  ${YELLOW}./scripts/demo-run.sh 3${NC}      # Scenario 3"
else
    echo -e "\n${BLUE}When ready, run:${NC}"
    echo -e "  1. ${YELLOW}./scripts/demo-setup.sh${NC}   # Pre-build images (~10 min)"
    echo -e "  2. ${YELLOW}./scripts/demo-run.sh${NC}     # Deploy Scenario 1"
fi
