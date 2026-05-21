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

## CAP-012 — Media-type versioning for REST; protocol comparison by fitness, not hierarchy

- **Date:** r23 (recorded ahead of the REST/gRPC/GraphQL work)
- **Status:** accepted
- **Context:** The capstone runs four protocols deliberately (REST at the
  edge, gRPC for synchronous internal calls, GraphQL for federated
  cross-domain reads, Kafka for async events). At some point the prose has
  to explain *why* each is used where it is, and the REST surfaces have to
  make a versioning choice. The common default — URI versioning (`/v1/orders`)
  — is convenient and familiar, but it is in genuine tension with REST's
  hypermedia constraint, not merely inelegant with it.
- **Decision (two coupled commitments):**

  1. **Our REST surfaces version via media type / content negotiation**
     (e.g. `Accept: application/vnd.capstone.order.v1+json`), **not** via
     the URI. We want a genuinely *RESTful* implementation, and **URI
     versioning precludes that**: baking `/v1/` into the path makes the
     version out-of-band knowledge the client must hardcode, which is
     exactly what HATEOAS exists to eliminate — a client can no longer
     discover its way from resource to resource purely by following the
     links the server hands back, because every link is pinned to a version
     namespace decided off-band. Versioning in the media type keeps the
     uniform-interface constraint intact and lets the hypermedia examples
     (link relations for `next`/`prev` pagination, action discovery) stay
     honest. The cost — content negotiation is fiddlier to operate than a
     path segment — is acknowledged in the prose as part of the tradeoff,
     not hidden.

  2. **The protocol comparison is framed by "which constraint matters for
     this interaction," never as a ranking.** It is not a hit piece on any
     protocol, and not a one-size-fits-all verdict. Each is presented as
     *differently shaped*, strongest for its own reasons:
     - **REST** — uniquely strong at HTTP caching and at hypermedia
       (HATEOAS, link-driven pagination). Can do paging and discovery well;
       the usual URI-versioning habit is what quietly forecloses the
       hypermedia half, which is why we version by media type.
     - **gRPC** — the capabilities REST structurally lacks: bidirectional
       and server/client **streaming**, and efficient multiplexed calls
       over HTTP/2. Our order→inventory synchronous call uses it.
     - **GraphQL** — client-specified response shape (no over-/under-fetch
       across what would be multiple REST round-trips) and **federation**
       for cross-domain queries, which neither REST nor gRPC addresses.
     The capstone is positioned to *demonstrate* this rather than assert
     it: by r25 all four are live, so the comparison can point at running
     code. The URI-versioning-vs-HATEOAS tension is the concrete worked
     example that keeps the discussion defensible instead of hand-wavy.

- **Consequences:**
  - (+) The tutorial *practices* what it argues — the REST surfaces model
    the harder-but-correct hypermedia-compatible path
  - (+) The eventual comparison prose has a clear, sourced editorial spine:
    fitness-for-interaction, with a real example, not protocol tribalism
  - (−) Media-type versioning is less conventional and more work to
    implement and document than URI versioning; we take that on
    deliberately and explain why
- **References** (inform the REST patterns and the comparison stance):
  - Amundsen, *RESTful Web API Patterns and Practices Cookbook* (O'Reilly)
  - Gough, Bryant & Auburn, *Mastering API Architecture* (O'Reilly)
  - Kleppmann & Riccomini, *Designing Data-Intensive Applications*, 2nd ed.
    (O'Reilly)
  - Higginbotham, *Principles of Web API Design* (Addison-Wesley)
  - Zimmermann, Stocker, Lübke et al., *Patterns for API Design*
    (Addison-Wesley)

## CAP-013 — gRPC codegen layout: protos in-repo, per-service committed stubs, server in-process

- **Date:** r23
- **Status:** accepted
- **Context:** The capstone is a single-repo tutorial whose subject is
  services on Kubernetes, not multi-repo API release engineering. The
  common "shared protos" advice (a dedicated contract repo consumed via git
  submodule or a published stub package) solves a multi-team versioning
  problem we don't have, and would add an orthogonal dimension to teach.
  We needed a layout that keeps the focus on the services and stays
  reproducible (CAP-001) and image-lean (CAP-005).
- **Decision:**
  - **Protos live in-repo** at `examples/17-capstone/proto/`, mirroring the
    package as directories (`capstone/<service>/v1/...`) with a named
    package per file and one service per file (1-1-1).
  - **Stubs are generated once and committed per service** (option b):
    `scripts/gen-protos.sh` runs `buf generate` (CAP-R19-4) — or falls back
    to `python -m grpc_tools.protoc` if buf is absent — and copies the
    generated `capstone/...` tree into each consuming service's `gen/`
    directory. inventory-service and order-service get identical stubs
    (the `_pb2_grpc.py` holds both the Servicer and the Stub). Services add
    `gen/` to `sys.path` so `capstone.<svc>.v1` is importable in-container
    (`/opt/app-root/src/gen`) and locally. **No buf/protoc in the images.**
  - **The gRPC server runs in the same process as FastAPI** via `grpc.aio`,
    started and stopped by the app's lifespan — one container, two ports
    (HTTP for REST/health, gRPC for service calls). Avoids a second process
    or sidecar.
  - **First call: order → inventory `CheckStock`.** order-service validates
    stock over gRPC before persisting an order; it fails closed if inventory
    is unreachable. This is the smallest real synchronous cross-service
    call and the template for the rest.
- **Consequences:**
  - (+) Self-contained images; build context stays per-service; no extra
    build-time tooling
  - (+) Reproducible — committed stubs build identically every time
  - (+) The gen step is one command, fallback-friendly (buf *or* grpc_tools)
  - (−) Stubs are duplicated across services that share a contract (small,
    regenerated by one script — acceptable)
  - (−) Generated code carries a protobuf-runtime version expectation; deps
    pin `protobuf >=5.26,<6` / `grpcio ^1.66` and the prose notes the skew
    risk
  - (−) Codegen + `poetry lock` (grpc deps added) are manual "run once"
    steps before the first build — documented in the iteration

## CAP-014 — Python 3.12 for the dev venv, matching the container runtime

- **Date:** r23
- **Status:** accepted
- **Context:** The service images run UBI 9 `python-312` (Python 3.12 — the
  newest Python with a supported UBI 9 image; there is no UBI 9 3.14 image).
  Fedora 44, the target host, defaults to Python 3.14. A bare `poetry
  install` on the host therefore builds the dev venv with 3.14, which (a)
  drifts from the 3.12 the container actually runs and (b) can hit
  wheel-availability gaps on a very new Python — `grpcio`/`grpcio-tools` in
  particular may lack 3.14 wheels and fall back to a source build.
- **Decision:** Keep the container on UBI 9 `python-312`, and pin each
  service's **host dev venv to Python 3.12** for parity: `sudo dnf install
  python3.12` once, then `poetry env use python3.12` per service before
  `poetry lock && poetry install`. The `pyproject.toml` constraint stays
  `python = "^3.12"` (permissive — 3.12/3.13/3.14 all satisfy it) so the
  project isn't artificially locked to one minor version; the *operational*
  guidance is to use 3.12 to match the runtime.
- **Consequences:**
  - (+) Dev/runtime parity — local tests and codegen run the same Python the
    container does
  - (+) Avoids brand-new-Python wheel gaps (no surprise source builds)
  - (+) A clean teaching point: match your dev environment to your runtime
  - (−) Requires installing a non-default Python (`python3.12`) on a Fedora
    44 host and remembering `poetry env use` per service
  - (−) The permissive `^3.12` means a contributor *can* drift to 3.14 if
    they skip the `env use` step; the §17 prerequisites call this out

## CAP-015 — imagePullPolicy: Always for capstone services (mutable :v1 + local registry)

- **Date:** r23
- **Status:** accepted
- **Context:** Services are pushed to the in-cluster registry under a mutable
  `:v1` tag and rebuilt repeatedly during development. With
  `imagePullPolicy: IfNotPresent`, the node's containerd already has an image
  tagged `localhost:5000/<svc>:v1` cached from an earlier session, so the
  kubelet does **not** pull the freshly-pushed `:v1` — it serves the stale
  cached layer. This silently bit r23: order-service ran its r21c image (no
  gRPC stock check) and inventory-service ran its r22 image (no `/stock`, no
  gRPC server), so an out-of-stock order wrongly returned 201 and `/stock`
  404'd — even though the registry held the correct new images and
  uninstall/reinstall didn't help (the *node cache*, not the release, was
  stale).
- **Decision:** Set **`imagePullPolicy: Always`** on all capstone service
  charts and in the scaffold template. With a local registry, pulls are
  cheap, and Always guarantees the running pod matches what was just pushed.
- **Consequences:**
  - (+) Eliminates an entire class of "I rebuilt but my change didn't take"
    confusion — the pod always runs the current image
  - (+) Cheap with a local registry (no external bandwidth)
  - (−) A pull on every pod start; negligible here, would matter against a
    remote registry
  - **Production-grade alternative (noted, not adopted):** use **immutable
    tags** (a git SHA or build timestamp per build) instead of a mutable
    `:v1`, which makes `IfNotPresent` correct and gives provenance. Deferred
    as extra machinery the tutorial doesn't need yet; called out in §17 prose
    as the real-world pattern.
- **Guardrail added alongside:** the smoke tests now assert each chart's
  `image.repository` starts with `localhost:5000/` before deploying, so a
  bare image name (which pulls from Docker Hub and ErrImagePulls) fails
  immediately with a clear message instead of after a rollout timeout. This
  was prompted by a separate r23 regression where order-service's
  `values.yaml` had reverted to a bare `order-service`.

## CAP-016 — GraphQL via a gateway that orchestrates, not true subgraph federation

- **Date:** r24
- **Status:** accepted (for the tutorial; true federation noted as the
  production pattern)
- **Context:** CAP-R19-5 chose "a federated gateway with Strawberry." There
  are two ways to deliver a unified GraphQL graph across services:
  - **(A) True subgraph federation** — each service exposes its *own*
    GraphQL subgraph (with `@key` entity directives), and a gateway composes
    them into a supergraph, planning queries across subgraphs. This is the
    production-scale pattern (Apollo Federation / the GraphQL composite
    spec): each domain owns and evolves its slice of the graph independently.
  - **(B) Gateway orchestration** — one stateless gateway exposes the unified
    graph, and its resolvers fetch from the services over their existing
    interfaces (order via REST, inventory via gRPC). The services are
    unchanged.
- **Decision:** Use **(B)** for the capstone. A single `graphql-gateway`
  service resolves `order(id)` from order-service (REST) and the nested
  `Order.stock` field from inventory-service (gRPC). No GraphQL is added to
  the existing services.
- **Rationale:**
  - This is an example, not a production deployment — (B) demonstrates the
    *value* GraphQL adds (one client query, multiple backends, response
    shaped by the client) with one new service and zero changes to the five
    existing ones, fitting the incremental rhythm and minimal-dependency rule.
  - It makes the protocol comparison (CAP-012) concrete in one place: the
    gateway's resolvers literally call REST and gRPC side by side, and
    GraphQL stitches the result — the reader sees all three protocols
    cooperating.
  - The gateway's readiness probe deliberately does **not** check downstreams
    (readiness = "can I serve", not "are my dependencies up"), so a
    downstream outage surfaces per-field at query time rather than as
    cascading unavailability.
- **Consequences:**
  - (+) Small, self-contained, demonstrably valuable; one vertical slice
    (`order → stock`) proven, widened later
  - (+) Reuses the already-verified REST and gRPC surfaces
  - (−) Not how you'd federate at scale: a single gateway is a development
    and scaling bottleneck, and the schema isn't owned by the domains
  - **When you'd use (A) in production (documented in §17 prose):** when
    each domain team must own and evolve its part of the graph
    independently; when you want the supergraph composed and validated in
    CI (breaking-change detection across subgraphs); when query planning,
    entity resolution across subgraphs, and per-subgraph scaling matter.
    (A) trades the gateway bottleneck and central schema for real domain
    autonomy — the same data-mesh principle the capstone teaches, applied
    to the graph itself.

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
