#!/bin/bash
# BoxCo CI Build Script
# Replaces Jenkins - builds images, pushes to registry, updates manifests

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     BoxCo CI Pipeline                                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

# Get current branch and commit
BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT=$(git rev-parse --short HEAD)
IMAGE_TAG="${BRANCH}-${COMMIT}"
MINIKUBE_IP=$(minikube ip)
REGISTRY="${MINIKUBE_IP}:30500"

echo -e "\n${YELLOW}Branch:${NC} ${BRANCH}"
echo -e "${YELLOW}Commit:${NC} ${COMMIT}"
echo -e "${YELLOW}Image Tag:${NC} ${IMAGE_TAG}"
echo -e "${YELLOW}Registry:${NC} ${REGISTRY}"

# Point to Minikube's Docker
echo -e "\n${YELLOW}═══ Configuring Docker ═══${NC}"
eval $(minikube docker-env)
echo -e "${GREEN}✓ Using Minikube's Docker daemon${NC}"

# Build images
echo -e "\n${YELLOW}═══ Building Images ═══${NC}"
SERVICES=("sales-api" "inventory-api" "shipment-api" "notification-service")

for svc in "${SERVICES[@]}"; do
    echo -e "${BLUE}Building ${svc}...${NC}"
    docker build -t ${REGISTRY}/${svc}:${IMAGE_TAG} -t ${REGISTRY}/${svc}:latest services/${svc}/
    echo -e "${GREEN}✓ ${svc} built${NC}"
done

# Push images
echo -e "\n${YELLOW}═══ Pushing Images ═══${NC}"
for svc in "${SERVICES[@]}"; do
    echo -e "${BLUE}Pushing ${svc}...${NC}"
    docker push ${REGISTRY}/${svc}:${IMAGE_TAG}
    docker push ${REGISTRY}/${svc}:latest
    echo -e "${GREEN}✓ ${svc} pushed${NC}"
done

# Update manifests with new image tags
echo -e "\n${YELLOW}═══ Updating Kubernetes Manifests ═══${NC}"
for svc in "${SERVICES[@]}"; do
    MANIFEST="k8s/services/${svc}.yaml"
    if [ -f "$MANIFEST" ]; then
        sed -i "s|image: .*/${svc}:.*|image: ${REGISTRY}/${svc}:${IMAGE_TAG}|g" ${MANIFEST}
        echo -e "${GREEN}✓ Updated ${MANIFEST}${NC}"
    fi
done

# Trigger Argo CD sync (or wait for auto-sync)
echo -e "\n${YELLOW}═══ Triggering Deployment ═══${NC}"
kubectl rollout restart deployment sales-api -n boxco
kubectl rollout restart deployment inventory-api -n boxco
kubectl rollout restart deployment shipment-api -n boxco
kubectl rollout restart deployment notification-service -n boxco

echo -e "\n${YELLOW}Waiting for rollouts to complete...${NC}"
kubectl rollout status deployment/sales-api -n boxco --timeout=120s
kubectl rollout status deployment/inventory-api -n boxco --timeout=120s
kubectl rollout status deployment/shipment-api -n boxco --timeout=120s
kubectl rollout status deployment/notification-service -n boxco --timeout=120s

echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✅ CI/CD Pipeline Complete!                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo -e "\n${BLUE}Images pushed:${NC}"
for svc in "${SERVICES[@]}"; do
    echo "  - ${REGISTRY}/${svc}:${IMAGE_TAG}"
done
echo -e "\n${BLUE}View your app:${NC}"
echo "  Sales Portal:     http://localhost:3001"
echo "  Shipment Portal:  http://localhost:3002"
echo "  Inventory Portal: http://localhost:3003"
echo "  Grafana:          http://localhost:3000"
