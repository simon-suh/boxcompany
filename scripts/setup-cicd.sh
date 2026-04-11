#!/bin/bash
# BoxCo CI/CD Setup Script
# Deploys Jenkins and Argo CD to your Minikube cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     BoxCo CI/CD Pipeline Setup                             ║${NC}"
echo -e "${BLUE}║     Jenkins + Argo CD on Minikube                          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
check_prereqs() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    if ! command -v minikube &> /dev/null; then
        echo -e "${RED}Error: minikube is not installed${NC}"
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl is not installed${NC}"
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}Error: helm is not installed${NC}"
        exit 1
    fi
    
    # Check if Minikube is running
    if ! minikube status &> /dev/null; then
        echo -e "${RED}Error: Minikube is not running${NC}"
        echo "Start Minikube with: minikube start --cpus=4 --memory=8192"
        exit 1
    fi
    
    echo -e "${GREEN}✓ All prerequisites met${NC}"
}

# Get Minikube IP
get_minikube_ip() {
    MINIKUBE_IP=$(minikube ip)
    echo -e "${GREEN}Minikube IP: ${MINIKUBE_IP}${NC}"
    export MINIKUBE_IP
}

# Deploy Jenkins
deploy_jenkins() {
    echo -e "\n${YELLOW}═══ Deploying Jenkins ═══${NC}"
    
    # Create namespace
    kubectl apply -f jenkins/k8s/namespace.yaml
    echo -e "${GREEN}✓ Jenkins namespace created${NC}"
    
    # Update Jenkins config with Minikube IP
    kubectl create configmap jenkins-config \
        --from-literal=minikube-ip="${MINIKUBE_IP}" \
        -n jenkins \
        --dry-run=client -o yaml | kubectl apply -f -
    echo -e "${GREEN}✓ Jenkins config updated with Minikube IP${NC}"
    
    # Apply RBAC
    kubectl apply -f jenkins/k8s/rbac.yaml
    echo -e "${GREEN}✓ Jenkins RBAC configured${NC}"
    
    # Apply PVC
    kubectl apply -f jenkins/k8s/pvc.yaml
    echo -e "${GREEN}✓ Jenkins PVC created${NC}"
    
    # Apply deployment
    kubectl apply -f jenkins/k8s/deployment.yaml
    echo -e "${GREEN}✓ Jenkins deployment applied${NC}"
    
    # Wait for Jenkins to be ready
    echo -e "${YELLOW}Waiting for Jenkins to start (this may take 2-3 minutes)...${NC}"
    kubectl wait --for=condition=ready pod -l app=jenkins -n jenkins --timeout=300s
    
    # Get initial admin password
    sleep 10  # Wait for Jenkins to fully initialize
    JENKINS_POD=$(kubectl get pod -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}')
    JENKINS_PASSWORD=$(kubectl exec -n jenkins $JENKINS_POD -- cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "Password not ready yet")
    
    echo -e "${GREEN}✓ Jenkins deployed successfully${NC}"
    echo -e "${BLUE}Jenkins URL: http://${MINIKUBE_IP}:30080/jenkins${NC}"
    echo -e "${BLUE}Initial Admin Password: ${JENKINS_PASSWORD}${NC}"
}

# Deploy Argo CD
deploy_argocd() {
    echo -e "\n${YELLOW}═══ Deploying Argo CD ═══${NC}"
    
    # Create namespace
    kubectl apply -f argo/namespace.yaml
    echo -e "${GREEN}✓ Argo CD namespace created${NC}"
    
    # Install Argo CD using official manifests
    echo -e "${YELLOW}Installing Argo CD (this may take a minute)...${NC}"
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for Argo CD to be ready
    echo -e "${YELLOW}Waiting for Argo CD to start...${NC}"
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
    
    # Patch Argo CD server to use NodePort
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"name": "http", "port": 80, "targetPort": 8080, "nodePort": 30081}, {"name": "https", "port": 443, "targetPort": 8080, "nodePort": 30443}]}}'
    
    # Get initial admin password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    echo -e "${GREEN}✓ Argo CD deployed successfully${NC}"
    echo -e "${BLUE}Argo CD URL: http://${MINIKUBE_IP}:30081${NC}"
    echo -e "${BLUE}Username: admin${NC}"
    echo -e "${BLUE}Password: ${ARGOCD_PASSWORD}${NC}"
}

# Register BoxCo applications with Argo CD
register_applications() {
    echo -e "\n${YELLOW}═══ Registering BoxCo Applications ═══${NC}"
    
    # Wait a bit for Argo CD CRDs to be ready
    sleep 5
    
    # Apply the project
    kubectl apply -f argo/project.yaml
    echo -e "${GREEN}✓ BoxCo project created${NC}"
    
    # Apply applications
    kubectl apply -f argo/applications/boxco-infrastructure.yaml
    echo -e "${GREEN}✓ BoxCo infrastructure application registered${NC}"
    
    kubectl apply -f argo/applications/boxco-services.yaml
    echo -e "${GREEN}✓ BoxCo services application registered${NC}"
    
    echo -e "${GREEN}✓ All applications registered with Argo CD${NC}"
}

# Print summary
print_summary() {
    echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Setup Complete! 🎉                                      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Access URLs:${NC}"
    echo -e "  Jenkins:        http://${MINIKUBE_IP}:30080/jenkins"
    echo -e "  Argo CD:        http://${MINIKUBE_IP}:30081"
    echo -e "  Sales Portal:   http://${MINIKUBE_IP}:30001"
    echo -e "  Shipment Portal: http://${MINIKUBE_IP}:30002"
    echo -e "  Inventory Portal: http://${MINIKUBE_IP}:30003"
    echo -e "  Grafana:        http://${MINIKUBE_IP}:30300"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Access Jenkins and complete initial setup"
    echo "  2. Install required plugins: Kubernetes, Pipeline, Git"
    echo "  3. Configure GitHub credentials"
    echo "  4. Create a pipeline job pointing to your Jenkinsfile"
    echo "  5. Access Argo CD and verify applications are syncing"
    echo ""
    echo -e "${YELLOW}Test the Pipeline:${NC}"
    echo "  1. Push a change to scenario-2 branch"
    echo "  2. Watch Jenkins build and push images"
    echo "  3. Watch Argo CD sync the new manifests"
    echo "  4. Check Grafana to see the bug fix in action!"
    echo ""
}

# Port forwarding helper
setup_port_forwards() {
    echo -e "\n${YELLOW}Setting up port forwards (optional)...${NC}"
    echo "Run these commands in separate terminals if you prefer localhost access:"
    echo ""
    echo "  # Jenkins"
    echo "  kubectl port-forward -n jenkins svc/jenkins 8080:8080"
    echo ""
    echo "  # Argo CD"
    echo "  kubectl port-forward -n argocd svc/argocd-server 8081:80"
    echo ""
}

# Main execution
main() {
    check_prereqs
    get_minikube_ip
    deploy_jenkins
    deploy_argocd
    register_applications
    setup_port_forwards
    print_summary
}

# Run main function
main "$@"
