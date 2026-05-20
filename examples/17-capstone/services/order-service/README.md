# order-service

The first data product of the §17 capstone, and the **template
every other service follows**. r21 scope: REST + Postgres only.
gRPC (r23), GraphQL (r24), and Kafka event publication (r25) are
added in later iterations.

## What it owns

The `orders` schema in the shared capstone Postgres database
(CAP-003). order-service is the only service that writes this
schema — that's the per-service data-ownership boundary.

## API (r21)

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness — process is up |
| GET | `/healthz` | Readiness — Postgres reachable |
| POST | `/orders` | Place an order |
| GET | `/orders` | List orders |
| GET | `/orders/{id}` | Fetch one order |

## Local development

Dependencies are managed with Poetry (CAP-001):

```bash
cd services/order-service
poetry install            # creates the venv, installs deps
poetry run pytest         # runs the unit tests (SQLite-backed, no Postgres needed)
```

To run the service locally against a port-forwarded Postgres:

```bash
# In one terminal: forward the in-cluster Postgres
kubectl port-forward -n capstone svc/capstone-postgres-rw 5432:5432

# In another: run with connection env pointing at the forward
PG_HOST=127.0.0.1 PG_PASSWORD=<from-secret> poetry run uvicorn app.main:app --port 8080
```

(Get the password from the CNPG secret:
`kubectl get secret capstone-postgres-app -n capstone -o jsonpath='{.data.password}' | base64 -d`)

## Build

The Containerfile is a UBI 9 Python 3.12 multi-stage build
(CAP-005). Build it into the capstone minikube profile:

```bash
minikube image build -p capstone -t order-service:v1 services/order-service
```

**Recommended:** commit `poetry.lock` for reproducible builds.
Generate it once with `poetry lock` (the Containerfile uses it
if present via a `poetry.lock*` glob).

## Source layout

```
services/order-service/
├── pyproject.toml      ← Poetry deps + metadata
├── poetry.lock         ← (generate with `poetry lock`, then commit)
├── Containerfile       ← UBI 9 multi-stage
├── README.md           ← this file
├── app/
│   ├── __init__.py
│   ├── config.py       ← settings from env (Postgres conn from CNPG secret)
│   ├── db.py           ← async engine + schema init (CAP-004: create_all)
│   ├── models.py       ← SQLAlchemy Order model (orders schema)
│   ├── schemas.py      ← Pydantic request/response (the API contract)
│   └── main.py         ← FastAPI app + endpoints
└── tests/
    └── test_orders.py  ← pytest, SQLite-backed (no Postgres needed)
```

## The template pattern

Every other service (inventory, payment, shipping, notification)
follows this same shape:

- Poetry `pyproject.toml`
- UBI 9 multi-stage `Containerfile`
- `app/{config,db,models,schemas,main}.py`
- own schema in the shared Postgres
- helm subchart under `charts/capstone/charts/<service>/`
- `/health` + `/healthz` probes

r22 parallelizes this across the remaining four services.
