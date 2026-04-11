#!/bin/bash
# BoxCo CI/CD Demo Script
# Demonstrates the full pipeline: bug → fix → Grafana shows improvement

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     BoxCo CI/CD Demo                                       ║${NC}"
echo -e "${CYAN}║     Watch the bug get fixed through the pipeline!          ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

MINIKUBE_IP=$(minikube ip)

# Step 1: Show current state (bug exists)
step_1_show_bug() {
    echo -e "${YELLOW}═══ Step 1: Current State (Bug Exists) ═══${NC}"
    echo ""
    echo -e "Current branch: ${RED}main (scenario-1)${NC}"
    echo -e "The bug: Medium boxes can be ordered despite 0 stock"
    echo ""
    echo -e "${BLUE}Open these URLs to see the bug:${NC}"
    echo "  Sales Portal: http://${MINIKUBE_IP}:30001"
    echo "  Grafana:      http://${MINIKUBE_IP}:30300"
    echo ""
    echo "Try ordering Medium boxes - it will fail!"
    echo "Check Grafana → 'Stock Validation Errors' panel shows failures"
    echo ""
    read -p "Press Enter when ready to proceed to bug fix..."
}

# Step 2: Simulate git push (trigger pipeline)
step_2_trigger_pipeline() {
    echo -e "\n${YELLOW}═══ Step 2: Fix the Bug (Push scenario-2) ═══${NC}"
    echo ""
    echo "Switching to scenario-2 branch (bug fix)..."
    
    git checkout scenario-2
    
    echo -e "${GREEN}✓ Now on scenario-2 branch${NC}"
    echo ""
    echo "Changes in scenario-2:"
    echo "  - Stock validation enforced (bug fixed)"
    echo "  - UI: Gradient background (visual indicator)"
    echo ""
    echo -e "${BLUE}The Jenkins pipeline will now:${NC}"
    echo "  1. Build new Docker images tagged: scenario-2-<commit>"
    echo "  2. Push images to local registry"
    echo "  3. Update k8s/services/*.yaml with new image tags"
    echo "  4. Commit and push the manifest changes"
    echo ""
    read -p "Press Enter to trigger the pipeline..."
    
    # Simulate what Jenkins would do
    echo -e "\n${YELLOW}Building images...${NC}"
    eval $(minikube docker-env)
    
    docker build -t ${MINIKUBE_IP}:30500/sales-api:scenario-2 services/sales-api/ &
    docker build -t ${MINIKUBE_IP}:30500/inventory-api:scenario-2 services/inventory-api/ &
    docker build -t ${MINIKUBE_IP}:30500/shipment-api:scenario-2 services/shipment-api/ &
    docker build -t ${MINIKUBE_IP}:30500/notification-service:scenario-2 services/notification-service/ &
    wait
    
    echo -e "${GREEN}✓ Images built${NC}"
    
    echo -e "\n${YELLOW}Pushing images to registry...${NC}"
    docker push ${MINIKUBE_IP}:30500/sales-api:scenario-2
    docker push ${MINIKUBE_IP}:30500/inventory-api:scenario-2
    docker push ${MINIKUBE_IP}:30500/shipment-api:scenario-2
    docker push ${MINIKUBE_IP}:30500/notification-service:scenario-2
    
    echo -e "${GREEN}✓ Images pushed${NC}"
}

# Step 3: Watch Argo CD sync
step_3_argocd_sync() {
    echo -e "\n${YELLOW}═══ Step 3: Argo CD Auto-Sync ═══${NC}"
    echo ""
    echo -e "${BLUE}Argo CD is watching k8s/services/ directory${NC}"
    echo "When manifests change, it automatically syncs to cluster"
    echo ""
    echo "Watch Argo CD at: http://${MINIKUBE_IP}:30081"
    echo ""
    
    # Trigger rolling update (simulating what Argo CD does)
    echo -e "${YELLOW}Triggering deployment update...${NC}"
    kubectl set image deployment/sales-api sales-api=${MINIKUBE_IP}:30500/sales-api:scenario-2 -n boxco
    kubectl set image deployment/inventory-api inventory-api=${MINIKUBE_IP}:30500/inventory-api:scenario-2 -n boxco
    kubectl set image deployment/shipment-api shipment-api=${MINIKUBE_IP}:30500/shipment-api:scenario-2 -n boxco
    kubectl set image deployment/notification-service notification-service=${MINIKUBE_IP}:30500/notification-service:scenario-2 -n boxco
    
    echo -e "\n${YELLOW}Waiting for rollout...${NC}"
    kubectl rollout status deployment/sales-api -n boxco --timeout=120s
    kubectl rollout status deployment/inventory-api -n boxco --timeout=120s
    kubectl rollout status deployment/shipment-api -n boxco --timeout=120s
    kubectl rollout status deployment/notification-service -n boxco --timeout=120s
    
    echo -e "${GREEN}✓ All services updated${NC}"
}

# Step 4: Verify the fix
step_4_verify_fix() {
    echo -e "\n${YELLOW}═══ Step 4: Verify the Bug is Fixed ═══${NC}"
    echo ""
    echo -e "${GREEN}The bug is now fixed! 🎉${NC}"
    echo ""
    echo "Verify at:"
    echo "  Sales Portal: http://${MINIKUBE_IP}:30001"
    echo "    → Try ordering Medium boxes - now properly shows out of stock"
    echo "    → Notice the gradient background (scenario-2 indicator)"
    echo ""
    echo "  Grafana: http://${MINIKUBE_IP}:30300"
    echo "    → 'Stock Validation Errors' should drop to ZERO"
    echo "    → 'Order Success Rate' should jump to 100%"
    echo ""
}

# Summary
print_demo_summary() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Demo Complete! 🚀                                       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}What we demonstrated:${NC}"
    echo ""
    echo "  1. ${RED}Bug exists${NC} in scenario-1 (main branch)"
    echo "     └─ Medium boxes could be ordered despite 0 stock"
    echo ""
    echo "  2. ${YELLOW}Developer fixes bug${NC} and pushes scenario-2"
    echo "     └─ Jenkins pipeline builds new images"
    echo "     └─ Pipeline updates k8s manifests with new tags"
    echo ""
    echo "  3. ${BLUE}Argo CD detects changes${NC} and syncs automatically"
    echo "     └─ Rolling update deploys new version"
    echo "     └─ Zero downtime deployment"
    echo ""
    echo "  4. ${GREEN}Bug is fixed${NC} - verified in Grafana"
    echo "     └─ Stock validation errors: HIGH → ZERO"
    echo "     └─ Order success rate: ~50% → 100%"
    echo ""
    echo -e "${YELLOW}Try scenario-3 next for the new XL boxes feature!${NC}"
    echo "  git checkout scenario-3"
    echo "  ./scripts/demo-cicd.sh"
    echo ""
}

# Main
main() {
    step_1_show_bug
    step_2_trigger_pipeline
    step_3_argocd_sync
    step_4_verify_fix
    print_demo_summary
}

main "$@"
