# BoxCo — Order Management System

A portfolio project demonstrating event-driven microservices architecture using
real infrastructure tooling. Built to show how three internal teams — Sales,
Shipment, and Inventory — communicate through a shared Kafka event backbone
rather than calling each other's services or databases directly.

The project is structured around three scenarios, each deployed via a CI/CD
pipeline, to simulate how a development team would push bug fixes and new
features to a running system using GitOps practices.

> This README is updated as each piece is built. It only documents what currently works.

---

## What's been set up so far

- Project folder structure
- `docker-compose.yml` — defines all services for local development
- `config/postgres/init.sql` — Sales DB schema and Scenario 1 seed data
- `config/kafka/schemas.json` — Avro event schemas for all 4 Kafka topics
- `.env.example` — environment variable template

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
| Sales | PostgreSQL (RDS) | Relational — orders, customers, payments |
| Shipment | DynamoDB | Simple key lookups — order ID → tracking info |
| Inventory | DynamoDB | Simple key lookups — product ID → stock count |

### Scenarios (Git branches)

| Branch | Background | What it demonstrates |
|---|---|---|
| `scenario-1` | White | Medium boxes out of stock but still orderable (bug exists) |
| `scenario-2` | White → Gray | Stock check fix deployed via CI/CD pipeline |
| `scenario-3` | Gray | XL boxes added across all services |

### CI/CD pipeline

- **Jenkins** — builds and tests Docker images on every Git push
- **Argo CD** — watches Git and syncs changes to Kubernetes automatically
- **Kubernetes** — runs all services as containers across namespaced teams

---

## Project structure

```
boxcompany/
├── docker-compose.yml
├── .env.example
├── config/
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