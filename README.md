# Box Company's Order Management System

A portfolio project demonstrating event-driven microservices architecture using
real infrastructure tooling. Built to show how three internal teams (Sales,
Shipment, and Inventory) communicate through a shared Kafka event backbone
rather than calling each other's services or databases directly.

The project is structured around three scenarios, each deployed via a CI/CD
pipeline, to simulate how a development team would push bug fixes and new
features to a running system using GitOps practices.

> This README is updated as each piece is built. It only documents what currently works.

---

## What's been set up so far

### Infrastructure
- `docker-compose.yml`: full local development stack with all services
- `config/postgres/init.sql`: Sales DB schema and Scenario 1 seed data
- `config/kafka/schemas.json`: Avro event schemas for all 4 Kafka topics
- `config/dynamodb/init.py`: DynamoDB table creation and inventory seeding
- `.env.example`: environment variable template

### Services (all running and tested)
- **Sales API**: accepts orders, checks stock, saves to PostgreSQL, publishes to Kafka
- **Shipment API**: consumes orders from Kafka, stores in DynamoDB, uploads tracking
- **Inventory API**: manages stock levels in DynamoDB, publishes stock changes to Kafka
- **Notification Service**: consumes Kafka events, sends order and shipment notifications

### Verified end-to-end flows
- Sales order submitted, saved to PostgreSQL, `orders.created` Kafka event published
- Shipment API consumes `orders.created` and order appears on shipment dashboard automatically
- Tracking uploaded and `orders.shipped` Kafka event published
- Notification Service consumes both events and logs confirmation email and SMS
- Scenario 1 bug confirmed: medium box orders accepted despite 0 stock

### Quick start

```bash
git clone https://github.com/simon-suh/boxcompany.git
cd boxcompany
git checkout scenario-1
cp .env.example .env
docker compose up --build
```

Once running, open:
- http://localhost:3001/docs: Sales API
- http://localhost:3002/docs: Shipment API
- http://localhost:3003/docs: Inventory API
- http://localhost:8080: Kafka UI

---

## Planned architecture

### Services

| Service | Language | Purpose |
|---|---|---|
| Sales API | Python / FastAPI | Accepts orders from Sales frontend, publishes to Kafka |
| Shipment API | Python / FastAPI | Consumes incoming orders, stores tracking info |
| Inventory API | Python / FastAPI | Manages stock levels, publishes stock changes |
| Notification Service | Python | Sends email and SMS to customers via Kafka events |

### Kafka topics

| Topic | Producer | Consumers |
|---|---|---|
| `orders.created` | Sales API | Shipment API, Notification Service |
| `orders.shipped` | Shipment API | Notification Service |
| `inventory.updated` | Inventory API | Sales API |
| `errors.reported` | Any service | Responsible team, dev alerting |

### Databases

| Service | Database | Why |
|---|---|---|
| Sales | PostgreSQL | Relational: orders, customers, payments |
| Shipment | DynamoDB | Simple key lookups: order ID to tracking info |
| Inventory | DynamoDB | Simple key lookups: product ID to stock count |

### Scenarios (Git branches)

| Branch | Background | What it demonstrates |
|---|---|---|
| `scenario-1` | White | Medium boxes out of stock but still orderable (bug exists) |
| `scenario-2` | White to Gray | Stock check fix deployed via CI/CD pipeline |
| `scenario-3` | Gray | XL boxes added across all services |

### CI/CD pipeline
- **Jenkins**: builds and tests Docker images on every Git push
- **Argo CD**: watches Git and syncs changes to Kubernetes automatically
- **Kubernetes**: runs all services as containers across namespaced teams

---

## Project structure

```
boxcompany/
├── docker-compose.yml
├── .env.example
├── config/
│   ├── dynamodb/
│   │   ├── init.py
│   │   └── run.sh
│   ├── postgres/
│   │   └── init.sql
│   └── kafka/
│       └── schemas.json
├── services/
│   ├── sales-api/
│   ├── shipment-api/
│   ├── inventory-api/
│   └── notification-service/
├── k8s/
├── jenkins/
└── argo/
```
