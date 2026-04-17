#!/bin/bash
# ═════════════════════════════════════════════════════════════════════════════
# BoxCo Demo Start
# Run this on the day of the demo, after your machine boots up.
# Takes ~2-3 minutes.
#
# What this does:
#   1. Verifies Minikube is running
#   2. Restarts all port-forwards
#   3. Restarts smee webhook bridge (if configured)
#   4. Verifies all services are healthy
#   5. Prints access URLs
#
# Usage:
#   ./scripts/start.sh
# ═════════════════════════════════════════════════════════════════════════════
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

header() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════╗\n║  $1\n╚══════════════════════════════════════════════════╝${NC}"
}
step() { echo -e "\n${YELLOW}─── $1 ───${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

header "BoxCo Demo Start"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — Minikube
# ═════════════════════════════════════════════════════════════════════════════
step "Step 1/4 — Minikube"
if minikube status 2>/dev/null | grep -q "Running"; then
    ok "Minikube running"
else
    warn "Minikube not running — starting..."
    minikube start --insecure-registry="192.168.49.2:30500"
    ok "Minikube started"
fi
MINIKUBE_IP=$(minikube ip)
ok "Node IP: ${MINIKUBE_IP}"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — Port Forwards
# ═════════════════════════════════════════════════════════════════════════════
step "Step 2/4 — Port forwards"
pkill -f "port-forward" 2>/dev/null || true
sleep 2

nohup kubectl port-forward -n registry      svc/registry                               5000:5000 >/dev/null 2>&1 &
nohup kubectl port-forward -n observability  svc/prometheus-grafana                    3000:80   >/dev/null 2>&1 &
nohup kubectl port-forward -n observability  svc/prometheus-kube-prometheus-prometheus 9090:9090 >/dev/null 2>&1 &
nohup kubectl port-forward -n argocd         svc/argocd-server                         8081:80   >/dev/null 2>&1 &
nohup kubectl port-forward -n ingress-nginx  svc/ingress-nginx-controller              8080:80   >/dev/null 2>&1 &
nohup kubectl port-forward -n jenkins        svc/jenkins                               8082:8080 >/dev/null 2>&1 &
sleep 3
ok "Port forwards started"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — Smee webhook bridge
# ═════════════════════════════════════════════════════════════════════════════
step "Step 3/4 — Smee webhook bridge"
if kubectl get configmap jenkins-smee -n jenkins &>/dev/null; then
    SMEE_URL=$(kubectl get configmap jenkins-smee -n jenkins -o jsonpath="{.data.url}")
    # Restart smee pod to ensure fresh connection
    kubectl rollout restart deployment/smee-client -n jenkins > /dev/null 2>&1 || true
    ok "Smee webhook bridge restarted: ${SMEE_URL}"
else
    warn "Smee not configured — webhooks won't work"
    warn "Builds can still be triggered manually in Jenkins UI"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — Health checks
# ═════════════════════════════════════════════════════════════════════════════
step "Step 4/4 — Health checks"

# Check registry has images
CATALOG=$(curl -s http://localhost:5000/v2/_catalog 2>/dev/null || echo "{}")
if echo "$CATALOG" | grep -q "sales-api"; then
    ok "Registry has images"
else
    warn "Registry is empty — images were lost (Minikube was deleted)"
    warn "Run Jenkins builds for main, scenario-2, scenario-3 to rebuild images"
fi

# Check boxco pods
UNHEALTHY=$(kubectl get pods -n boxco --no-headers 2>/dev/null | \
    grep -v "Running\|Completed" | wc -l)
if [ "$UNHEALTHY" -eq 0 ]; then
    ok "All boxco pods healthy"
else
    warn "${UNHEALTHY} pod(s) not ready in boxco namespace"
    warn "Run: kubectl get pods -n boxco"
fi

# Check Jenkins
JENKINS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    http://localhost:8082/login 2>/dev/null || echo "0")
if [ "$JENKINS_STATUS" == "200" ]; then
    ok "Jenkins UI reachable"
else
    warn "Jenkins UI not responding yet — may still be starting up"
    warn "Try: http://localhost:8082 in a minute"
fi

# Check Argo CD
ARGOCD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    http://localhost:8081 2>/dev/null || echo "0")
if [ "$ARGOCD_STATUS" == "200" ]; then
    ok "Argo CD UI reachable"
else
    warn "Argo CD UI not responding — check port-forward"
fi

# ═════════════════════════════════════════════════════════════════════════════
# Done
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ Demo environment ready!                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Access URLs:${NC}"
echo "  Sales API   → http://sales.boxco.local:8080"
echo "  Shipment    → http://shipment.boxco.local:8080"
echo "  Inventory   → http://inventory.boxco.local:8080"
echo "  Jenkins     → http://localhost:8082"
echo "  Argo CD     → http://localhost:8081"
echo "  Grafana     → http://localhost:3000  (admin/admin)"
echo ""
echo -e "${BLUE}Demo flow:${NC}"
echo "  Scenario 1 (buggy)  → already live"
echo "  Scenario 2 (fix)    → push to scenario-2 branch"
echo "  Scenario 3 (XL box) → push to scenario-3 branch"
echo ""
echo -e "${BLUE}Demo reset:${NC}"
echo "  Jenkins → boxco-pipeline → main → Build Now"
echo ""
echo -e "${CYAN}Credentials:${NC} ./credentials.txt"
