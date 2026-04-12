#!/bin/bash

# Get the branch name (default to current branch)
BRANCH=${1:-$(git branch --show-current)}
BUILD_NUMBER=${2:-$(date +%s)}
IMAGE_TAG="${BRANCH}-${BUILD_NUMBER}"

# Get Minikube IP for pushing
MINIKUBE_IP=$(minikube ip)
REGISTRY_PUSH="${MINIKUBE_IP}:30500"
# Use localhost for kubectl (manifest updates via port-forward)
REGISTRY_PULL="localhost:5000"

echo "========================================"
echo "Building BoxCo Services"
echo "Branch: $BRANCH"
echo "Build Number: $BUILD_NUMBER"
echo "Image Tag: $IMAGE_TAG"
echo "Registry (push): $REGISTRY_PUSH"
echo "Registry (pull): $REGISTRY_PULL"
echo "========================================"

# Ensure we're using Minikube's Docker
eval $(minikube docker-env)

# Build and push all services
echo "Building and pushing sales-api..."
docker build -t ${REGISTRY_PUSH}/sales-api:${IMAGE_TAG} -t ${REGISTRY_PUSH}/sales-api:latest services/sales-api/
docker push ${REGISTRY_PUSH}/sales-api:${IMAGE_TAG}
docker push ${REGISTRY_PUSH}/sales-api:latest

echo "Building and pushing inventory-api..."
docker build -t ${REGISTRY_PUSH}/inventory-api:${IMAGE_TAG} -t ${REGISTRY_PUSH}/inventory-api:latest services/inventory-api/
docker push ${REGISTRY_PUSH}/inventory-api:${IMAGE_TAG}
docker push ${REGISTRY_PUSH}/inventory-api:latest

echo "Building and pushing shipment-api..."
docker build -t ${REGISTRY_PUSH}/shipment-api:${IMAGE_TAG} -t ${REGISTRY_PUSH}/shipment-api:latest services/shipment-api/
docker push ${REGISTRY_PUSH}/shipment-api:${IMAGE_TAG}
docker push ${REGISTRY_PUSH}/shipment-api:latest

echo "Building and pushing notification-service..."
docker build -t ${REGISTRY_PUSH}/notification-service:${IMAGE_TAG} -t ${REGISTRY_PUSH}/notification-service:latest services/notification-service/
docker push ${REGISTRY_PUSH}/notification-service:${IMAGE_TAG}
docker push ${REGISTRY_PUSH}/notification-service:latest

echo "Updating Kubernetes deployments..."
kubectl set image deployment/sales-api sales-api=${REGISTRY_PULL}/sales-api:${IMAGE_TAG} -n boxco
kubectl set image deployment/inventory-api inventory-api=${REGISTRY_PULL}/inventory-api:${IMAGE_TAG} -n boxco
kubectl set image deployment/shipment-api shipment-api=${REGISTRY_PULL}/shipment-api:${IMAGE_TAG} -n boxco
kubectl set image deployment/notification-service notification-service=${REGISTRY_PULL}/notification-service:${IMAGE_TAG} -n boxco

echo "Waiting for rollout to complete..."
kubectl rollout status deployment/sales-api -n boxco --timeout=120s
kubectl rollout status deployment/inventory-api -n boxco --timeout=120s
kubectl rollout status deployment/shipment-api -n boxco --timeout=120s
kubectl rollout status deployment/notification-service -n boxco --timeout=120s

echo "========================================"
echo "✅ Deployment Complete!"
echo "Images pushed with tag: ${IMAGE_TAG}"
echo "========================================"
kubectl get pods -n boxco
