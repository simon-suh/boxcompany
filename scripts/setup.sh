#!/bin/bash
# ═════════════════════════════════════════════════════════════════════════════
# BoxCo Demo Setup
# Run ONCE before the demo. Takes ~20-30 minutes.
#
# What this does:
#   1.  Starts Minikube
#   2.  Enables Ingress
#   3.  Creates all namespaces
#   4.  Deploys local Docker registry
#   5.  Installs Prometheus + Grafana
#   6.  Installs Argo CD + registers applications
#   7.  Deploys databases (Postgres, DynamoDB) + Kafka
#   8.  Deploys Jenkins (with CasC + plugin install)
#   9.  Sets up smee.io webhook bridge + registers GitHub webhook
#   10. Triggers Jenkins to pre-build all scenario images
#   11. Starts port-forwards
#   12. Configures local DNS
#   13. Saves all credentials to credentials.txt
#
# Usage:
#   ./scripts/setup.sh          — interactive
#   ./scripts/setup.sh -y       — non-interactive (reads from env vars)
#
# Non-interactive env vars:
#   GITHUB_USERNAME, GITHUB_TOKEN, JENKINS_ADMIN_PASS
# ═════════════════════════════════════════════════════════════════════════════
set -e

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

AUTO_YES=false
[[ "$1" == "-y" || "$1" == "--yes" ]] && AUTO_YES=true

# ── Helpers ───────────────────────────────────────────────────────────────────
header() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════╗\n║  $1\n╚══════════════════════════════════════════════════╝${NC}"
}
step() { echo -e "\n${YELLOW}─── $1 ───${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

header "BoxCo Demo Setup"
echo "Run this once before your demo. Everything will be ready when it completes."

# ── Prerequisites ─────────────────────────────────────────────────────────────
step "Checking prerequisites"
for cmd in minikube kubectl helm docker git curl; do
    command -v $cmd &>/dev/null && ok "$cmd" || fail "$cmd not found — please install it first"
done

# ── Credentials ───────────────────────────────────────────────────────────────
step "GitHub credentials for Jenkins"
echo ""
echo "Jenkins needs a GitHub Personal Access Token to:"
echo "  • Check out branches and build Docker images"
echo "  • Push updated image tags back to main (triggers Argo CD)"
echo "  • Register a webhook on your repo (for instant build triggers)"
echo ""
echo "  Token requires: repo scope"
echo "  Create one at: https://github.com/settings/tokens"
echo ""

if [[ "$AUTO_YES" == true ]]; then
    : "${GITHUB_USERNAME:?Set GITHUB_USERNAME env var}"
    : "${GITHUB_TOKEN:?Set GITHUB_TOKEN env var}"
    JENKINS_ADMIN_PASS="${JENKINS_ADMIN_PASS:-admin}"
    ok "Using credentials from environment"
else
    read -p  "  GitHub username  : " GITHUB_USERNAME
    read -sp "  GitHub token     : " GITHUB_TOKEN; echo
    read -sp "  Jenkins admin password (Enter for 'admin'): " JENKINS_ADMIN_PASS; echo
    JENKINS_ADMIN_PASS="${JENKINS_ADMIN_PASS:-admin}"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — Minikube
# ═════════════════════════════════════════════════════════════════════════════
step "Step 1/12 — Minikube"
if minikube status 2>/dev/null | grep -q "Running"; then
    ok "Minikube already running"
else
    echo "Starting Minikube (8 GB RAM, 4 CPUs)..."
    minikube start --memory=8192 --cpus=4 --insecure-registry="192.168.0.0/16"
    ok "Minikube started"
fi
MINIKUBE_IP=$(minikube ip)
ok "Node IP: ${MINIKUBE_IP}"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — Ingress
# ═════════════════════════════════════════════════════════════════════════════
step "Step 2/12 — Ingress controller"
if minikube addons list | grep -q "ingress.*enabled"; then
    ok "Ingress addon already enabled"
else
    minikube addons enable ingress
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/component=controller \
        -n ingress-nginx --timeout=120s
    ok "Ingress controller ready"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — Namespaces
# ═════════════════════════════════════════════════════════════════════════════
step "Step 3/12 — Namespaces"
for ns in boxco observability argocd registry jenkins; do
    kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - > /dev/null
    ok "namespace/$ns"
done

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — Local Docker Registry
# ═════════════════════════════════════════════════════════════════════════════
step "Step 4/12 — Local Docker registry"
kubectl apply -f k8s/registry/ > /dev/null
kubectl wait --for=condition=ready pod -l app=registry -n registry --timeout=120s
ok "Registry ready at ${MINIKUBE_IP}:30500"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 — Prometheus + Grafana
# ═════════════════════════════════════════════════════════════════════════════
step "Step 5/12 — Prometheus + Grafana"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update 2>/dev/null || true

if helm list -n observability | grep -q prometheus; then
    ok "Prometheus stack already installed"
else
    helm install prometheus prometheus-community/kube-prometheus-stack \
        -n observability -f grafana-values.yaml --wait
    kubectl apply -f k8s/observability/ > /dev/null
    ok "Prometheus + Grafana installed"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 — Argo CD
# ═════════════════════════════════════════════════════════════════════════════
step "Step 6/12 — Argo CD"
if kubectl get deployment argocd-server -n argocd &>/dev/null; then
    ok "Argo CD already installed"
else
    kubectl apply -n argocd \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
        --server-side
    echo "  Waiting for Argo CD..."
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
    ok "Argo CD installed"
fi

# Register Argo CD Applications (boxco-infrastructure + boxco-services)
kubectl apply -f argo/ > /dev/null
kubectl apply -f argo/applications/ > /dev/null
ok "Argo CD applications registered"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7 — Databases + Kafka
# ═════════════════════════════════════════════════════════════════════════════
step "Step 7/12 — Databases + Kafka"
kubectl apply -f k8s/config/ > /dev/null

kubectl apply -f k8s/kafka/ > /dev/null
kubectl wait --for=condition=ready pod -l app=zookeeper -n boxco --timeout=120s
kubectl wait --for=condition=ready pod -l app=kafka     -n boxco --timeout=120s
ok "Kafka + Zookeeper ready"

kubectl apply -f k8s/databases/postgres.yaml  > /dev/null
kubectl apply -f k8s/databases/dynamodb.yaml  > /dev/null
kubectl wait --for=condition=ready pod -l app=postgres -n boxco --timeout=120s
kubectl wait --for=condition=ready pod -l app=dynamodb -n boxco --timeout=120s
ok "Postgres + DynamoDB ready"

kubectl delete job dynamodb-init -n boxco --ignore-not-found > /dev/null
kubectl apply -f k8s/databases/dynamodb-init-job.yaml > /dev/null
kubectl wait --for=condition=complete job/dynamodb-init -n boxco --timeout=180s
ok "DynamoDB initialized"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 8 — Jenkins
# ═════════════════════════════════════════════════════════════════════════════
step "Step 8/12 — Jenkins"

# 8a. Credentials secret (never stored in git — created here from user input)
kubectl create secret generic jenkins-credentials \
    --namespace=jenkins \
    --from-literal=admin-password="${JENKINS_ADMIN_PASS}" \
    --from-literal=dev-password="developer" \
    --from-literal=github-username="${GITHUB_USERNAME}" \
    --from-literal=github-token="${GITHUB_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f - > /dev/null
ok "Credentials secret created"

# 8b. ConfigMaps from repo files
kubectl create configmap jenkins-casc \
    --namespace=jenkins \
    --from-file=jenkins.yaml=jenkins/k8s/jenkins-casc.yaml \
    --dry-run=client -o yaml | kubectl apply -f - > /dev/null

kubectl create configmap jenkins-plugins \
    --namespace=jenkins \
    --from-file=plugins.txt=jenkins/plugins.txt \
    --dry-run=client -o yaml | kubectl apply -f - > /dev/null
ok "ConfigMaps created (CasC + plugins)"

# 8c. Apply Jenkins manifests (smee.yaml applied after smee URL is known — Step 9)
kubectl apply -f jenkins/k8s/namespace.yaml  > /dev/null
kubectl apply -f jenkins/k8s/pvc.yaml        > /dev/null
kubectl apply -f jenkins/k8s/rbac.yaml       > /dev/null
kubectl apply -f jenkins/k8s/deployment.yaml > /dev/null
kubectl apply -f jenkins/k8s/service.yaml    > /dev/null
ok "Jenkins manifests applied"

echo "  Waiting for Jenkins pod (plugin install takes 2-3 min)..."
kubectl wait --for=condition=ready pod -l app=jenkins -n jenkins --timeout=360s
ok "Jenkins pod ready"

# 8d. Wait for Jenkins HTTP to respond
echo "  Waiting for Jenkins web UI..."
for i in $(seq 1 40); do
    STATUS=$(kubectl exec -n jenkins deploy/jenkins -- \
        curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login 2>/dev/null || echo "0")
    [[ "$STATUS" == "200" ]] && { ok "Jenkins web UI up"; break; }
    [[ $i -eq 40 ]] && warn "Jenkins web UI slow to respond — check logs if builds don't start"
    sleep 10
done

# ═════════════════════════════════════════════════════════════════════════════
# STEP 9 — Smee webhook bridge + GitHub webhook registration
# ═════════════════════════════════════════════════════════════════════════════
# Why smee?  Jenkins runs on localhost — GitHub can't reach it directly.
# Smee.io (made by GitHub) provides a free public relay URL. The smee-client
# pod inside your cluster forwards those events to Jenkins instantly.
#
# Result: git push → GitHub → smee.io → smee pod → Jenkins → build starts
# ═════════════════════════════════════════════════════════════════════════════
step "Step 9/12 — Webhook bridge (smee.io)"

# 9a. Create a smee.io channel (one HTTP redirect → get the assigned URL)
echo "  Creating smee.io channel..."
SMEE_URL=$(curl -sI https://smee.io/new | grep -i ^location | awk '{print $2}' | tr -d '\r\n')

if [[ -z "$SMEE_URL" ]]; then
    warn "Could not reach smee.io — falling back to 1-minute polling for demo"
    warn "Webhooks can be configured manually later"
    SMEE_URL="https://smee.io/PLACEHOLDER"
else
    ok "Smee channel: ${SMEE_URL}"
fi

# 9b. Store the smee URL as a ConfigMap so the smee-client pod can read it
kubectl create configmap jenkins-smee \
    --namespace=jenkins \
    --from-literal=url="${SMEE_URL}" \
    --dry-run=client -o yaml | kubectl apply -f - > /dev/null
ok "Smee URL stored in ConfigMap"

# 9c. Deploy the smee-client pod (bridges smee.io → Jenkins inside cluster)
kubectl apply -f jenkins/k8s/smee.yaml > /dev/null
ok "Smee client pod deployed"

# 9d. Register the webhook on your GitHub repo via API
echo "  Registering GitHub webhook..."
WEBHOOK_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${GITHUB_USERNAME}/boxcompany/hooks" \
    -d "{
        \"name\": \"web\",
        \"active\": true,
        \"events\": [\"push\"],
        \"config\": {
            \"url\": \"${SMEE_URL}\",
            \"content_type\": \"json\"
        }
    }")

if [[ "$WEBHOOK_RESPONSE" == "201" ]]; then
    ok "GitHub webhook registered → ${SMEE_URL}"
else
    warn "GitHub webhook registration returned HTTP ${WEBHOOK_RESPONSE}"
    warn "You can add it manually: GitHub repo → Settings → Webhooks → Add"
    warn "  Payload URL : ${SMEE_URL}"
    warn "  Content type: application/json"
    warn "  Events      : Just the push event"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 10 — Pre-build scenario images via Jenkins
# ═════════════════════════════════════════════════════════════════════════════
# Trigger Jenkins builds for all 3 branches now so images are pre-loaded
# into the registry. During the demo, Jenkins will detect the images already
# exist and skip the Docker build — making scenario transitions ~30 seconds.
# ═════════════════════════════════════════════════════════════════════════════
step "Step 10/12 — Pre-building scenario images"
echo "  Triggering Jenkins builds for all 3 branches in the background."
echo "  (~15-20 min for first run — images cached in registry for demo)"

# Temporary port-forward to hit Jenkins REST API
kubectl port-forward -n jenkins svc/jenkins 18080:8080 > /dev/null 2>&1 &
PF_PID=$!
sleep 8

trigger_branch() {
    local branch=$1
    local encoded="${branch//\//%2F}"
    local crumb
    crumb=$(curl -s -u "admin:${JENKINS_ADMIN_PASS}" \
        "http://localhost:18080/crumbIssuer/api/json" 2>/dev/null | \
        grep -o '"crumb":"[^"]*"' | cut -d'"' -f4 || echo "")

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -u "admin:${JENKINS_ADMIN_PASS}" \
        ${crumb:+-H "Jenkins-Crumb: $crumb"} \
        "http://localhost:18080/job/boxco-pipeline/job/${encoded}/build" 2>/dev/null || echo "0")

    if [[ "$status" == "201" ]]; then
        ok "Build triggered: ${branch}"
    else
        warn "Could not trigger ${branch} now (HTTP ${status}) — Jenkins will auto-build within 1 min"
    fi
}

# Allow Jenkins time to scan the repo and discover branches
echo "  Waiting for branch discovery..."
sleep 30

for branch in main scenario-2 scenario-3; do
    trigger_branch "$branch"
done

kill $PF_PID 2>/dev/null || true
echo ""
echo -e "  ${CYAN}Builds are running in the background.${NC}"
echo -e "  ${CYAN}Monitor progress at http://localhost:8082 after port-forwards start.${NC}"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 11 — Port Forwards
# ═════════════════════════════════════════════════════════════════════════════
step "Step 11/12 — Port forwards"
for pattern in "port-forward.*5000" "port-forward.*3000" "port-forward.*9090" \
               "port-forward.*8081" "port-forward.*8080" "port-forward.*8082"; do
    pkill -f "$pattern" 2>/dev/null || true
done
sleep 2

nohup kubectl port-forward -n registry      svc/registry                               5000:5000 >/dev/null 2>&1 &
nohup kubectl port-forward -n observability  svc/prometheus-grafana                    3000:80   >/dev/null 2>&1 &
nohup kubectl port-forward -n observability  svc/prometheus-kube-prometheus-prometheus 9090:9090 >/dev/null 2>&1 &
nohup kubectl port-forward -n argocd         svc/argocd-server                         8081:80   >/dev/null 2>&1 &
nohup kubectl port-forward -n ingress-nginx  svc/ingress-nginx-controller              8080:80   >/dev/null 2>&1 &
nohup kubectl port-forward -n jenkins        svc/jenkins                               8082:8080 >/dev/null 2>&1 &
sleep 3

ok "Port forwards started:"
echo "    Jenkins       → http://localhost:8082"
echo "    Argo CD       → http://localhost:8081"
echo "    Grafana       → http://localhost:3000"
echo "    Prometheus    → http://localhost:9090"
echo "    App (Ingress) → http://*.boxco.local:8080"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 12 — Local DNS
# ═════════════════════════════════════════════════════════════════════════════
step "Step 12/12 — Local DNS"
HOSTS_ENTRY="127.0.0.1  sales.boxco.local shipment.boxco.local inventory.boxco.local"

if grep -qi microsoft /proc/version 2>/dev/null; then
    warn "WSL2 detected — add this to your WINDOWS hosts file:"
    echo ""
    echo -e "    ${GREEN}${HOSTS_ENTRY}${NC}"
    echo ""
    echo "  PowerShell (as Administrator):"
    echo -e "    ${YELLOW}Add-Content -Path 'C:\\Windows\\System32\\drivers\\etc\\hosts' -Value '${HOSTS_ENTRY}'${NC}"
else
    if grep -q "boxco.local" /etc/hosts; then
        ok "Hosts already configured"
    else
        echo "${HOSTS_ENTRY}" | sudo tee -a /etc/hosts > /dev/null
        ok "Hosts configured"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# Credentials file
# ═════════════════════════════════════════════════════════════════════════════
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "check-argocd-ui")

cat > credentials.txt << EOF
═══════════════════════════════════════════════════════════════════
 BoxCo Demo Environment
 Generated: $(date)
═══════════════════════════════════════════════════════════════════

 BOXCO SERVICES
 ──────────────────────────────────────────────────────────────────
 Sales      → http://sales.boxco.local:8080
 Shipment   → http://shipment.boxco.local:8080
 Inventory  → http://inventory.boxco.local:8080

 CI/CD
 ──────────────────────────────────────────────────────────────────
 Jenkins    → http://localhost:8082   admin / ${JENKINS_ADMIN_PASS}
 Argo CD    → http://localhost:8081   admin / ${ARGOCD_PASS}
 Webhook    → ${SMEE_URL}

 OBSERVABILITY
 ──────────────────────────────────────────────────────────────────
 Grafana    → http://localhost:3000   admin / admin
 Prometheus → http://localhost:9090

═══════════════════════════════════════════════════════════════════
 DEMO FLOW (no scripts needed!)
 ──────────────────────────────────────────────────────────────────
 Scenario 1 (buggy)  → already live — open http://sales.boxco.local:8080
 Scenario 2 (fix)    → git push to scenario-2 branch
 Scenario 3 (XL box) → git push to scenario-3 branch

 GitHub push → smee.io → Jenkins builds → Argo CD syncs → ~30 sec ✨
═══════════════════════════════════════════════════════════════════
EOF

ok "Credentials saved to credentials.txt"

# ═════════════════════════════════════════════════════════════════════════════
# Done!
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ Setup complete!                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Jenkins is building scenario images in the background.${NC}"
echo -e "${CYAN}Check build progress → http://localhost:8082${NC}"
echo -e "${CYAN}When all 3 builds show green, your demo is ready.${NC}"
echo ""
echo -e "${BLUE}Demo flow:${NC}"
echo "  1. Open http://sales.boxco.local:8080  — show the bug (Scenario 1)"
echo "  2. git push to scenario-2              — Jenkins + Argo CD fix the bug ✨"
echo "  3. git push to scenario-3              — XL box appears ✨"
echo ""
echo -e "${BLUE}Credentials:${NC} ./credentials.txt"
