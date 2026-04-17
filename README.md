# Box Company's Order Management System

A portfolio project demonstrating event-driven microservices architecture using real infrastructure tooling. Built to show three internal teams (Sales, Shipment, and Inventory) communicating through a shared Kafka event backbone rather than calling each other's services or databases directly. The system includes three deployment scenarios that demonstrate bug introduction, fix, and feature rollout — deployed via a fully automated GitOps pipeline powered by Jenkins and Argo CD.

**Run locally with Docker Compose (Option 1) or explore the full Kubernetes stack with CI/CD and observability (Option 2).**

---

## Quick Start

### Prerequisites

This project supports two deployment modes:
- **Option 1: Docker Compose** for quick local setup (~5 min)
- **Option 2: Kubernetes** for full stack with CI/CD and observability (~25-30 min)

**Required for both options:**
- Git
- Docker Desktop 4.0+ (or Docker Engine 20.10+ with Docker Compose plugin)

**Additional requirements for Kubernetes:**
- Minikube 1.30+
- kubectl 1.27+
- Helm 3.12+
- A GitHub Personal Access Token with `repo` scope ([create one here](https://github.com/settings/tokens))

<details>
<summary><b>Install prerequisites (click to expand)</b></summary>

#### For Docker Compose (Option 1)

**Docker Desktop** (includes Docker Engine and Compose):
- [Download Docker Desktop](https://www.docker.com/products/docker-desktop/)

That's it — you're ready for Option 1.

---

#### For Kubernetes (Option 2)

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

### Option 2: Kubernetes

**Best for:** Exploring a complete DevOps workflow, verifying a GitOps CI/CD pipeline, observability  
**Time:** ~25-30 minutes (one-time setup)

<details>
<summary><b>Kubernetes Setup</b></summary>

```bash
# Clone the repo
git clone https://github.com/simon-suh/boxcompany.git
cd boxcompany

# Run setup (interactive — prompts for GitHub credentials)
./scripts/setup.sh
```

When prompted:
- **GitHub username** — your GitHub username
- **GitHub token** — Personal Access Token with `repo` scope
- **Jenkins admin password** — choose a password or press Enter for `admin`

Setup takes ~25-30 minutes. It will:
1. Start Minikube
2. Deploy all infrastructure (registry, databases, Kafka, Argo CD, Grafana)
3. Deploy Jenkins with full Configuration as Code
4. Register a GitHub webhook via smee.io for instant build triggers
5. Pre-build all scenario images in the background
6. Start all port-forwards
7. Save all credentials to `credentials.txt`

**WSL2 Users:** After setup completes, add these entries to your Windows hosts file.  
Run in PowerShell as Administrator:
```powershell
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "127.0.0.1 sales.boxco.local shipment.boxco.local inventory.boxco.local"
```

</details>

<details>
<summary><b>Exploring the CI/CD Pipeline</b></summary>

Before exploring, restart port-forwards to ensure everything is accessible:

```bash
./scripts/start.sh
```

**Access the portals:**
| Portal | URL | Credentials |
|--------|-----|-------------|
| Sales | http://sales.boxco.local:8080 | — |
| Shipment | http://shipment.boxco.local:8080 | — |
| Inventory | http://inventory.boxco.local:8080 | — |
| Jenkins | http://localhost:8082 | admin / see `credentials.txt` |
| Argo CD | http://localhost:8081 | admin / see `credentials.txt` |
| Grafana | http://localhost:3000 | admin / admin |
| Prometheus | http://localhost:9090 | — |

> **Note:** `credentials.txt` is auto-generated in your project root by `setup.sh`. It contains all passwords and access URLs.

---

### Initial Scenario: Show the Bug
Open http://sales.boxco.local:8080. Medium boxes are orderable despite being out of stock. This is the bug on the `main` branch.

### Scenario-2: Fix the Bug
```bash
git push origin scenario-2
```
- GitHub fires a webhook → Jenkins triggers automatically
- Jenkins confirms scenario-2 images are cached → skips build (~30 seconds total)
- Jenkins commits updated image tags to `main`
- Argo CD detects the change and syncs to the cluster
- Out of stock items are no longer orderable


### Scenario-3: New Item Rollout
```bash
git push origin scenario-3
```
- Same pipeline flow as above
- XL boxes added across all portals


You can verify each step by watching Jenkins (builds), Argo CD (sync status), and Grafana (metrics).

</details>

---

<details>
<summary><b>Pipeline Reset</b></summary>

### Normal Reset
After running through all scenarios, `main` will have scenario-3 image tags committed by Jenkins. To reset back to Scenario 1:

**Jenkins → boxco-pipeline → main → Build Now**

Jenkins detects the scenario-1 images are already cached in the registry and simply commits the scenario-1 tags back to `main`. Argo CD syncs automatically. No manual steps needed.

### After Minikube Restart
If you restarted your machine (but did not delete Minikube), the registry images are preserved on the PVC but port-forwards need restarting:

```bash
./scripts/start.sh
```

If `start.sh` reports the registry is empty, trigger builds for all 3 branches in Jenkins:
- Jenkins → boxco-pipeline → main → Build Now
- Jenkins → boxco-pipeline → scenario-2 → Build Now
- Jenkins → boxco-pipeline → scenario-3 → Build Now

Then trigger main again to reset manifests back to scenario-1.

</details>

---

## CI/CD Architecture
 
How a git push becomes a live deployment:
 
1. Push to `scenario-2` or `scenario-3`
2. GitHub fires a webhook to the smee.io public relay channel
3. The smee-client pod inside the cluster receives the event and forwards it to Jenkins
4. Jenkins checks if images are already cached in the local registry — if yes, skips the build entirely
5. Jenkins clones `main`, patches image tags and SCENARIO env vars in `k8s/services/`
6. Jenkins commits the manifest update back to `main` with `[skip ci]` and pushes
7. Argo CD detects the change on `main` and auto-syncs to the cluster
8. Kubernetes rolls out new pods — the browser reflects the new scenario within ~30 seconds
**Key design decisions:**
 
- **Branch-named image tags** (`scenario-1`, `scenario-2`, `scenario-3`) instead of `latest` — each scenario's image is independently cacheable, making demo transitions near-instant after the first build
- **`[skip ci]` guard** — prevents Jenkins from triggering itself when it commits manifest updates back to `main`, avoiding an infinite loop
- **Kubernetes Downward API** — injects the node IP into the builder pod at startup so the registry address is resolved automatically on any machine, with no hardcoded IPs
- **Lockable resource on manifest update** — prevents race conditions when multiple branches build simultaneously; without it, parallel builds can overwrite each other's manifest commits
- **smee.io webhook bridge** — relays GitHub push events to Jenkins running on localhost with no public IP or tunneling required

---

## Scripts Reference

| Script | When to run | What it does |
|--------|-------------|--------------|
| `scripts/setup.sh` | Once, on first clone | Full infrastructure setup + Jenkins deploy + image pre-build |
| `scripts/start.sh` | After any machine restart | Restarts port-forwards, verifies health, prints URLs |

---

### The Three Scenarios

| Scenario | Branch | Background | Products | Demonstrates |
|----------|--------|------------|----------|--------------|
| **1. Bug Exists** | `main` | White | S, M, L | Medium boxes orderable despite 0 stock |
| **2. Bug Fixed** | `scenario-2` | Gradient | S, M, L | Stock validation enforced |
| **3. New Feature** | `scenario-3` | Gray | S, M, L, XL | XL boxes added across all services |

---

## Components

| Service | Technology | Database | Kafka Events |
|---------|-----------|----------|--------------|
| **Sales API** | FastAPI | PostgreSQL | **Produces:** `orders.created`, `errors.reported`<br>**Consumes:** `orders.shipped` |
| **Shipment API** | FastAPI | DynamoDB | **Produces:** `orders.shipped`, `errors.reported`<br>**Consumes:** `orders.created`, `errors.reported` |
| **Inventory API** | FastAPI | DynamoDB | **Produces:** `inventory.updated`<br>**Consumes:** `orders.created` |
| **Notification Service** | Python | N/A | **Consumes:** `orders.created`, `orders.shipped` |

---

## Event Flow Example

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
├── scripts/
│   ├── setup.sh                     # One-time full stack setup
│   └── start.sh                     # Restarts port-forwards and verifies health
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
│   │   └── ingress.yaml
│   ├── registry/
│   │   └── registry.yaml            # Local Docker registry with PVC
│   └── observability/
│       └── servicemonitor.yaml
│
├── jenkins/
│   ├── Jenkinsfile                  # Full CI/CD pipeline
│   ├── plugins.txt                  # Jenkins plugin list
│   └── k8s/
│       ├── deployment.yaml          # Jenkins deployment with plugin init container
│       ├── jenkins-casc.yaml        # Configuration as Code
│       ├── namespace.yaml
│       ├── pvc.yaml
│       ├── rbac.yaml
│       ├── service.yaml
│       └── smee.yaml                # Webhook relay client
│
└── argo/                            # GitOps with Argo CD
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
- Jenkins - CI pipeline running on Kubernetes with ephemeral agent pods; builds Docker images and commits manifest updates
- Argo CD - GitOps continuous delivery; auto-syncs cluster state when manifests change on `main`
- smee.io - Webhook relay bridge connecting GitHub push events to Jenkins running on localhost
- Local Docker Registry - PVC-backed image storage; images persist across Minikube restarts
**Frontend**
- HTML, CSS, JavaScript - Responsive service portals

</details>
