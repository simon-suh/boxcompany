#!/bin/bash
# Pre-build all scenario images for fast demo deployment
set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Pre-building All Scenario Images                       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

MINIKUBE_IP=$(minikube ip)
REGISTRY="${MINIKUBE_IP}:30500"
SERVICES=("sales-api" "inventory-api" "shipment-api" "notification-service")
CURRENT_BRANCH=$(git branch --show-current)

echo -e "\n${YELLOW}Registry:${NC} ${REGISTRY}"

# Configure Docker to use Minikube
eval $(minikube docker-env)

# Build scenario-1 images (from main)
echo -e "\n${YELLOW}═══ Building Scenario 1 Images (main) ═══${NC}"
git checkout main
for svc in "${SERVICES[@]}"; do
    echo -e "${BLUE}Building ${svc}:scenario-1...${NC}"
    docker build -t ${REGISTRY}/${svc}:scenario-1 services/${svc}/
    docker push ${REGISTRY}/${svc}:scenario-1
    echo -e "${GREEN}✓ ${svc}:scenario-1${NC}"
done

# Build scenario-2 images
echo -e "\n${YELLOW}═══ Building Scenario 2 Images ═══${NC}"
git checkout scenario-2
for svc in "${SERVICES[@]}"; do
    echo -e "${BLUE}Building ${svc}:scenario-2...${NC}"
    docker build -t ${REGISTRY}/${svc}:scenario-2 services/${svc}/
    docker push ${REGISTRY}/${svc}:scenario-2
    echo -e "${GREEN}✓ ${svc}:scenario-2${NC}"
done

# Build scenario-3 images
echo -e "\n${YELLOW}═══ Building Scenario 3 Images ═══${NC}"
git checkout scenario-3
for svc in "${SERVICES[@]}"; do
    echo -e "${BLUE}Building ${svc}:scenario-3...${NC}"
    docker build -t ${REGISTRY}/${svc}:scenario-3 services/${svc}/
    docker push ${REGISTRY}/${svc}:scenario-3
    echo -e "${GREEN}✓ ${svc}:scenario-3${NC}"
done

# Return to original branch
git checkout ${CURRENT_BRANCH}

echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✅ All Images Pre-built!                               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo -e "\n${BLUE}Available images:${NC}"
echo "  scenario-1: ${REGISTRY}/*:scenario-1"
echo "  scenario-2: ${REGISTRY}/*:scenario-2"
echo "  scenario-3: ${REGISTRY}/*:scenario-3"
echo -e "\n${YELLOW}Now run: ./scripts/demo-run.sh${NC}"
