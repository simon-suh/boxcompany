#!/bin/bash
# BoxCo Demo Script
# Usage:
#   ./scripts/demo.sh      - Deploy scenario-1 (initial setup)
#   ./scripts/demo.sh 2    - Magic Moment 1: Merge & deploy scenario-2 (bug fix)
#   ./scripts/demo.sh 3    - Magic Moment 2: Merge & deploy scenario-3 (XL boxes)
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCENARIO=${1:-1}
BRANCH=$(git branch --show-current)

# ═══════════════════════════════════════════════════════════════════════════════
# Header
# ═══════════════════════════════════════════════════════════════════════════════
case $SCENARIO in
  1)
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     BoxCo Demo: Deploying Scenario 1 (Initial Setup)      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    ;;
  2)
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Magic Moment 1: Deploying Scenario 2 (Bug Fix)        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    ;;
  3)
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Magic Moment 2: Deploying Scenario 3 (XL Boxes)       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    ;;
  *)
    echo -e "${RED}Usage: ./scripts/demo.sh [1|2|3]${NC}"
    echo "  1 - Deploy scenario-1 (default)"
    echo "  2 - Merge & deploy scenario-2 (bug fix)"
    echo "  3 - Merge & deploy scenario-3 (XL boxes)"
    exit 1
    ;;
esac

# ═══════════════════════════════════════════════════════════════════════════════
# Merge (for scenarios 2 and 3)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$SCENARIO" = "2" ]; then
  echo -e "\n${YELLOW}═══ Merging Scenario 2 ═══${NC}"
  git merge -X theirs scenario-2 -m "Deploy scenario-2: fix stock validation bug"
  echo -e "${GREEN}✓ Merged scenario-2${NC}"
elif [ "$SCENARIO" = "3" ]; then
  echo -e "\n${YELLOW}═══ Merging Scenario 3 ═══${NC}"
  git merge -X theirs scenario-3 -m "Deploy scenario-3: add XL boxes"
  echo -e "${GREEN}✓ Merged scenario-3${NC}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Build Images
# ═══════════════════════════════════════════════════════════════════════════════
COMMIT=$(git rev-parse --short HEAD)
IMAGE_TAG="${BRANCH}-${COMMIT}"
MINIKUBE_IP=$(minikube ip)
REGISTRY="${MINIKUBE_IP}:30500"

echo -e "\n${YELLOW}Branch:${NC} ${BRANCH}"
echo -e "${YELLOW}Commit:${NC} ${COMMIT}"
echo -e "${YELLOW}Image Tag:${NC} ${IMAGE_TAG}"
echo -e "${YELLOW}Registry:${NC} ${REGISTRY}"

echo -e "\n${YELLOW}═══ Configuring Docker ═══${NC}"
eval $(minikube docker-env)
echo -e "${GREEN}✓ Using Minikube's Docker daemon${NC}"

echo -e "\n${YELLOW}═══ Building Images ═══${NC}"
SERVICES=("sales-api" "inventory-api" "shipment-api" "notification-service")

for svc in "${SERVICES[@]}"; do
    echo -e "${BLUE}Building ${svc}...${NC}"
    docker build -t ${REGISTRY}/${svc}:${IMAGE_TAG} services/${svc}/
    echo -e "${GREEN}✓ ${svc} built${NC}"
done

# ═══════════════════════════════════════════════════════════════════════════════
# Push Images
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Pushing Images ═══${NC}"
for svc in "${SERVICES[@]}"; do
    echo -e "${BLUE}Pushing ${svc}...${NC}"
    docker push ${REGISTRY}/${svc}:${IMAGE_TAG}
    echo -e "${GREEN}✓ ${svc} pushed${NC}"
done

# ═══════════════════════════════════════════════════════════════════════════════
# Update Manifests
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Updating Kubernetes Manifests ═══${NC}"
for svc in "${SERVICES[@]}"; do
    MANIFEST="k8s/services/${svc}.yaml"
    if [ -f "$MANIFEST" ]; then
        sed -i "s|image: .*/${svc}:.*|image: ${REGISTRY}/${svc}:${IMAGE_TAG}|g" ${MANIFEST}
        echo -e "${GREEN}✓ Updated ${MANIFEST}${NC}"
    fi
done

# ═══════════════════════════════════════════════════════════════════════════════
# Commit and Push to Git
# ═══════════════════════════════════════════════════════════════════════════════
# Apply manifests directly for immediate deployment
echo -e "\n${YELLOW}═══ Applying Manifests ═══${NC}"
kubectl apply -f k8s/services/
echo -e "${GREEN}✓ Manifests applied${NC}"

echo -e "\n${YELLOW}═══ Committing Manifest Changes to Git ═══${NC}"
git add k8s/services/*.yaml
git commit -m "ci: update image tags to ${IMAGE_TAG}" || echo -e "${YELLOW}No changes to commit${NC}"
git push origin ${BRANCH}
echo -e "${GREEN}✓ Pushed to origin/${BRANCH}${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Wait for ArgoCD & Deployments
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Waiting for ArgoCD Sync ═══${NC}"
echo -e "${BLUE}ArgoCD will detect manifest changes and auto-sync.${NC}"
sleep 10

echo -e "\n${YELLOW}═══ Waiting for Deployments ═══${NC}"
kubectl rollout status deployment/sales-api -n boxco --timeout=120s
kubectl rollout status deployment/inventory-api -n boxco --timeout=120s
kubectl rollout status deployment/shipment-api -n boxco --timeout=120s
kubectl rollout status deployment/notification-service -n boxco --timeout=120s

# Wait for ArgoCD to finish syncing
echo -e "${BLUE}Waiting for pods to stabilize...${NC}"
sleep 10

# ═══════════════════════════════════════════════════════════════════════════════
# Port Forwards
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Setting Up Port Forwards ═══${NC}"
pkill -f "port-forward.*3001" || true
pkill -f "port-forward.*3002" || true
pkill -f "port-forward.*3003" || true
sleep 5

# Verify pods are running
echo -e "${BLUE}Verifying pods are ready...${NC}"
kubectl wait --for=condition=ready pod -l app=sales-api -n boxco --timeout=60s
kubectl wait --for=condition=ready pod -l app=inventory-api -n boxco --timeout=60s
kubectl wait --for=condition=ready pod -l app=shipment-api -n boxco --timeout=60s

kubectl port-forward -n boxco svc/sales-api 3001:3001 &
kubectl port-forward -n boxco svc/inventory-api 3003:3003 &
kubectl port-forward -n boxco svc/shipment-api 3002:3002 &
sleep 5
echo -e "${GREEN}✓ Port forwards ready${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Success Message
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
case $SCENARIO in
  1)
    echo -e "${GREEN}║     ✅ Scenario 1 Deployed!                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${BLUE}Current State:${NC}"
    echo "  • Background: White"
    echo "  • Bug: Out-of-stock orders ARE allowed (medium box)"
    echo -e "\n${YELLOW}Next: Run ./scripts/demo.sh 2 for Magic Moment 1${NC}"
    ;;
  2)
    echo -e "${GREEN}║     ✅ Scenario 2 Deployed!                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${BLUE}Changes:${NC}"
    echo "  • Background: White → Gradient"
    echo "  • Tag: Scenario 1 → Scenario 2"
    echo "  • Bug fixed: Out-of-stock orders now BLOCKED"
    echo -e "\n${YELLOW}Next: Run ./scripts/demo.sh 3 for Magic Moment 2${NC}"
    ;;
  3)
    echo -e "${GREEN}║     ✅ Scenario 3 Deployed!                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${BLUE}Changes:${NC}"
    echo "  • Background: Gradient → Gray"
    echo "  • Tag: Scenario 2 → Scenario 3"
    echo "  • New feature: XL boxes now available"
    ;;
esac

echo -e "\n${BLUE}View your app:${NC}"
echo "  Sales Portal:     http://localhost:3001"
echo "  Inventory Portal: http://localhost:3003"
echo "  Shipment Portal:  http://localhost:3002"
echo "  ArgoCD:           http://localhost:8081"
echo "  Grafana:          http://localhost:3000"
