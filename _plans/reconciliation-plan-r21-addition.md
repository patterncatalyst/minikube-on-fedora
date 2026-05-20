# Reconciliation plan addition — r21 (order-service walking skeleton)

> Merge instructions: append the entry below to Section D of
> `_plans/reconciliation-plan.md`, after the r20 entry.

---

- **r21** (capstone walking skeleton — order-service end-to-end +
  CloudNativePG operator + Postgres Cluster CR) — first
  *runnable* capstone iteration. Proves the full vertical spine
  (CAP-006): image build → minikube cache → helm deploy →
  operator-managed Postgres → service connects → REST works →
  data persists → smoke test asserts. Establishes the template
  every other service follows.

  **Decisions captured this iteration** (in the new
  `_plans/capstone-decisions.md`):
  - CAP-001 Poetry for Python dependency management
  - CAP-002 CloudNativePG operator, installed separately
    (cluster-wide install called out as a teaching point)
  - CAP-003 one Postgres cluster, schema per service (restated
    from r19)
  - CAP-004 `create_all` for r21; Alembic migrations deferred
  - CAP-005 UBI 9 python-312 for both build + runtime stages
  - CAP-006 walking-skeleton-first (vertical slice over
    horizontal layers)
  - plus the ten r19 decisions back-filled as CAP-R19-1..10

  **What r21 ships:**
  - `_plans/capstone-decisions.md` — ADR-lite decision log,
    single source of truth for capstone choices
  - `examples/17-capstone/scripts/setup-postgres-operator.sh` —
    installs CloudNativePG via helm; prints the cluster-wide
    effects (CRDs registered, controller watching all
    namespaces)
  - `examples/17-capstone/charts/capstone/charts/postgres/` —
    CloudNativePG `Cluster` CR subchart (Chart.yaml,
    values.yaml, templates/cluster.yaml)
  - `examples/17-capstone/services/order-service/` — the
    service: Poetry pyproject.toml, UBI 9 multi-stage
    Containerfile, FastAPI app (config/db/models/schemas/main),
    pytest unit tests (SQLite-backed), README
  - `examples/17-capstone/charts/capstone/charts/order-service/`
    — helm subchart (Deployment with CNPG-secret-sourced
    Postgres env + Health Probes; Service)
  - `examples/17-capstone/demos/smoke-order.sh` — the
    walking-skeleton verification (build, deploy, exercise
    REST, query Postgres directly to confirm persistence,
    cleanup trap)
  - `_docs/17-capstone-r21-prose-insert.md` — §17 prose
    addition documenting order-service + the
    operator-is-cluster-wide teaching point (splice into
    `_docs/17-capstone.md`)

  **Patterns from *Kubernetes Patterns* (Ibryam & Huss)
  referenced in this iteration:**
  - Health Probe (liveness `/health`, readiness `/healthz`)
  - Predictable Demands (resource requests/limits; declared
    Postgres dependency)
  - Configuration Resource (Postgres creds from CNPG Secret
    via secretKeyRef)
  - Managed Lifecycle (clean connection-pool disposal on
    shutdown via FastAPI lifespan)

  **Validation performed in the build environment** (no
  minikube available there, so these are static checks):
  - All Python modules compile (`py_compile`)
  - All non-template YAML parses (pyyaml)
  - All helm templates have balanced `{{ }}` delimiters
  - deployment.yaml, service.yaml, cluster.yaml render to
    valid Kubernetes resources under placeholder substitution
  - All shell scripts pass `bash -n`

  **Verification status — UNVERIFIED pending real Fedora 44 run:**
  - `setup-postgres-operator.sh` installs the operator → unverified
  - `smoke-order.sh` passes end-to-end → unverified
  - order-service image builds with Poetry on UBI 9 → unverified
  - CloudNativePG provisions a working cluster on rootless
    podman minikube → unverified (flagged as a risk in r19 —
    this iteration is where we find out)
  - `poetry run pytest` passes locally → unverified

  These rows enter Section B as `unverified` and promote to
  `verified (Fedora 44)` only after the user runs the smoke
  test and reports the result. Verified count stays at **107**
  until then.

  **Known risk being tested in r21:** CloudNativePG's behavior
  on rootless-podman minikube specifically. The operator
  assumes a working default StorageClass; minikube provides
  `standard` via its storage-provisioner addon, which should
  satisfy the `Cluster` CR's PVC. If the PVC doesn't bind, the
  fix is likely a `storageClass:` override in the postgres
  subchart values — a quick r21a if needed.

  **Notes for r22:**
  - The four remaining services (inventory, payment, shipping,
    notification) follow order-service's exact shape. Strongly
    consider a `scripts/scaffold-service.sh` that stamps out
    the per-service skeleton (pyproject, Containerfile, app/*,
    subchart) from order-service as a template, to make r22
    mechanical
  - notification-service is the odd one — Kafka-consumer-only,
    no REST surface — so its skeleton differs. Hold it for r25
    (Kafka) rather than forcing a REST shape on it in r22,
    OR ship it in r22 with a minimal /health-only HTTP surface
    and wire the Kafka consumer in r25. Decide at r22 start.

  Verified row count holds at **107**.
