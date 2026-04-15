# Box Company's Order Management System

A portfolio project demonstrating event-driven microservices architecture using real infrastructure tooling. Built to show three internal teams (Sales, Shipment, and Inventory) communicating through a shared Kafka event backbone rather than calling each other's services or databases directly. The system includes three deployment scenarios that demonstrate bug introduction, fix, and feature rollout, deployed via automation scripts with a GitOps pipeline scaffolded for future implementation.

**Run locally with Docker Compose (Option 1) or explore the full Kubernetes stack with observability and observability (Option 2).**

---

## Quick Start

### Prerequisites

This project supports two deployment modes:
- **Option 1: Docker Compose** for quick local setup (~5 min)
- **Option 2: Kubernetes** for full stack with CI/CD and observability (~25 min)

**Required for both options:**
- Git
- Docker Desktop 4.0+ (or Docker Engine 20.10+ with Docker Compose plugin)

**Additional requirements for Kubernetes demo:**
- Minikube 1.30+
- kubectl 1.27+
- Helm 3.12+

<details>
<summary><b>Install prerequisites (click to expand)</b></summary>

#### For Docker Compose (Option 1)

**Docker Desktop** (includes Docker Engine and Compose):
- [Download Docker Desktop](https://www.docker.com/products/docker-desktop/)

That's it — you're ready for Option 1.

---

#### For Kubernetes Demo (Option 2)

You'll need Docker Desktop plus the following:

**Minikube:**
```bash
# macOS
brew install minikube

# Linux
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Windows (PowerShell as Admin)
choco install minikube
```

**kubectl:**
```bash
# macOS
brew install kubectl

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl

# Windows (PowerShell as Admin)
choco install kubernetes-cli
```

**Helm:**
```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Windows (PowerShell as Admin)
choco install kubernetes-helm
```

</details>

---

Choose your **deployment mode** based on how you want to explore:

---

### Option 1: Docker Compose

**Best for:** Quick testing, local development, understanding the application  
**Time:** ~5 minutes

<details>
<summary><b>Click to expand Docker Compose setup</b></summary>

```bash
# Clone and start
git clone https://github.com/simon-suh/boxcompany.git
cd boxcompany
cp .env.example .env
docker compose up --build
```

**Access the portals:**
| Portal | URL | Description |
|--------|-----|-------------|
| Sales | http://localhost:3001 | Place orders, view order history |
| Shipment | http://localhost:3002 | View incoming orders, add tracking |
| Inventory | http://localhost:3003 | View/update stock levels |
| Grafana | http://localhost:3000 | Metrics dashboard (admin/admin) |
| Kafka UI | http://localhost:8080 | View Kafka topics and messages |

**Test the event flow:**
1. Place an order on the Sales Portal
2. Watch it appear on the Shipment dashboard (via Kafka)
3. Add tracking info on Shipment dashboard
4. See order status update to "shipped" on Sales portal
5. Update stock levels on Inventory Portal
6. Confirm stock levels updated on Sales Portal
7. Watch metrics in Grafana
8. (Optional) Check logs to verify notifications logged: `docker compose logs notification-service`

**Switch scenarios:**
```bash
docker compose down
git checkout scenario-2  # Bug fix
docker compose up --build
# or
docker compose down
git checkout scenario-3  # New feature (XL boxes)
docker compose up --build
```

</details>


---

### Option 2: Kubernetes Demo

**Best for:** Demonstrating complete DevOps workflow, CI/CD pipeline, observability  
**Time:** ~25-30 minutes (one-time setup)

<details>
<summary><b>Click to expand Kubernetes setup</b></summary>

```bash
# Clone the repo
git clone https://github.com/simon-suh/boxcompany.git
cd boxcompany

# One command setup (builds everything, deploys scenario 1)
./scripts/full-stack-setup.sh -y
```

Or run interactively (prompts at each step):
```bash
./scripts/full-stack-setup.sh
```

**WSL2 Users:** After setup completes, add these entries to your Windows hosts file.  
Run in PowerShell as Administrator:
```powershell
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "127.0.0.1 sales.boxco.local shipment.boxco.local inventory.boxco.local"
```

**Access the portals:**
| Portal | URL | Credentials |
|--------|-----|-------------|
| Sales | http://sales.boxco.local:8080 | — |
| Shipment | http://shipment.boxco.local:8080 | — |
| Inventory | http://inventory.boxco.local:8080 | — |
| Grafana | http://localhost:3000 | admin / admin |
| Prometheus | http://localhost:9090 | — |
| ArgoCD | http://localhost:8081 | admin / see `credentials.txt` |

> **Note:** `credentials.txt` is auto-generated in your project root by `full-stack-setup.sh`. It contains the ArgoCD admin password and all access URLs.

**Run the demo:**
```bash
./scripts/demo-run.sh        # Scenario 1: White bg, bug exists
./scripts/demo-run.sh 2      # Scenario 2: Gradient bg, bug fixed
./scripts/demo-run.sh 3      # Scenario 3: Gray bg, XL boxes added
```

</details>

---

### Scripts Reference

<details>
<summary><b>What does full-stack-setup.sh do?</b></summary>

1. Starts Minikube with 8GB RAM, 3 CPUs, insecure registry configured
2. Enables NGINX Ingress Controller addon
3. Creates namespaces (boxco, observability, argocd, registry)
4. Sets up local Docker registry
5. Installs Prometheus & Grafana via Helm
6. Installs ArgoCD (dashboard mode)
7. Deploys infrastructure (Postgres, DynamoDB, Kafka, Zookeeper)
8. Applies Ingress routes for BoxCo services
9. Starts port forwards
10. Generates `credentials.txt` with all passwords and URLs
11. Optionally builds scenario images and deploys scenario 1

</details>

<details>
<summary><b>What does demo-setup.sh do?</b></summary>

1. Checks out `main` branch and builds scenario-1 images
2. Checks out `scenario-2` branch and builds scenario-2 images
3. Checks out `scenario-3` branch and builds scenario-3 images
4. Pushes all images to local registry
5. Returns to original branch

</details>

<details>
<summary><b>What does demo-run.sh do?</b></summary>

1. Updates manifest image tags to selected scenario
2. Updates SCENARIO env var in manifests
3. Applies manifests to Kubernetes
4. Triggers rollout restart for all deployments (ensures fresh images)
5. Waits for pods to be ready
6. Re-enables ArgoCD auto-sync

</details>

---

### The Three Scenarios

| Scenario | Branch | Background | Products | Demonstrates |
|----------|--------|------------|----------|--------------|
| **1. Bug Exists** | `main` | White | S, M, L | Medium boxes orderable despite 0 stock |
| **2. Bug Fixed** | `scenario-2` | Gradient | S, M, L | Stock validation enforced |
| **3. New Feature** | `scenario-3` | Gray | S, M, L, XL | XL boxes added across all services |

---

### Components

| Service | Technology | Database | Kafka Events |
|---------|-----------|----------|--------------|
| **Sales API** | FastAPI | PostgreSQL | **Produces:** `orders.created`, `errors.reported`<br>**Consumes:** `orders.shipped` |
| **Shipment API** | FastAPI | DynamoDB | **Produces:** `orders.shipped`, `errors.reported`<br>**Consumes:** `orders.created`, `errors.reported` |
| **Inventory API** | FastAPI | DynamoDB | **Produces:** `inventory.updated`<br>**Consumes:** `orders.created` |
| **Notification Service** | Python | N/A | **Consumes:** `orders.created`, `orders.shipped` |

---

### Event Flow Example

1. User orders 2x Small boxes → Sales API validates stock (HTTP call to Inventory) → Saves order to PostgreSQL → Publishes `orders.created`

2. Shipment API receives `orders.created` → Creates shipment record → Dashboard shows new order

3. Inventory API receives `orders.created` → Decrements stock: Small boxes (500 → 498)

4. Notification Service receives `orders.created` → Logs confirmation (email/SMS coming soon)

5. Warehouse adds tracking via Shipment Portal → Shipment API publishes `orders.shipped`

6. Sales API receives `orders.shipped` → Updates order status: pending → shipped → Sales Portal shows updated status

7. Notification Service receives `orders.shipped` → Logs shipping notification

8. Inventory team restocks via Inventory Portal → Inventory API publishes `inventory.updated` → *(Future: Notification Service alerts "Back in stock")*

9. Sales team reports shipping issue via Sales Portal → Sales API publishes `errors.reported` → Shipment API receives and displays on dashboard → *(Future: Notification Service alerts dev team)*

---

## Observability

### Grafana Dashboard

Access Grafana at http://localhost:3000 (login: admin/admin).

**Business Metrics:**
- Stock Validation Errors: demonstrates the scenario-1 bug
- Orders Created: success vs failed rates
- Items Ordered: product demand by type

**Infrastructure Metrics:**
- Service Status: health check for all microservices
- CPU Usage: per service
- Memory Usage: per service

> **Note:** The Kubernetes deployment currently uses default Grafana dashboards. A custom BoxCo dashboard ConfigMap is planned but not yet implemented.

<details>
<summary><b>Custom Prometheus Metrics</b></summary>
  
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

**All services expose:**
```
up{namespace="boxco", job="sales-api"}           # Service health (1=up, 0=down)
process_cpu_seconds_total{job="sales-api"}       # CPU usage
process_resident_memory_bytes{job="sales-api"}   # Memory usage
```
Prometheus scrapes every 2 seconds.

</details>

---

## CI/CD Pipeline

**Current State:** Demo scripts handle deployments. ArgoCD is installed as a deployment dashboard.

**What works today:**
- ✅ Local Docker registry (deployed by `full-stack-setup.sh`)
- ✅ Pre-built scenario images via `demo-setup.sh`
- ✅ One-command scenario switching via `demo-run.sh`
- ✅ ArgoCD dashboard shows deployment status (auto-sync enabled by `demo-run.sh`)
- ✅ NGINX Ingress Controller routes traffic to services
- ✅ Prometheus/Grafana validates changes with real metrics

**What's scaffolded (ready but not active):**
- 📝 Jenkins Kubernetes manifests (not deployed)
- 📝 Jenkinsfile pipeline structure (stages are stubs)
- 📝 Jenkins Configuration as Code (complete but unused)

<details>
<summary><b>🚧 Planned: Full GitOps Pipeline</b></summary>
	
To enable the full pipeline, the following would need to be completed:

1. **Jenkins deployment**: Apply `jenkins/k8s/` manifests
2. **Jenkinsfile implementation**: Replace echo stubs with actual docker build/push commands
3. **Webhook integration**: Connect GitHub → Jenkins → ArgoCD


```text
Developer pushes code
└─▶ GitHub webhook triggers Jenkins
└─▶ Jenkins builds & pushes images
└─▶ Jenkins updates K8s manifests with new tags
└─▶ ArgoCD detects Git changes, auto-syncs
└─▶ Grafana metrics reflect the change
```


</details>

---

<details>
<summary><b>Project Structure</b> (click to expand)</summary>

```
boxcompany/
├── README.md
├── docker-compose.yml
├── .env.example
├── .gitignore
├── grafana-values.yaml              # Helm values for Prometheus stack
│
├── config/                          # Database & Kafka initialization
│   ├── dynamodb/
│   │   ├── init.py
│   │   └── run.sh
│   ├── postgres/
│   │   └── init.sql
│   └── kafka/
│       └── schemas.json
│
├── scripts/                         # Setup & demo automation
│   ├── full-stack-setup.sh          # One-command K8s deployment
│   ├── demo-setup.sh                # Builds all scenario images
│   ├── demo-run.sh                  # Switches between scenarios
│   └── setup-cicd.sh                # CI/CD tooling setup
│
├── services/                        # Microservices
│   ├── sales-api/
│   │   ├── main.py
│   │   ├── database.py
│   │   ├── kafka_producer.py
│   │   ├── kafka_consumer.py
│   │   ├── requirements.txt
│   │   ├── Dockerfile
│   │   └── static/
│   │       └── index.html
│   ├── inventory-api/
│   │   ├── main.py
│   │   ├── dynamodb.py
│   │   ├── kafka_producer.py
│   │   ├── kafka_consumer.py
│   │   ├── requirements.txt
│   │   ├── Dockerfile
│   │   └── static/
│   │       └── index.html
│   ├── shipment-api/
│   │   ├── main.py
│   │   ├── dynamodb.py
│   │   ├── kafka.py
│   │   ├── requirements.txt
│   │   ├── Dockerfile
│   │   └── static/
│   │       └── index.html
│   └── notification-service/
│       ├── main.py
│       ├── notifications.py
│       ├── requirements.txt
│       └── Dockerfile
│
├── k8s/                             # Kubernetes manifests
│   ├── config/
│   │   └── postgres-init-configmap.yaml
│   ├── databases/
│   │   ├── dynamodb.yaml
│   │   ├── dynamodb-init-job.yaml
│   │   └── postgres.yaml
│   ├── kafka/
│   │   ├── kafka.yaml
│   │   └── zookeeper.yaml
│   ├── services/
│   │   ├── sales-api.yaml
│   │   ├── inventory-api.yaml
│   │   ├── shipment-api.yaml
│   │   ├── notification-service.yaml
│   │   └── ingress.yaml             # NGINX Ingress routes
│   ├── registry/
│   │   └── registry.yaml            # Local Docker registry
│   └── observability/
│       └── servicemonitor.yaml      # Prometheus scrape config
│
├── jenkins/                         # CI/CD pipeline (scaffolded, not deployed)
│   ├── Jenkinsfile                  # Pipeline stub: stages echo only
│   ├── plugins.txt
│   └── k8s/
│       ├── deployment.yaml
│       ├── jenkins-casc.yaml        # Configuration as Code (ready to use)
│       ├── namespace.yaml
│       ├── pvc.yaml
│       └── rbac.yaml
│
└── argo/                            # GitOps with ArgoCD
    ├── namespace.yaml
    ├── project.yaml
    └── applications/
        ├── boxco-infrastructure.yaml
        └── boxco-services.yaml
```

</details>

---

<details>
<summary><b>Tech Stack</b> (click to expand)</summary>

**Application**
- Language: Python 3.12
- Web Framework: FastAPI 0.111
- Python Libraries: SQLAlchemy 2.0, Boto3, prometheus-client, confluent-kafka

**Databases**
- PostgreSQL 16 - Customer orders (Sales API)
- DynamoDB Local 2.0 - Shipment tracking, inventory stock

**Event Streaming**
- Apache Kafka - Event backbone between services
  - Docker Compose: Confluent Platform 7.6 (Kafka 3.6)
  - Kubernetes: wurstmeister/kafka 2.8 (Confluent images had compatibility issues with Minikube)
- Zookeeper - Kafka coordination (KRaft mode planned for production)

**Container & Orchestration**
- Docker & Docker Compose - Local development
- Kubernetes (Minikube) - Container orchestration
- Helm 3.x - Kubernetes package manager

**Networking**
- NGINX Ingress Controller - Routes external traffic to services via hostnames

**Observability**
- Prometheus - Metrics collection (2s scrape interval)
- Grafana - Dashboards and visualization
- prometheus_client - Python instrumentation

**CI/CD**
- Shell Scripts - Current deployment automation
- Local Docker Registry - Image storage for K8s deployments
- Argo CD - Deployment dashboard with auto-sync (enabled by `demo-run.sh`)
- Jenkins - Scaffolded, not deployed

**Frontend**
- HTML, CSS, JavaScript - Responsive service portals

</details>
