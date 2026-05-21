---
title: Capstone decision log
description: Architecture decision records (ADR-lite) for the §17 capstone. Every iteration that makes a non-obvious choice adds an entry here.
render_with_liquid: false
---

# Capstone decision log

A running log of decisions made while building the §17 capstone.
Lightweight ADR format: each decision has a number, a date, a
status, the context that forced the choice, the decision itself,
and the consequences (good and bad).

When an iteration makes a choice worth remembering — a tool, a
pattern, a deferral — it gets an entry here rather than living
only in conversation. Superseded decisions are kept (struck
through in status) so the history stays legible.

Status values: **accepted**, **superseded by CAP-NNN**,
**deferred**, **proposed**.

---

## CAP-001 — Poetry for Python dependency management

- **Date:** r21
- **Status:** accepted
- **Context:** The five services are Python/FastAPI. We need
  reproducible dependency resolution, a lockfile, and a clean
  dev workflow. Options: raw `pip` + `requirements.txt`, `pip-tools`,
  Poetry, PDM, uv.
- **Decision:** Use **Poetry**. It builds on the standard
  `pyproject.toml`, adds a resolver and `poetry.lock` for
  reproducible builds, and gives a single command surface
  (`poetry add`, `poetry install`, `poetry lock`).
- **Consequences:**
  - (+) Reproducible builds via committed `poetry.lock`
  - (+) One tool for deps + venv + packaging metadata
  - (+) `poetry export` bridges cleanly to a pip-based runtime
    layer in the Containerfile
  - (−) Contributors need Poetry installed locally
    (`pipx install poetry`)
  - (−) `poetry.lock` must be regenerated and committed when
    dependencies change

## CAP-002 — CloudNativePG operator for Postgres, installed separately

- **Date:** r21
- **Status:** accepted
- **Context:** The capstone needs Postgres (per CAP-003, one
  cluster with a schema per service). Options: a plain
  single-replica `StatefulSet` + PVC (no operator, thinnest), or
  a Postgres operator (CloudNativePG, Zalando, Crunchy). The
  tutorial already teaches operators (Strimzi §12, KEDA, Istio
  §11), so a Postgres operator is consistent rather than a
  one-off pattern.
- **Decision:** Use the **CloudNativePG operator**, installed via
  a **separate setup script** (`scripts/setup-postgres-operator.sh`),
  the same way §11/§12 install their operators. The umbrella
  chart ships only the `Cluster` custom resource, not the
  operator itself.
- **Consequences:**
  - (+) Demonstrates the operator pattern consistently with the
    rest of the tutorial
  - (+) `Cluster` CR is declarative; rolling restarts, failover,
    and backups are operator-managed
  - (+) No StatefulSet→operator migration later (avoids the
    complexity-deferral the user explicitly flagged)
  - (−) **Installing the operator is a cluster-wide act**: it
    registers CRDs (cluster-scoped by definition) and runs a
    controller that watches across namespaces. This is
    different from deploying an app into a namespace — the
    §17 prose calls this out explicitly as a teaching point
  - (−) One more operator's readiness to wait on during the
    full-stack deploy

## CAP-003 — One Postgres cluster, one schema per service

- **Date:** r19 (restated here)
- **Status:** accepted
- **Context:** Each service is a data product owning its data
  (data-mesh principle 1). Options: a Postgres cluster per
  service (strong isolation, heavy), or one shared cluster with
  a schema per service (lighter, cross-service queries
  possible, cleaner lineage in OpenMetadata).
- **Decision:** **One shared Postgres cluster, one schema per
  service.** order-service owns the `orders` schema,
  inventory-service the `inventory` schema, etc., all within a
  single `capstone` application database.
- **Consequences:**
  - (+) Far smaller resource footprint on a single workstation
  - (+) Schema boundaries still enforce per-service ownership
  - (+) OpenMetadata can infer lineage within one database
  - (−) Not the strong isolation a per-service cluster gives;
    acceptable for a tutorial, called out as a non-production
    simplification

## CAP-004 — `create_all` for r21 skeleton; Alembic migrations deferred

- **Date:** r21
- **Status:** deferred
- **Context:** A data product owns its schema and its evolution.
  Proper schema migration uses a tool like Alembic. But the r21
  walking skeleton wants the thinnest verifiable slice.
- **Decision:** r21 uses SQLAlchemy `Base.metadata.create_all()`
  (create-if-not-exists) at service startup, after ensuring the
  service's schema exists. **Alembic migrations are deferred**
  until a later iteration where schema evolution becomes
  relevant (likely r25 when Kafka event schemas couple to table
  schemas).
- **Consequences:**
  - (+) Thinnest path to a verifiable r21 slice
  - (+) No migration tooling to wire up before the spine is proven
  - (−) `create_all` doesn't handle schema *changes* (only
    creation) — fine until schemas start evolving
  - (−) Revisit decision required before any schema change ships

## CAP-005 — UBI 9 python-312 for both build and runtime stages

- **Date:** r21
- **Status:** accepted
- **Context:** Per CONTRIBUTING.md, our images use UBI 9.
  §6 demonstrated a builder→minimal multi-stage pattern (ubi9
  builder → ubi9-minimal runtime) for nginx. For Python, the
  equivalent minimal runtime (`ubi9/python-312-minimal`) may or
  may not be a published image, and a missing image fails the
  build.
- **Decision:** Use **`ubi9/python-312` for both the builder and
  the runtime stage** of the Containerfile. Still multi-stage
  (builder has Poetry + build deps; runtime has only the venv +
  app code, no Poetry), but same base image both stages for
  reliability.
- **Consequences:**
  - (+) Reliable build — no dependency on an image whose
    existence we haven't verified
  - (+) Still demonstrates multi-stage separation of build-time
    vs runtime dependencies
  - (−) Larger runtime image than a true minimal base would
    produce. Optimization (minimal runtime via microdnf
    python install, or `ubi9/python-312-minimal` if confirmed
    available) deferred as a possible later enhancement; noted
    in §17 prose
  - **r21b amendment:** the UBI 9 python-312 image's default user
    (1001) cannot write to `/opt/venv` (`/opt` is root-owned),
    which broke the build with `Permission denied: '/opt/venv'`.
    Fix: the **builder stage runs as root** (`USER 0`) — it's
    discarded in a multi-stage build, so there's no security cost —
    while the **runtime stage** keeps `USER 1001:0` and copies the
    venv with `COPY --chown=1001:0`. Idiomatic multi-stage: relax
    the build stage, lock down the runtime stage. The non-root
    *runtime* guarantee CONTRIBUTING.md requires is preserved.
    Verified working on Fedora 44 (r21c).

## CAP-006 — Walking-skeleton-first, vertical slice over horizontal layers

- **Date:** r21
- **Status:** accepted
- **Context:** Two ways to start the capstone build: all five
  services as templates first (horizontal), or all platform
  infrastructure first (horizontal the other way). Both
  accumulate unverified surface area.
- **Decision:** Build a **thin vertical slice first** — r21 is
  order-service + the Postgres it actually needs, proven
  end-to-end (image build → helm deploy → operator-managed
  Postgres → service connects → REST works → smoke test
  asserts). Subsequent iterations widen (r22: the other four
  services) then deepen (r23+: each new capability brings its
  own infrastructure).
- **Consequences:**
  - (+) Integration risk surfaces early and locally, not late
    and tangled
  - (+) r22 becomes mechanical once r21's spine is verified
  - (+) Every iteration ends with something runnable and
    verifiable
  - (−) r21 is a larger single iteration than a pure
    "scaffold only" one — but the payoff is a proven spine

## CAP-007 — Image distribution via the in-cluster registry

- **Date:** r21a (original), revised r21c
- **Status:** accepted (the r21a/r21b `minikube image load` approach
  is **superseded**)
- **Context:** Getting a locally-built image to the kubelet under the
  rootless-podman + containerd driver combo proved unexpectedly hard.
  In sequence we hit: (1) `minikube image build` exited 0 but the
  image never entered the profile's containerd store; (2) `minikube
  image load <name>` reported "image not found" even with the
  fully-qualified `localhost/` name, because the lookup goes through
  the rootless podman socket and fails; (3) `podman save | ctr import`
  didn't read stdin as expected and dumped the image to the terminal.
  Each was a distinct facet of the same problem: there is no reliable
  *push-free* path into containerd on this driver.
- **Decision:** Use **minikube's built-in registry addon**. Build on
  the host with podman, push to the registry, and have deployments
  pull from it as normal images. Encapsulated in
  `scripts/build-image.sh <context> <name> <tag>`.
- **Consequences:**
  - (+) Reliable and **proven** end-to-end on Fedora 44 (r21c)
  - (+) Scales cleanly to all six capstone images — same one command
    each
  - (+) Standard `podman push` / kubelet pull; no containerd-internals
    plumbing
  - (−) Requires the registry addon enabled (now done in
    `setup-capstone-profile.sh`)
  - (−) Introduces the host/cluster port asymmetry — see CAP-009

## CAP-008 — Demo failure leaves resources in place and dumps diagnostics

- **Date:** r21a
- **Status:** accepted
- **Context:** r21's smoke test had `trap cleanup EXIT` that
  uninstalled order-service on *any* exit, including failure. When the
  pod failed to go Ready, the trap destroyed the evidence before it
  could be inspected, forcing a separate diagnostic re-run.
- **Decision:** Demo scripts clean up **only on success**. On failure
  they leave the resources in place and dump a diagnostic bundle
  inline (pod status, describe events, current + previous logs,
  registry catalog) — the pattern §11/§12 demos already use.
- **Consequences:**
  - (+) A failed run hands you the evidence directly
  - (+) Consistent with the established §11/§12 diagnostic-dump
    convention
  - (−) Failed runs leave cluster state that must be cleaned up
    manually (the dump prints the exact uninstall commands)

## CAP-009 — The registry port asymmetry (host vs cluster)

- **Date:** r21c
- **Status:** accepted
- **Context:** minikube's registry is reachable at two *different*
  addresses depending on where you are. With the podman driver, the
  host-side port is NOT 5000 — minikube assigns one (we observed
  41685) and explicitly warns to use it. Inside the cluster the
  kubelet reaches the registry at `localhost:5000`.
- **Decision:** `build-image.sh` discovers the host port dynamically
  (`podman port capstone | grep 5000/tcp`) and pushes to
  `127.0.0.1:<port>`. Charts reference the in-cluster address
  `localhost:5000/<service>` in `image.repository`.
- **Consequences:**
  - (+) No hardcoded port that drifts between machines
  - (−) Genuinely confusing the first time; documented prominently in
    the §17 "known friction" callout because every reader on this
    driver will hit it

## CAP-010 — MINIKUBE_ROOTLESS=true is mandatory

- **Date:** r21c
- **Status:** accepted
- **Context:** Several baffling failures (status reporting "unknown
  state", `minikube ssh` aborting, `image load` failing) all traced to
  one cause: when `MINIKUBE_ROOTLESS` is unset in the current shell,
  minikube routes host operations through `sudo podman`, which cannot
  see the rootless user's `capstone` container. The variable was set
  in the shell that *created* the profile but not in later shells, so
  the breakage appeared intermittently.
- **Decision:** Set rootless mode two ways for defence in depth:
  (1) persist it in minikube config (`minikube config set rootless
  true`, done in `setup-capstone-profile.sh`), and (2) `export
  MINIKUBE_ROOTLESS=true` at the top of every capstone script.
- **Consequences:**
  - (+) Eliminates an entire class of intermittent, hard-to-diagnose
    failures
  - (+) Config covers ad-hoc `minikube` commands; export covers
    scripts run in a bare shell
  - (−) Readers must understand this is load-bearing — covered in the
    §17 friction callout

## CAP-011 — Generate services from a template script; health-only skeletons in r22

- **Date:** r22
- **Status:** accepted
- **Context:** Four services remain (inventory, payment, shipping,
  notification), each following order-service's exact shape — same UBI 9
  Containerfile, same async-SQLAlchemy + FastAPI wiring, same subchart.
  Hand-writing each invites copy-paste drift, and a fix to the template
  would have to be applied four times.
- **Decision:** A **`scripts/scaffold-service.sh <name> <schema>`** stamps
  out a new service from the proven order-service template, parameterised
  by service name and Postgres schema. It auto-generates the `poetry.lock`
  (CAP-001) when poetry is present and refuses to overwrite an existing
  service. r22's generated services are **health-only skeletons**:
  `/health` (liveness), `/healthz` (readiness, checks Postgres), and
  startup schema creation — **no domain surface yet**. Domain endpoints
  arrive per-protocol in later iterations (REST/gRPC r23, GraphQL r24,
  Kafka r25). A generic **`demos/smoke-service.sh <name>`** builds, deploys,
  and asserts the probes for any scaffolded service. **notification-service
  gets the same `/health` surface** even though it will ultimately be
  Kafka-consumer-only, because a probe-able surface is useful for testing
  regardless (user decision, r22).
- **Consequences:**
  - (+) Uniform services with no drift; one template to maintain
  - (+) Each service is generated and verified **incrementally** (one at a
    time), so any wrinkle surfaces in isolation rather than as a pile
  - (+) notification-service is testable from the start
  - (−) Scaffolded services share identical dependencies, so their lock
    files are near-duplicates (harmless)
  - (−) The scaffold script itself becomes a thing to maintain as the
    service shape evolves — but that's one place, not five

---

## Decisions inherited from r19 (PRD planning)

These were resolved during r19 planning and accepted by the user.
Restated here so the decision log is the single source of truth.

| # | Decision | Choice |
|---|---|---|
| CAP-R19-1 | Metadata catalog | OpenMetadata (lighter than DataHub, Postgres-backed) |
| CAP-R19-2 | Postgres topology | One cluster, schema per service (see CAP-003) |
| CAP-R19-3 | Prefect deployment | OSS self-hosted |
| CAP-R19-4 | gRPC codegen | protobuf-first with `buf` |
| CAP-R19-5 | GraphQL | Federated gateway with Strawberry (Python) |
| CAP-R19-6 | Protocol per service | Per-service appropriate, not uniform |
| CAP-R19-7 | helm structure | Umbrella chart with subcharts |
| CAP-R19-8 | UBI vs upstream | UBI for our services; upstream for operators (documented) |
| CAP-R19-9 | Capstone profile | 24 GB / 16 CPU |
| CAP-R19-10 | OTEL Collector | Deployment with OTLP receiver |

---

## Pending decisions (not yet resolved)

- **Alembic introduction point** (follows from CAP-004) — which
  iteration introduces real migrations. Tentatively r25.
- **GraphQL gateway scaling** — single replica assumed; revisit
  if demos need more.
- **OpenMetadata ingestion mechanism** — official Apicurio
  connector vs OpenMetadata REST API ingestion. Resolve at r27
  when OpenMetadata lands.
