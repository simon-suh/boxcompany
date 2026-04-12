#!/bin/bash
# BoxCo CI Build Script
# Builds images, pushes to registry, updates manifests, commits to git
# ArgoCD auto-syncs when it detects manifest changes
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
    docker build -t ${REGISTRY}/${svc}:${IMAGE_TAG} services/${svc}/
    echo -e "${GREEN}✓ ${svc} built${NC}"
done

# Push images
echo -e "\n${YELLOW}═══ Pushing Images ═══${NC}"
for svc in "${SERVICES[@]}"; do
    echo -e "${BLUE}Pushing ${svc}...${NC}"
    docker push ${REGISTRY}/${svc}:${IMAGE_TAG}
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

# Commit and push manifest changes to git
echo -e "\n${YELLOW}═══ Committing Manifest Changes to Git ═══${NC}"
git add k8s/services/*.yaml
git commit -m "ci: update image tags to ${IMAGE_TAG}" || echo -e "${YELLOW}No changes to commit${NC}"
git push origin ${BRANCH}
echo -e "${GREEN}✓ Pushed to origin/${BRANCH}${NC}"

# ArgoCD will auto-sync, but show status
echo -e "\n${YELLOW}═══ ArgoCD Status ═══${NC}"
echo -e "${BLUE}ArgoCD will detect manifest changes and auto-sync.${NC}"
echo -e "${BLUE}Watch progress at: http://localhost:8081${NC}"

# Wait for pods to update (ArgoCD sync)
echo -e "\n${YELLOW}═══ Waiting for Deployment ═══${NC}"
sleep 5
kubectl rollout status deployment/sales-api -n boxco --timeout=120s
kubectl rollout status deployment/inventory-api -n boxco --timeout=120s
kubectl rollout status deployment/shipment-api -n boxco --timeout=120s
kubectl rollout status deployment/notification-service -n boxco --timeout=120s

echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✅ CI/CD Pipeline Complete!                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"

echo -e "\n${BLUE}Images deployed:${NC}"
for svc in "${SERVICES[@]}"; do
    echo "  - ${REGISTRY}/${svc}:${IMAGE_TAG}"
done

echo -e "\n${BLUE}View your app:${NC}"
echo "  Sales Portal:     http://localhost:3001"
echo "  Shipment Portal:  http://localhost:3002"
echo "  Inventory Portal: http://localhost:3003"
echo "  ArgoCD:           http://localhost:8081"
echo "  Grafana:          http://localhost:3000"
