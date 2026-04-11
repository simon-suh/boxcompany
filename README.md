# Box Company's Order Management System
A portfolio project demonstrating event-driven microservices architecture using real infrastructure tooling. Built to show three internal teams (Sales, Shipment, and Inventory) communicating through a shared Kafka event backbone rather than calling each other's services or databases directly. The system includes three deployment scenarios that demonstrate bug introduction, fix, and feature rollout, which are all automated through a CI/CD pipeline.

---

## Quick Start

Choose your **deployment mode** based on how you want to explore:

### Docker Compose (5 minutes)

**Best for:** Quick testing, local development, understanding the application

<details>
<summary><b>Click to expand details for Docker Compose deployment mode</b></summary>

**Prerequisites:** Docker and Docker Compose installed

```bash
# Clone and start
git clone https://github.com/simon-suh/boxcompany.git
cd boxcompany
git checkout main  # Starts with scenario-1 (the bug)
cp .env.example .env
docker compose up --build

# Access the application
# Sales Portal:     http://localhost:3001
# Shipment Portal:  http://localhost:3002
# Inventory Portal: http://localhost:3003
# Grafana:          http://localhost:3000 (admin/admin)
# Kafka UI:         http://localhost:8080
```

**Test the event flow:**
1. Place an order on the Sales Portal
2. Watch it appear on the Shipment dashboard (via Kafka event)
3. Add tracking info on Shipment dashboard
4. See order status update to "shipped" on Sales portal (via Kafka event)
5. Check console: `docker compose logs notification-service`

**Switch scenarios:**
```bash
docker compose down
git checkout scenario-2  # Bug fix
# or
git checkout scenario-3  # New feature (XL boxes)
docker compose up --build
```
</details>

---

### Full Kubernetes Stack (30-60 minutes)

**Best for:** Demonstrating complete DevOps workflow, CI/CD pipeline, observability

<details>
<summary><b>Click to expand details for Kubernetes deployment mode</b></summary>

**Prerequisites:**
- Minikube installed
- kubectl configured
- Helm 3.x installed

**Manual Setup:**

<details>
<summary><b>1. Start Minikube and Build Images</b></summary>

```bash
# Start local Kubernetes cluster
minikube start --cpus=4 --memory=8192 \
  --insecure-registry="192.168.49.2:30500" \
  --insecure-registry="10.0.0.0/8"

# Point Docker to Minikube's daemon
eval $(minikube docker-env)

# Get Minikube IP
MINIKUBE_IP=$(minikube ip)
echo "Minikube IP: $MINIKUBE_IP"
```
</details>

<details>
<summary><b>2. Deploy Infrastructure</b></summary>

```bash
# Create namespaces
kubectl create namespace boxco
kubectl create namespace observability
kubectl create namespace registry

# Deploy local Docker registry
kubectl apply -f k8s/registry/

# Deploy infrastructure (Kafka, databases)
kubectl apply -f k8s/config/
kubectl apply -f k8s/databases/
kubectl apply -f k8s/kafka/

# Wait for databases to be ready
kubectl wait --for=condition=ready pod -l app=postgres -n boxco --timeout=180s
kubectl wait --for=condition=ready pod -l app=dynamodb -n boxco --timeout=180s
kubectl wait --for=condition=ready pod -l app=kafka -n boxco --timeout=180s
```
</details>

<details>
<summary><b>3. Initialize PostgreSQL Database</b></summary>

```bash
# Get PostgreSQL pod name
POSTGRES_POD=$(kubectl get pod -n boxco -l app=postgres -o jsonpath='{.items[0].metadata.name}')

# Create database user and database
kubectl exec -n boxco $POSTGRES_POD -- psql -U boxco -d sales -c \
  "CREATE USER boxco_user WITH PASSWORD 'boxco_pass';"

kubectl exec -n boxco $POSTGRES_POD -- psql -U boxco -d sales -c \
  "CREATE DATABASE boxco_db OWNER boxco_user;"

# Create schema (tables)
kubectl exec -n boxco $POSTGRES_POD -- psql -U boxco -d boxco_db -c "
CREATE TABLE IF NOT EXISTS customers (
  id VARCHAR PRIMARY KEY,
  name VARCHAR NOT NULL,
  email VARCHAR,
  phone VARCHAR,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orders (
  id VARCHAR PRIMARY KEY,
  order_number VARCHAR UNIQUE NOT NULL,
  customer_id VARCHAR NOT NULL,
  payment_method VARCHAR NOT NULL,
  status VARCHAR NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS order_items (
  id VARCHAR PRIMARY KEY,
  order_id VARCHAR NOT NULL,
  product_id VARCHAR NOT NULL,
  product_name VARCHAR NOT NULL,
  quantity INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS error_reports (
  id VARCHAR PRIMARY KEY,
  order_number VARCHAR,
  reported_by VARCHAR NOT NULL,
  issue_type VARCHAR NOT NULL,
  description TEXT NOT NULL,
  notify_teams TEXT[],
  status VARCHAR NOT NULL DEFAULT 'open',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);"

# Grant permissions
kubectl exec -n boxco $POSTGRES_POD -- psql -U boxco -d boxco_db -c "
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO boxco_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO boxco_user;
GRANT USAGE ON SCHEMA public TO boxco_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO boxco_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO boxco_user;"
```
</details>

<details>
<summary><b>4. Install Observability Stack</b></summary>

```bash
# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus + Grafana with auto-loading dashboard
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --values grafana-values.yaml \
  --wait \
  --timeout 5m

# Deploy ServiceMonitors and Dashboard
kubectl apply -f k8s/observability-servicemonitor.yaml
kubectl apply -f k8s/grafana-dashboards/grafana-dashboard-configmap.yaml

# Wait for Grafana to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n observability --timeout=300s
```
</details>

<details>
<summary><b>5. Build and Deploy Services</b></summary>

```bash
# Build Docker images (choose your scenario)
git checkout main  # or scenario-2, scenario-3

# Build images
docker build -t $MINIKUBE_IP:30500/sales-api:latest services/sales-api/
docker build -t $MINIKUBE_IP:30500/inventory-api:latest services/inventory-api/
docker build -t $MINIKUBE_IP:30500/shipment-api:latest services/shipment-api/
docker build -t $MINIKUBE_IP:30500/notification-service:latest services/notification-service/

# Push to local registry
docker push $MINIKUBE_IP:30500/sales-api:latest
docker push $MINIKUBE_IP:30500/inventory-api:latest
docker push $MINIKUBE_IP:30500/shipment-api:latest
docker push $MINIKUBE_IP:30500/notification-service:latest

# Deploy services
kubectl apply -f k8s/services/

# Patch service ports for Prometheus (important!)
kubectl patch svc sales-api -n boxco -p '{"spec":{"ports":[{"name":"http","port":3001,"protocol":"TCP","targetPort":3001,"nodePort":30001}]}}'
kubectl patch svc inventory-api -n boxco -p '{"spec":{"ports":[{"name":"http","port":3003,"protocol":"TCP","targetPort":3003,"nodePort":30003}]}}'
kubectl patch svc shipment-api -n boxco -p '{"spec":{"ports":[{"name":"http","port":3002,"protocol":"TCP","targetPort":3002,"nodePort":30002}]}}'

# Wait for services to be ready
kubectl wait --for=condition=ready pod -l app=sales-api -n boxco --timeout=120s
kubectl wait --for=condition=ready pod -l app=inventory-api -n boxco --timeout=120s
kubectl wait --for=condition=ready pod -l app=shipment-api -n boxco --timeout=120s
kubectl wait --for=condition=ready pod -l app=notification-service -n boxco --timeout=120s

# Restart Prometheus to discover ServiceMonitors
kubectl delete pod -n observability -l app.kubernetes.io/name=prometheus
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n observability --timeout=180s
```
</details>

<details>
<summary><b>6. Access Services</b></summary>

```bash
# Port-forward application services
kubectl port-forward -n boxco svc/sales-api 3001:3001 &
kubectl port-forward -n boxco svc/shipment-api 3002:3002 &
kubectl port-forward -n boxco svc/inventory-api 3003:3003 &

# Port-forward Grafana (dashboard auto-loads!)
kubectl port-forward -n observability svc/prometheus-grafana 3000:80 &

# Port-forward Prometheus
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090 &

# Access URLs:
# Sales Portal:     http://localhost:3001
# Shipment Portal:  http://localhost:3002
# Inventory Portal: http://localhost:3003
# Grafana:          http://localhost:3000 (admin/admin)
# Prometheus:       http://localhost:9090
```
</details>

<details>
<summary><b>7. Test and Observe</b></summary>

1. **Place orders** on Sales Portal (http://localhost:3001)
2. **Try ordering Medium boxes** - this will FAIL in main/scenario-1 (the bug!)
3. **Open Grafana** (http://localhost:3000) - dashboard loads automatically
4. **Watch metrics:**
   - Stock Validation Errors shows Medium box failures
   - Orders Created shows failed orders
5. **Switch to scenario-2** to see the bug fix in action

</details>

</details>

---

## The Three Scenarios

This project demonstrates a realistic development workflow through three Git branches:

| Scenario | Branch | Background | Products | Demonstrates |
|----------|--------|------------|----------|--------------|
| **1. Bug Exists** | `main` | White | S, M, L | **The Problem:** Medium boxes can be ordered despite 0 stock<br>**Metrics:** High stock validation errors, ~50% order failure rate |
| **2. Bug Fixed** | `scenario-2` | Gradient | S, M, L | **The Fix:** Stock validation now enforced<br>**Metrics:** Zero validation errors, 100% success rate<br>**UI Update:** Gradient background |
| **3. New Feature** | `scenario-3` | Gray | S, M, L, XL | **Enhancement:** XL boxes added<br>**Metrics:** Zero errors, 100% success, new product tracked<br>**UI Update:** Solid gray background |

**The CI/CD Demo:** Push from scenario-1 → scenario-2, watch Jenkins build, Argo CD deploy, and Grafana metrics prove the bug is fixed!

---

### Components

| Service | Technology | Database | Kafka Events |
|---------|-----------|----------|--------------|
| **Sales API** | FastAPI + PostgreSQL | Customer orders, order items | **Produces:** `orders.created`, `errors.reported`<br>**Consumes:** `orders.shipped` |
| **Shipment API** | FastAPI + DynamoDB | Shipment tracking | **Produces:** `orders.shipped`, `errors.reported`<br>**Consumes:** `orders.created` |
| **Inventory API** | FastAPI + DynamoDB | Product stock levels | **Produces:** `inventory.updated`<br>**Consumes:** `orders.created` |
| **Notification** | Python Consumer | N/A | **Consumes:** `orders.created`, `orders.shipped` |

### Event Flow Example

```
1. User orders 2x Small boxes
   └─▶ Sales API validates stock
       └─▶ Publishes: orders.created

2. Inventory API receives event
   └─▶ Decrements stock: Small boxes (10 → 8)
       └─▶ Publishes: inventory.updated

3. Shipment API receives event  
   └─▶ Creates shipment record
       └─▶ Dashboard shows new order

4. Notification Service receives event
   └─▶ Sends confirmation email

5. Warehouse adds tracking number
   └─▶ Shipment API publishes: orders.shipped

6. Sales API receives event
   └─▶ Updates order status: pending → shipped

7. Notification Service receives event
   └─▶ Sends shipping notification
```

---

## Observability

### Grafana Dashboard (Auto-Loading)

The **BoxCo Services Overview** dashboard automatically loads when you access Grafana and provides real-time visibility into both business and infrastructure metrics.

**Business Metrics:**
- **Stock Validation Errors** - Demonstrates the scenario-1 bug (Medium box failures)
- **Orders Created** - Success vs failed order rates over time
- **Items Ordered** - Product demand by type

**Infrastructure Metrics:**
- **Services Status** - Health check for all 3 microservices
- **CPU Usage** - Resource utilization per service  
- **Memory Usage** - RAM consumption per service

<details>
<summary><b>Click to expand details for Custom Prometheus Metrics</b></summary>
  
**Sales API exposes business metrics:**
```python
# Order tracking
orders_created_total{status="success"}   # Successful orders
orders_created_total{status="failed"}    # Failed orders

# Bug indicator
stock_validation_errors_total{product_name="Medium box"}  # The bug!

# Product demand
order_items_total{product_name="Small box"}  # Items ordered by product
```

**All services expose infrastructure metrics:**
```
up{namespace="boxco", job="sales-api"}           # Service health (1=up, 0=down)
process_cpu_seconds_total{job="sales-api"}       # CPU usage
process_resident_memory_bytes{job="sales-api"}   # Memory usage
```
</details>

---

## CI/CD Pipeline (In Progress)

<details>
<summary><b>🚧 Planned Pipeline Architecture (Click to expand)</b></summary>

The pipeline demonstrates a complete GitOps workflow:

```
1. Developer pushes code
   └─▶ Git: scenario-1 → scenario-2

2. Jenkins detects webhook
   └─▶ Runs pipeline (build, test, package)
   └─▶ Builds new Docker images
   └─▶ Tags: scenario-2-abc123
   └─▶ Updates K8s manifests with new image tags

3. Argo CD detects Git changes
   └─▶ Syncs manifests to cluster
   └─▶ Deploys new images
   └─▶ Performs rolling update

4. Grafana shows improvement
   └─▶ Stock validation errors: HIGH → ZERO
   └─▶ Order success rate: 50% → 100%
   └─▶ Bug is fixed! ✅
```

**Current Status:**
- ✅ Local Docker registry configured
- ✅ Kubernetes manifests with proper service mesh
- ✅ Prometheus/Grafana monitoring stack
- ✅ ServiceMonitors for metrics collection
- ✅ Auto-loading Grafana dashboards
- 🚧 Jenkins pipeline setup (in progress)
- 🚧 Argo CD GitOps configuration (in progress)


### Technologies
- **Jenkins:** CI pipeline (build, test, image creation)
- **Argo CD:** GitOps continuous deployment  
- **Prometheus/Grafana:** Metrics validation

</details>

---

<details>
<summary><h2>Project Structure</h2>&nbsp;(Click to expand)</summary>


```
boxcompany/
├── README.md
├── docker-compose.yml
├── .env.example
├── grafana-values.yaml              # Helm values for Prometheus stack
│
├── config/                           # Initialization scripts
│   ├── dynamodb/
│   │   ├── init.py
│   │   └── run.sh
│   ├── postgres/
│   │   └── init.sql
│   └── kafka/
│       └── schemas.json
│
├── services/                         # Microservices
│   ├── sales-api/
│   │   ├── main.py
│   │   ├── database.py
│   │   ├── kafka_producer.py
│   │   ├── kafka_consumer.py
│   │   ├── requirements.txt
│   │   ├── Dockerfile
│   │   └── static/
│   ├── inventory-api/
│   │   ├── main.py
│   │   ├── dynamodb.py
│   │   ├── kafka.py
│   │   ├── requirements.txt
│   │   ├── Dockerfile
│   │   └── static/
│   ├── shipment-api/
│   │   ├── main.py
│   │   ├── dynamodb.py
│   │   ├── kafka.py
│   │   ├── requirements.txt
│   │   ├── Dockerfile
│   │   └── static/
│   └── notification-service/
│       ├── main.py
│       ├── kafka_consumer.py
│       ├── requirements.txt
│       └── Dockerfile
│
├── k8s/                              # Kubernetes manifests
│   ├── config/
│   │   └── postgres-init-configmap.yaml
│   ├── databases/
│   │   ├── dynamodb.yaml
│   │   └── postgres.yaml
│   ├── kafka/
│   │   ├── kafka.yaml
│   │   └── zookeeper.yaml
│   ├── services/
│   │   ├── sales-api.yaml
│   │   ├── inventory-api.yaml
│   │   ├── shipment-api.yaml
│   │   └── notification-service.yaml
│   ├── registry/
│   │   └── registry.yaml             # Local Docker registry for CI/CD
│   ├── grafana-dashboards/
│   │   └── grafana-dashboard-configmap.yaml
│   └── observability-servicemonitor.yaml
│
├── jenkins/                          # CI/CD pipeline (in progress)
│   ├── Jenkinsfile
│   └── k8s/
└── argo/                             # GitOps configs (in progress)
```

</details>

---

## Development

### Switching Scenarios in Kubernetes

```bash
# Switch branch
git checkout scenario-2  # or scenario-3

# Point Docker to Minikube
eval $(minikube docker-env)
MINIKUBE_IP=$(minikube ip)

# Rebuild and push images
docker build -t $MINIKUBE_IP:30500/sales-api:latest services/sales-api/
docker build -t $MINIKUBE_IP:30500/inventory-api:latest services/inventory-api/
docker build -t $MINIKUBE_IP:30500/shipment-api:latest services/shipment-api/
docker build -t $MINIKUBE_IP:30500/notification-service:latest services/notification-service/

docker push $MINIKUBE_IP:30500/sales-api:latest
docker push $MINIKUBE_IP:30500/inventory-api:latest
docker push $MINIKUBE_IP:30500/shipment-api:latest
docker push $MINIKUBE_IP:30500/notification-service:latest

# Rolling update
kubectl rollout restart deployment sales-api -n boxco
kubectl rollout restart deployment inventory-api -n boxco
kubectl rollout restart deployment shipment-api -n boxco
kubectl rollout restart deployment notification-service -n boxco

# Watch Grafana - metrics should improve!
```

---

## Troubleshooting

<details>
<summary><b>Minikube won't start</b></summary>

```bash
# Delete and recreate cluster
minikube delete
minikube start --cpus=4 --memory=8192 \
  --insecure-registry="192.168.49.2:30500" \
  --insecure-registry="10.0.0.0/8"

# Check status
minikube status
```
</details>

<details>
<summary><b>Pods stuck in Pending</b></summary>

```bash
# Check pod status
kubectl get pods -n boxco

# Describe pod to see events
kubectl describe pod <pod-name> -n boxco

# Common issues:
# - Insufficient resources: Increase Minikube memory
# - Image pull errors: Verify images were built with eval $(minikube docker-env)
```
</details>

<details>
<summary><b>Grafana dashboard not loading</b></summary>

```bash
# Restart Grafana pod
kubectl rollout restart deployment prometheus-grafana -n observability

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n observability --timeout=180s

# Restart port-forward
pkill -f "port-forward.*grafana"
kubectl port-forward -n observability svc/prometheus-grafana 3000:80 &
```
</details>

<details>
<summary><b>No metrics in Grafana</b></summary>

```bash
# Verify ServiceMonitors exist
kubectl get servicemonitors -n observability

# Check Prometheus targets
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090 &
# Open http://localhost:9090/targets
# Should see boxco-services, boxco-inventory, boxco-shipment as UP

# If targets show "No targets", restart Prometheus
kubectl delete pod -n observability -l app.kubernetes.io/name=prometheus

# Check if services expose metrics
kubectl port-forward -n boxco svc/sales-api 3001:3001 &
curl http://localhost:3001/metrics/
```
</details>

<details>
<summary><b>Shipment portal not showing orders from Sales</b></summary>

```bash
# This is a Kafka connectivity issue
# Check shipment-api logs for Kafka errors
kubectl logs -n boxco -l app=shipment-api --tail=30 | grep -i kafka

# Verify Kafka is running
kubectl get pods -n boxco -l app=kafka

# Check Kafka logs
kubectl logs -n boxco -l app=kafka --tail=50

# If shipment-api shows "Connection refused to localhost:9092"
# The KAFKA_BROKERS environment variable is incorrect
# It should be "kafka:9092" not "localhost:9092"
```
</details>

<details>
<summary><b>PostgreSQL permission denied errors</b></summary>

```bash
# Grant permissions to boxco_user
POSTGRES_POD=$(kubectl get pod -n boxco -l app=postgres -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n boxco $POSTGRES_POD -- psql -U boxco -d boxco_db -c "
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO boxco_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO boxco_user;"

# Restart sales-api
kubectl rollout restart deployment sales-api -n boxco
```
</details>

---

<details>
<summary><h2>Tech Stack</h2>&nbsp;(Click to expand)</summary>

### Application
- **Language:** Python 3.12
- **Web Framework:** FastAPI
- **Python Libraries:** SQLAlchemy, Boto3, prometheus-client, confluent-kafka

### Databases
- **PostgreSQL 16** - Customer orders (Sales API)
- **DynamoDB 2.0** - Shipment tracking, inventory stock
- **Apache Kafka 3.6** - Event streaming between services

### Container & Orchestration
- **Docker & Docker Compose** - Containerization
- **Kubernetes (Minikube)** - Container orchestration
- **Helm 3.x** - Kubernetes package manager

### Observability
- **Prometheus** - Metrics collection
- **Grafana** - Dashboards and visualization
- **prometheus_client** - Python instrumentation

### CI/CD (In Progress)
- **Jenkins** - Build and test automation
- **Argo CD** - GitOps continuous deployment
- **Local Docker Registry** - Image storage for CI/CD

### Frontend
- **HTML, CSS, JavaScript** - Responsive dashboards

  </details>
