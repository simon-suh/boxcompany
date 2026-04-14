#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# BoxCo Fast Demo Script (uses pre-built images)
# Usage:
#   ./scripts/demo-run.sh      - Deploy scenario-1 (initial setup)
#   ./scripts/demo-run.sh 2    - Magic Moment 1: Deploy scenario-2 (bug fix)
#   ./scripts/demo-run.sh 3    - Magic Moment 2: Deploy scenario-3 (XL boxes)
#
# Prerequisites: Run ./scripts/demo-setup.sh first to pre-build images
#
# NOTE: This script uses Ingress for stable API access - no port-forwards needed!
#       Argo CD auto-sync is ENABLED - true GitOps workflow.
# ═══════════════════════════════════════════════════════════════════════════════
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCENARIO=${1:-1}

MINIKUBE_IP=$(minikube ip)
REGISTRY="${MINIKUBE_IP}:30500"
SERVICES=("sales-api" "inventory-api" "shipment-api" "notification-service")
IMAGE_TAG="scenario-${SCENARIO}"

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
    echo -e "${RED}Usage: ./scripts/demo-run.sh [1|2|3]${NC}"
    echo "  1 - Deploy scenario-1 (default)"
    echo "  2 - Deploy scenario-2 (bug fix)"
    echo "  3 - Deploy scenario-3 (XL boxes)"
    exit 1
    ;;
esac

# ═══════════════════════════════════════════════════════════════════════════════
# Update Manifests with Pre-built Image Tags
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Updating Manifests ═══${NC}"
for svc in "${SERVICES[@]}"; do
    MANIFEST="k8s/services/${svc}.yaml"
    if [ -f "$MANIFEST" ]; then
        sed -i "s|image: .*/${svc}:.*|image: ${REGISTRY}/${svc}:${IMAGE_TAG}|g" ${MANIFEST}
        sed -i "s|value: "[0-9]"|value: "${SCENARIO}"|g" ${MANIFEST}
        sed -i "s|value: \"[0-9]\"|value: \"${SCENARIO}\"|g" ${MANIFEST}
        echo -e "${GREEN}✓ ${svc} → ${IMAGE_TAG}${NC}"
    fi
done

# ═══════════════════════════════════════════════════════════════════════════════
# Apply Manifests (including Ingress)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Applying Manifests ═══${NC}"
kubectl apply -f k8s/services/
echo -e "${GREEN}✓ Manifests applied (including Ingress)${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Wait for Deployments
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Waiting for Deployments ═══${NC}"
kubectl rollout status deployment/sales-api -n boxco --timeout=60s
kubectl rollout status deployment/inventory-api -n boxco --timeout=60s
kubectl rollout status deployment/shipment-api -n boxco --timeout=60s
kubectl rollout status deployment/notification-service -n boxco --timeout=60s
echo -e "${GREEN}✓ All deployments ready${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Verify Ingress is Ready
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Verifying Ingress ═══${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=60s
echo -e "${GREEN}✓ Ingress controller ready${NC}"

# Verify Ingress resource exists
if kubectl get ingress boxco-ingress -n boxco &>/dev/null; then
    echo -e "${GREEN}✓ BoxCo Ingress configured${NC}"
else
    echo -e "${RED}✗ Ingress not found - applying now...${NC}"
    kubectl apply -f k8s/services/ingress.yaml
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Enable Argo CD Auto-Sync (GitOps!)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}═══ Enabling Argo CD Auto-Sync ═══${NC}"
kubectl patch application boxco-services -n argocd --type=merge -p '{
  "spec": {
    "syncPolicy": {
      "automated": {
        "prune": true,
        "selfHeal": true
      }
    }
  }
}' 2>/dev/null || echo -e "${YELLOW}⚠ ArgoCD application not found (optional)${NC}"
echo -e "${GREEN}✓ Argo CD auto-sync enabled${NC}"

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
    echo -e "\n${YELLOW}Next: Run ./scripts/demo-run.sh 2 for Magic Moment 1${NC}"
    ;;
  2)
    echo -e "${GREEN}║     ✅ Scenario 2 Deployed!                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${BLUE}Changes:${NC}"
    echo "  • Background: White → Gradient"
    echo "  • Tag: Scenario 1 → Scenario 2"
    echo "  • Bug fixed: Out-of-stock orders now BLOCKED"
    echo -e "\n${YELLOW}Next: Run ./scripts/demo-run.sh 3 for Magic Moment 2${NC}"
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

echo -e "\n${BLUE}View your app (via Ingress - stable, no port-forwards!):${NC}"
echo "  Sales Portal:     http://sales.boxco.local"
echo "  Shipment Portal:  http://shipment.boxco.local"
echo "  Inventory Portal: http://inventory.boxco.local"
echo ""
echo -e "${BLUE}Infrastructure:${NC}"
echo "  ArgoCD:           http://localhost:8081"
echo "  Grafana:          http://localhost:3000"
echo ""
echo -e "${GREEN}✨ Argo CD auto-sync is ON - pods can restart without breaking access!${NC}"
