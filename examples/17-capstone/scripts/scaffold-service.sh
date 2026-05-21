#!/usr/bin/env bash
#
# scaffold-service.sh — stamp out a new capstone service skeleton from the
# proven order-service template (r21c).
#
# What it generates (a "walking skeleton" service — CAP-006):
#   - services/<name>-service/         FastAPI app with /health + /healthz,
#                                       async SQLAlchemy wired to its own
#                                       Postgres schema, UBI 9 Containerfile
#   - charts/capstone/charts/<name>-service/   helm subchart (Deployment +
#                                       Service), image pulled from the
#                                       in-cluster registry (CAP-009)
#
# What it deliberately does NOT generate (added in later iterations):
#   - domain tables / REST CRUD (r23+), gRPC (r23), GraphQL (r24),
#     Kafka producers/consumers (r25). r22 proves each service stands up,
#     reaches its schema, and answers probes. Domain surface comes next.
#
# The generated service is uniform with order-service so the whole mesh
# follows one shape. notification-service gets the same /health surface even
# though it will ultimately be Kafka-consumer-only — a probe-able surface is
# useful for testing regardless (user decision, r22).
#
# Usage:
#   ./scripts/scaffold-service.sh <name> <schema>
# Examples:
#   ./scripts/scaffold-service.sh inventory inventory
#   ./scripts/scaffold-service.sh payment payments
#   ./scripts/scaffold-service.sh shipping shipping
#   ./scripts/scaffold-service.sh notification notifications
#
# Refuses to overwrite an existing service directory (so order-service and
# any already-scaffolded service are safe; re-running is a no-op error).

set -euo pipefail

BASE="${1:?usage: scaffold-service.sh <name> <schema>   e.g. inventory inventory}"
SCHEMA="${2:?usage: scaffold-service.sh <name> <schema>   (schema is often the plural, e.g. payment payments)}"
SERVICE="${BASE}-service"

# Resolve repo-relative paths from the example root (parent of scripts/).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVC_DIR="${ROOT}/services/${SERVICE}"
CHART_DIR="${ROOT}/charts/capstone/charts/${SERVICE}"

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

# Validate the name: lowercase letters, digits, hyphens (DNS-1123-ish).
[[ "$BASE"   =~ ^[a-z][a-z0-9-]*$ ]] || fail "name '$BASE' must be lowercase alphanumeric/hyphen, starting with a letter"
[[ "$SCHEMA" =~ ^[a-z][a-z0-9_]*$ ]] || fail "schema '$SCHEMA' must be lowercase alphanumeric/underscore, starting with a letter"
[[ -d "$SVC_DIR" ]]   && fail "service dir already exists: $SVC_DIR (refusing to overwrite)"
[[ -d "$CHART_DIR" ]] && fail "chart dir already exists: $CHART_DIR (refusing to overwrite)"

step "Scaffolding ${SERVICE} (schema: ${SCHEMA})"
mkdir -p "${SVC_DIR}/app" "${SVC_DIR}/tests" "${CHART_DIR}/templates"

# ─── services/<service>/pyproject.toml ───────────────────────────────────────
cat > "${SVC_DIR}/pyproject.toml" <<'EOF'
[tool.poetry]
name = "__SERVICE__"
version = "0.1.0"
description = "__SERVICE__ data product for the §17 capstone — health skeleton (domain surface added in later iterations)"
authors = ["patterncatalyst"]
readme = "README.md"
package-mode = false

[tool.poetry.dependencies]
python = "^3.12"
fastapi = "^0.115.0"
uvicorn = { extras = ["standard"], version = "^0.32.0" }
sqlalchemy = { extras = ["asyncio"], version = "^2.0.36" }
asyncpg = "^0.30.0"
pydantic = "^2.9.0"
pydantic-settings = "^2.6.0"

[tool.poetry.group.dev.dependencies]
pytest = "^8.3.0"
pytest-asyncio = "^0.24.0"
httpx = "^0.27.0"

[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"

[tool.pytest.ini_options]
asyncio_mode = "auto"
EOF

# ─── services/<service>/Containerfile (r21b root-builder; proven) ─────────────
cat > "${SVC_DIR}/Containerfile" <<'EOF'
# __SERVICE__ Containerfile — UBI 9 multi-stage build (CAP-005).
#
# The BUILDER stage runs as root so it can write /opt/venv (the UBI default
# user 1001 cannot — /opt is root-owned). The builder image is discarded, so
# there's no security cost. The RUNTIME stage enforces the non-root user
# (1001:0) and only reads/executes the copied venv. (CAP-005 r21b amendment.)
#
# Per CONTRIBUTING.md: UBI 9 base, runtime as USER 1001:0.

# ─── Builder (runs as root; image discarded) ─────────────────────────────────
FROM registry.access.redhat.com/ubi9/python-312:latest AS builder

USER 0
WORKDIR /build

RUN pip install --no-cache-dir "poetry==1.8.4" "poetry-plugin-export==1.8.0"

COPY pyproject.toml poetry.lock* ./

RUN poetry export --without-hashes --only main -f requirements.txt -o requirements.txt \
    && python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# ─── Runtime (non-root) ──────────────────────────────────────────────────────
FROM registry.access.redhat.com/ubi9/python-312:latest AS runtime

WORKDIR /opt/app-root/src

COPY --from=builder --chown=1001:0 /opt/venv /opt/venv
COPY --chown=1001:0 app/ ./app/

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER 1001:0

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
EOF

# ─── services/<service>/README.md ─────────────────────────────────────────────
cat > "${SVC_DIR}/README.md" <<'EOF'
# __SERVICE__

A §17 capstone data product. Owns the `__SCHEMA__` Postgres schema
(per-service ownership, CAP-003).

**r22 scope (skeleton):** the service starts, ensures its schema exists, and
serves health probes:

- `GET /health` — liveness (process up)
- `GET /healthz` — readiness (Postgres reachable)

Its domain surface is added in later iterations (REST/gRPC/GraphQL/Kafka as
appropriate to the service).

## Build + deploy

```bash
# from examples/17-capstone/
./scripts/build-image.sh services/__SERVICE__ __SERVICE__ v1
helm upgrade --install __SERVICE__ charts/capstone/charts/__SERVICE__ -n capstone
kubectl rollout status deployment/__SERVICE__ -n capstone --timeout=120s
```

Or run the health smoke test, which does all of the above and asserts the
probes: `./demos/smoke-service.sh __BASE__`
EOF

# ─── services/<service>/app/__init__.py ───────────────────────────────────────
: > "${SVC_DIR}/app/__init__.py"

# ─── services/<service>/app/config.py ─────────────────────────────────────────
cat > "${SVC_DIR}/app/config.py" <<'EOF'
"""Configuration for __SERVICE__, sourced from environment variables.

In-cluster, the Postgres connection comes from the CloudNativePG-generated
Secret (`capstone-postgres-app`), surfaced as env vars by the helm subchart.
Locally, the defaults allow running against a port-forwarded Postgres.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="", case_sensitive=False)

    # Service identity
    service_name: str = "__SERVICE__"
    service_schema: str = "__SCHEMA__"

    # Postgres connection. In-cluster these come from the CNPG app Secret.
    pg_host: str = "127.0.0.1"
    pg_port: int = 5432
    pg_user: str = "capstone_app"
    pg_password: str = "changeme"
    pg_database: str = "capstone"

    # Server
    host: str = "0.0.0.0"
    port: int = 8080

    @property
    def database_url(self) -> str:
        """Async SQLAlchemy URL using the asyncpg driver."""
        return (
            f"postgresql+asyncpg://{self.pg_user}:{self.pg_password}"
            f"@{self.pg_host}:{self.pg_port}/{self.pg_database}"
        )


settings = Settings()
EOF

# ─── services/<service>/app/models.py (Base only — no tables yet) ─────────────
cat > "${SVC_DIR}/app/models.py" <<'EOF'
"""SQLAlchemy declarative base for __SERVICE__.

r22 skeleton: no tables yet. The service's schema (`__SCHEMA__`) is created
at startup (see db.init_schema), ready for domain tables in a later
iteration. When this service's domain model lands, add table classes here
bound to `settings.service_schema` to keep the per-service ownership boundary
(CAP-003) explicit, e.g.:

    class Widget(Base):
        __tablename__ = "widgets"
        __table_args__ = {"schema": settings.service_schema}
        ...
"""

from __future__ import annotations

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
EOF

# ─── services/<service>/app/db.py (generic; same wiring as order-service) ─────
cat > "${SVC_DIR}/app/db.py" <<'EOF'
"""Database wiring for __SERVICE__.

Async SQLAlchemy 2.0 engine + session factory, plus a startup helper that
ensures the service's schema exists before creating any tables.

CAP-004: create-if-not-exists via metadata.create_all. Schema *evolution*
(Alembic) is deferred to a later iteration.
"""

from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.config import settings
from app.models import Base

engine = create_async_engine(settings.database_url, echo=False, pool_pre_ping=True)

SessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def init_schema() -> None:
    """Create the service's schema (and any tables) if they don't exist."""
    async with engine.begin() as conn:
        await conn.execute(
            text(f'CREATE SCHEMA IF NOT EXISTS "{settings.service_schema}"')
        )
        await conn.run_sync(Base.metadata.create_all)


async def check_db() -> bool:
    """Lightweight connectivity check for the readiness probe."""
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False


async def dispose() -> None:
    await engine.dispose()
EOF

# ─── services/<service>/app/main.py (health surface only) ─────────────────────
cat > "${SVC_DIR}/app/main.py" <<'EOF'
"""__SERVICE__ — a §17 capstone data product (r22 skeleton).

r22 scope: the service stands up, connects to its Postgres schema
(`__SCHEMA__`), and serves health probes. Its domain surface (REST/gRPC/
GraphQL/Kafka, as appropriate to this service) is added in later iterations.

Endpoints:
  GET /health   — liveness (process is up)
  GET /healthz  — readiness (can reach Postgres)
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, status

from app.config import settings
from app.db import check_db, dispose, init_schema


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: ensure the service's schema (and any tables) exist.
    await init_schema()
    yield
    # Shutdown: dispose the connection pool cleanly (Managed Lifecycle
    # pattern — Kubernetes Patterns, Ibryam & Huss).
    await dispose()


app = FastAPI(
    title="__SERVICE__",
    version="0.1.0",
    description="__SERVICE__ data product for the §17 capstone data mesh (skeleton).",
    lifespan=lifespan,
)


@app.get("/health", tags=["ops"])
async def health() -> dict[str, str]:
    """Liveness: the process is running. Always 200 if we can respond."""
    return {"status": "ok", "service": settings.service_name}


@app.get("/healthz", tags=["ops"])
async def healthz() -> dict[str, str]:
    """Readiness: we can serve traffic (Postgres reachable)."""
    if not await check_db():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="database unreachable",
        )
    return {"status": "ready", "service": settings.service_name}
EOF

# ─── services/<service>/tests/__init__.py + a tiny health test ────────────────
: > "${SVC_DIR}/tests/__init__.py"
cat > "${SVC_DIR}/tests/test_health.py" <<'EOF'
"""Liveness endpoint test for __SERVICE__ — no DB required.

Readiness (/healthz) is exercised in-cluster by the smoke test, since it
needs a real Postgres. This unit test just confirms the app wires up and
/health answers.
"""

from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient


@pytest.mark.asyncio
async def test_health_ok():
    # Import inside the test so collection doesn't trigger the DB lifespan.
    from app.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["service"] == "__SERVICE__"
EOF

# ─── charts/capstone/charts/<service>/Chart.yaml ──────────────────────────────
cat > "${CHART_DIR}/Chart.yaml" <<'EOF'
apiVersion: v2
name: __SERVICE__
description: __SERVICE__ data product — FastAPI service backed by the capstone Postgres (__SCHEMA__ schema). r22 ships the health skeleton; domain surface added later.
type: application
version: 0.1.0
appVersion: "0.1.0"
EOF

# ─── charts/capstone/charts/<service>/values.yaml ─────────────────────────────
cat > "${CHART_DIR}/values.yaml" <<'EOF'
# __SERVICE__ subchart values.

replicas: 1

image:
  # In-cluster registry address (CAP-009). build-image.sh pushes to
  # 127.0.0.1:<port>; the kubelet pulls from localhost:5000.
  repository: localhost:5000/__SERVICE__
  tag: v1
  pullPolicy: IfNotPresent

service:
  port: 80
  targetPort: 8080

# Postgres connection. The CloudNativePG operator generates a Secret named
# "<cluster>-app" holding the app user's credentials; we reference it by key.
postgres:
  clusterName: capstone-postgres
  appSecret: capstone-postgres-app
  schema: __SCHEMA__

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    memory: 256Mi

# /health is liveness; /healthz is readiness (checks Postgres).
probes:
  liveness:
    path: /health
    initialDelaySeconds: 5
    periodSeconds: 10
  readiness:
    path: /healthz
    initialDelaySeconds: 5
    periodSeconds: 5
EOF

# ─── charts/capstone/charts/<service>/templates/deployment.yaml ───────────────
cat > "${CHART_DIR}/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: __SERVICE__
  namespace: {{ .Release.Namespace }}
  labels:
    app.kubernetes.io/name: __SERVICE__
    app.kubernetes.io/part-of: capstone
    app.kubernetes.io/component: data-product
spec:
  replicas: {{ .Values.replicas }}
  selector:
    matchLabels:
      app.kubernetes.io/name: __SERVICE__
  template:
    metadata:
      labels:
        app.kubernetes.io/name: __SERVICE__
        app.kubernetes.io/part-of: capstone
    spec:
      containers:
        - name: __SERVICE__
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
          env:
            - name: SERVICE_SCHEMA
              value: {{ .Values.postgres.schema | quote }}
            # Predictable Demands pattern: declare exactly what we need.
            - name: PG_HOST
              value: "{{ .Values.postgres.clusterName }}-rw.{{ .Release.Namespace }}.svc.cluster.local"
            - name: PG_PORT
              value: "5432"
            - name: PG_DATABASE
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.postgres.appSecret }}
                  key: dbname
            - name: PG_USER
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.postgres.appSecret }}
                  key: username
            - name: PG_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.postgres.appSecret }}
                  key: password
          resources:
            requests:
              cpu: {{ .Values.resources.requests.cpu }}
              memory: {{ .Values.resources.requests.memory }}
            limits:
              memory: {{ .Values.resources.limits.memory }}
          # Health Probe pattern (Kubernetes Patterns, Ibryam & Huss).
          livenessProbe:
            httpGet:
              path: {{ .Values.probes.liveness.path }}
              port: http
            initialDelaySeconds: {{ .Values.probes.liveness.initialDelaySeconds }}
            periodSeconds: {{ .Values.probes.liveness.periodSeconds }}
          readinessProbe:
            httpGet:
              path: {{ .Values.probes.readiness.path }}
              port: http
            initialDelaySeconds: {{ .Values.probes.readiness.initialDelaySeconds }}
            periodSeconds: {{ .Values.probes.readiness.periodSeconds }}
EOF

# ─── charts/capstone/charts/<service>/templates/service.yaml ──────────────────
cat > "${CHART_DIR}/templates/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: __SERVICE__
  namespace: {{ .Release.Namespace }}
  labels:
    app.kubernetes.io/name: __SERVICE__
    app.kubernetes.io/part-of: capstone
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: __SERVICE__
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
EOF

# ─── Substitute placeholders across everything just generated ─────────────────
# __SERVICE__ and __SCHEMA__ are safe to sed (they won't collide with helm's
# {{ }} templating, which we left literal in quoted heredocs above).
step "Substituting placeholders (__SERVICE__=${SERVICE}, __SCHEMA__=${SCHEMA})"
find "$SVC_DIR" "$CHART_DIR" -type f -print0 | while IFS= read -r -d '' f; do
    sed -i "s/__SERVICE__/${SERVICE}/g; s/__SCHEMA__/${SCHEMA}/g; s/__BASE__/${BASE}/g" "$f"
done

step "Done — scaffolded ${SERVICE}"

# ─── Generate the lockfile so the image build works out of the box ───────────
# The Containerfile's `poetry export` step requires a poetry.lock. order-service
# has one committed (CAP-001); generate this service's now if poetry is on PATH.
if command -v poetry >/dev/null 2>&1; then
    step "Generating poetry.lock (CAP-001 — reproducible builds)"
    ( cd "$SVC_DIR" && poetry lock ) \
        && printf '    ✓ poetry.lock written\n' \
        || printf '    ! poetry lock failed — run `cd %s && poetry lock` before building\n' "$SVC_DIR"
else
    printf '\n  ! poetry not on PATH — before building, run:\n      cd %s && poetry lock\n' "$SVC_DIR"
fi

cat <<EOF

  services/${SERVICE}/        FastAPI health skeleton (schema: ${SCHEMA})
  charts/capstone/charts/${SERVICE}/   helm subchart

Next:
  1. Build + deploy + assert the probes:
       ./demos/smoke-service.sh ${BASE}
  2. When green, commit, then scaffold the next service.

EOF
