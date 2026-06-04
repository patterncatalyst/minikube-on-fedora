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

## CAP-017 — Async spine: Strimzi single-node KRaft, aiokafka, JSON-now/registry-later

- **Date:** r25
- **Status:** accepted (first async slice; Apicurio + Alembic deferred to
  follow-ons)
- **Context:** The mesh's synchronous story (REST, gRPC, GraphQL) is
  complete; the async story — services reacting to events — was missing.
  r25 establishes it with the smallest real flow: order-service emits an
  `order.placed` event, notification-service consumes it. The roadmap had
  bundled Kafka + Apicurio + Alembic into one r25; that's three heavy things,
  so we decomposed (the incremental discipline that's caught every issue
  cleanly).
- **Decisions:**
  - **Strimzi operator, single-node KRaft cluster.** Strimzi 0.51 (KRaft —
    no ZooKeeper), installed via Helm (`oci://quay.io/strimzi-helm/...`,
    pinned) as a separate setup script (the operator pattern, CAP-002). One
    dual-role `KafkaNodePool` (controller + broker), **ephemeral storage**,
    **replication factor 1**, `min.insync.replicas 1` — dev-scale. The
    `KafkaTopic` is managed declaratively by the Entity/Topic Operator.
    `kafka.version` is omitted so the operator uses its own supported default
    (avoids the version-skew error class).
  - **aiokafka** as the client. It's asyncio-native, so the producer and
    consumer run in the services' existing event loop (Managed Lifecycle:
    started/stopped by the FastAPI lifespan) — unlike the blocking
    kafka-python.
  - **JSON event payloads for now.** With Apicurio deferred there's no
    registry to validate against yet, and JSON keeps the slice
    dependency-light. The binary-format choice (Avro vs Protobuf) is made
    when Apicurio lands (r25b).
  - **First event: `order.placed`** (order-service → notification-service),
    keyed by order id for per-key ordering. This gives notification-service
    its designed purpose (a consumer-only data product) and models the
    canonical "something happened, downstreams react" pattern.
  - **notification records events in memory** (`GET /received`) — a
    deliberate stand-in so the flow is observable without a table yet.
- **Consequences & documented simplifications (production notes in §17):**
  - (+) Smallest verifiable async slice; Apicurio and Alembic land as
    independent, separately-verifiable follow-ons (r25b, r25c)
  - (−) **Dual-write gap:** order-service commits to Postgres then publishes
    to Kafka — a crash between them can drop the event. Production fix: the
    **transactional outbox** pattern (Kleppmann, DDIA). Noted in `events.py`
    and §17; deferred.
  - (−) **At-least-once delivery:** Kafka may redeliver; the consumer is made
    **idempotent** (keyed by order_id). Documented in `consumer.py`.
  - (−) **Ephemeral storage + RF 1 + single node** are dev-only; production
    uses persistent volumes, separate broker/controller pools, RF 3, and
    `min.insync.replicas 2`. Stated in §17.
  - (−) In-memory `/received` is not durable — replaced by notification's
    real `notifications` table + Alembic in r25c.
- **Follow-ons:** **r25b** — Apicurio schema registry + a registered binary
  schema (Avro vs Protobuf decided then). **r25c** — notification's
  `notifications` table with Alembic migrations, retiring `create_all` for
  that service (CAP-004).

## CAP-018 — Contract/metadata architecture: multi-format Apicurio, OpenMetadata on top

- **Date:** r25 (documentation iteration, ahead of r25b implementation)
- **Status:** accepted (architecture + sequencing); implemented across
  r25b → r27
- **Context:** The mesh now speaks four protocols, each of which is a
  contract. A data mesh needs those contracts stored, versioned,
  compatibility-checked, and discoverable — and needs lineage over them. We
  documented the target architecture now (prose + two diagrams in §17) so the
  iterations can correct it against reality rather than back-filling
  explanation at the end.
- **Decisions:**
  - **Apicurio as a multi-format registry holding all four contracts.** Not
    just Avro/Kafka — Apicurio stores each protocol's contract as its native
    artifact type: **Avro** (Kafka events), **Protobuf** (gRPC defs),
    **OpenAPI** (REST, from FastAPI `/openapi.json`), **GraphQL SDL**
    (gateway). One registry, every contract.
  - **Runtime vs discovery contracts.** Avro events are a *runtime*
    contract — producer/consumer serialize against the registry, the event
    won't encode/decode without it (gRPC Protobuf is similar in spirit,
    compiled ahead of time). OpenAPI and SDL are *discovery* contracts —
    published as source-of-truth, but nothing fails at runtime if absent;
    they exist for humans, CI breaking-change checks, and catalog ingestion.
  - **Avro for events, Protobuf stays for gRPC.** Each is conventional in its
    domain (Avro is the polished Kafka-registry path; Protobuf is gRPC's
    native IDL and reuses the `buf` tooling from CAP-013). Both live in the
    registry; the event format being distinct from the gRPC format is fine.
  - **OpenMetadata layered on top, ingesting from Apicurio + Postgres +
    Kafka.** Apicurio is the *contract* metadata; OpenMetadata is the
    *lineage/discovery* metadata derived from it (plus CNPG Postgres schemas
    and Strimzi topics), assembling the who-produces/who-consumes graph.
  - **Sequencing rationale:** Apicurio before OpenMetadata, because a catalog
    with nothing to catalog is empty — the registry must hold contracts
    before the catalog can ingest them. And within the registry work, the
    runtime path (Avro event) before the discovery path (publishing
    OpenAPI/Protobuf/SDL), because the runtime path is load-bearing and
    independently verifiable.
- **Implementation plan (multi-iteration, one concern at a time):**
  - **r25b** — deploy Apicurio; move `order.placed` from ad-hoc JSON to a
    registered **Avro** schema; producer/consumer validate against it (the
    runtime contract).
  - **discovery-contracts follow-on** — publish OpenAPI (each FastAPI
    service), Protobuf (the `.proto` defs), and GraphQL SDL into Apicurio as
    the artifacts OpenMetadata will ingest.
  - **r27** — deploy OpenMetadata; ingest Apicurio + Postgres + Kafka; build
    lineage.
- **Consequences:**
  - (+) Single source of contract truth across all protocols; clean
    separation of contract metadata (Apicurio) from lineage metadata
    (OpenMetadata)
  - (+) Documented destination lets iterations correct the explanation
    against what's actually built
  - (−) Several distinct registration mechanisms (Avro serde, proto upload,
    OpenAPI/SDL publish) — hence split across iterations rather than one big
    step

## CAP-019 — order.placed as registered Avro: Apicurio + a transparent ccompat serde

- **Date:** r25b
- **Status:** accepted (first runtime contract; discovery contracts + the rest
  of CAP-018 still follow)
- **Context:** CAP-018 set the destination. r25b implements the first piece —
  the runtime contract — by moving `order.placed` from ad-hoc JSON (r25) to a
  registered Avro schema that producer and consumer validate against.
- **Decisions:**
  - **Apicurio Registry 3, in-memory, as a first-party subchart.** Deployed
    via `charts/capstone/charts/apicurio` (Deployment + Service running the
    official `quay.io/apicurio/apicurio-registry:3.2.4` image with
    `APICURIO_STORAGE_KIND=mem`), rather than a community Helm chart whose
    values schema we can't fully verify — consistent with how Postgres and
    Kafka are wrapped. In-memory loses schemas on restart, which is harmless:
    the producer re-registers on startup. Production uses SQL (CloudNativePG)
    or kafkasql; the storage kind is a single values key.
  - **Confluent-compatible API (`/apis/ccompat/v7`).** Apicurio implements the
    Confluent Schema Registry API, the standard way to reach it from any
    language. Register: `POST /subjects/{subject}/versions`; fetch by id:
    `GET /schemas/ids/{id}`. Subject follows TopicNameStrategy:
    `order-placed-value`.
  - **Transparent serde (Option A), not a library.** A small shared
    `avro_serde.py` (`fastavro` + `httpx`) implements the Confluent Wire
    Format ourselves — magic byte `0x00`, 4-byte big-endian schema id, then
    the Avro payload. Chosen over a serde library (e.g. Kafkit) for minimal
    dependencies and legibility: the reader sees the schema registered, the id
    stamped into the bytes, and the consumer fetch the schema by id to decode.
    confluent-kafka's own serde doesn't fit anyway (librdkafka-based, sync;
    we're on aiokafka).
  - **order-service owns the contract.** The canonical `order-placed.avsc`
    lives inside order-service (`services/order-service/schemas/`), since the
    producer owns the event it emits. The consumer holds **no** local copy —
    it fetches the writer schema from the registry by the id in each message,
    which is the essence of a runtime contract.
  - **`amount` as a string** in the Avro schema (matches the JSON it
    replaces); Avro `decimal` logical type is the noted refinement.
- **Consequences:**
  - (+) The event now has a real, versioned, compatibility-checkable
    contract; the registry is genuinely in the runtime path (the consumer
    can't decode without it)
  - (+) The wire format is visible and teachable; only `fastavro` + `httpx`
    added
  - (−) In-memory registry isn't durable (acceptable; producer re-registers)
  - (−) Manual wire framing is our code to maintain — but it's ~25 lines and
    matches the documented Confluent format exactly
- **Follow-ons (unchanged from CAP-018):** publish the discovery contracts
  (OpenAPI/Protobuf/SDL) into Apicurio; then OpenMetadata (r27) ingests
  everything into lineage.

## CAP-020 — Discovery contracts: publish OpenAPI, Protobuf, and GraphQL SDL to Apicurio

- **Date:** r25b (discovery-contracts follow-on)
- **Status:** accepted (completes the registry half of CAP-018; OpenMetadata
  still follows)
- **Context:** CAP-019 put the Avro *runtime* contract in Apicurio. This adds
  the *discovery* contracts for the other three protocols, so the registry
  holds all four — the feedstock OpenMetadata ingests (CAP-018).
- **Decisions:**
  - **Native v3 API, not ccompat.** Discovery artifacts are created via
    `POST /apis/registry/v3/groups/{group}/artifacts` with the structured v3
    body (`artifactId`, `artifactType`, `firstVersion.content`). The ccompat
    API is reserved for the Avro runtime path (where producer/consumer expect
    Confluent-style ids); discovery artifacts have no such constraint and use
    Apicurio's first-class multi-format API. They share the `default` group.
  - **Three artifacts, three sources.** `order-service-openapi` (OPENAPI,
    fetched from the live `/openapi.json` — the REST exemplar), the publish
    step generalizes to every service's OpenAPI; `inventory-grpc-proto`
    (PROTOBUF, read from the committed `.proto` — no service needed);
    `graphql-gateway-sdl` (GRAPHQL, fetched from a new gateway `/sdl`
    endpoint that returns `schema.as_str()`).
  - **A gateway `/sdl` endpoint.** Strawberry can emit the SDL directly; the
    gateway exposes it so the schema is fetchable for publishing (and useful
    on its own as a discoverable contract). It's explicitly off the runtime
    path.
  - **Publishing is offline, not per-service-startup.** A reusable
    `scripts/publish-discovery-contracts.sh` (stdlib Python, given reachable
    URLs) does the work; the smoke script supplies port-forwarded URLs. This
    keeps discovery publishing as a CI/ops step, not runtime coupling baked
    into every service (contrast the Avro runtime contract, which order-service
    must register to function).
  - **Idempotent.** An existing artifact (HTTP 409) is treated as already
    published; production CI would add a new version (`ifExists=UPDATE`).
- **Consequences:**
  - (+) Apicurio now holds all four protocols' contracts; the runtime-vs-
    discovery distinction in the diagrams is concrete (ccompat vs v3 API,
    runtime-registered vs offline-published)
  - (+) No new runtime coupling; only the gateway gained a read-only endpoint
  - (−) OpenAPI publish needs the service running (fetched live); the proto is
    static, the SDL needs the gateway up. The smoke deploys what it needs.
  - (−) Only order-service's OpenAPI is published as the exemplar; extending
    to all services is a trivial loop, deferred to keep the slice focused.
- **Remaining for CAP-018:** OpenMetadata (r27) ingests Apicurio + Postgres +
  Kafka into lineage — the last layer.

## CAP-021 — Alembic migrations via an init container; retire create_all for notification

- **Date:** r25c
- **Status:** accepted (applies to notification-service; other services keep
  `create_all` for now)
- **Context:** CAP-004 chose `Base.metadata.create_all` at startup for the
  walking skeleton, with Alembic deferred until schema *evolution* mattered.
  notification-service is the first service to gain a real domain table
  (`notifications`, persisting consumed events), so it's the right place to
  introduce Alembic and retire create_all.
- **Decisions:**
  - **Alembic, async template.** notification uses the SQLAlchemy 2.0 async
    engine (asyncpg), so env.py is the `-t async` style with the
    `connection.run_sync(do_run_migrations)` bridge (the default sync env.py
    does not work with asyncpg). Migrations themselves are plain sync
    `op.*` functions — Alembic runs them inside `run_sync` (per Alembic
    discussion #1208); they are not awaited.
  - **Run as a Kubernetes init container, not at app startup.** The Deployment
    gets a `migrate` init container (same image, same DB env) that runs
    `alembic upgrade head` before the app container starts. This is the
    idiomatic k8s pattern and is precisely what *retires* create_all: when the
    app process starts, the schema and table already exist, so the app issues
    no DDL. `db.py`'s `init_schema()` is removed and the lifespan no longer
    creates anything.
    - *Alternative considered:* a Helm pre-install/pre-upgrade hook Job. Also
      valid; the init container was chosen because it's co-located with the
      Deployment, re-runs idempotently on every rollout, and needs no separate
      Job lifecycle. A hook Job becomes attractive once multiple services share
      migrations or migrations must run exactly once cluster-wide.
  - **Per-service `alembic_version` in the service's own schema.** One Postgres
    database, schema per service (CAP-003). The version table goes in the
    `notifications` schema via `version_table_schema`, so each service keeps an
    isolated migration history (a shared `public.alembic_version` would
    collide). env.py `CREATE SCHEMA IF NOT EXISTS` + commits before stamping,
    since the version table lives in that schema.
  - **DB URL built in env.py, not via `config.set_main_option`.** Setting the
    URL through configparser triggers `%` interpolation, which would corrupt a
    CloudNativePG password containing `%`. env.py builds the async engine
    directly from `settings.database_url`; `alembic.ini`'s `sqlalchemy.url` is
    an unused placeholder.
  - **Idempotent persistence.** The consumer writes each event via
    `INSERT ... ON CONFLICT (order_id) DO NOTHING` (unique constraint on
    `order_id`), so Kafka's at-least-once redelivery is a no-op, not a
    duplicate. `/received` now reads from the table; durability across pod
    restarts is the observable benefit over the in-memory list.
- **Consequences:**
  - (+) Real schema-evolution path for notification; create_all retired there;
    establishes the Alembic pattern other services can adopt
  - (+) Migrations run before the app, declaratively, on every rollout
  - (−) Other services still use create_all (deferred; not yet evolving)
  - (−) The async env.py + run_sync bridge is non-obvious boilerplate (the
    documented async pitfalls: sync-only default env, empty autogenerate if
    models aren't imported, `%` interpolation) — captured in env.py comments

## CAP-022 — OpenMetadata deploy: lean trio, Airflow-free, single-node search, reuse Postgres

- **Date:** r27
- **Status:** accepted (deploy decisions); DB-reuse wiring carries unverified
  risk until the live run (see consequences)
- **Context:** OpenMetadata is the catalog layer (CAP-018). It's the heaviest
  component in the capstone — production specs sum to ~40 GiB across DB +
  search + Airflow, far over the 24 GB / 16 CPU `capstone` profile. The deploy
  must be trimmed to a demo footprint without losing the canonical shape.
- **Decisions:**
  - **Use the official charts** (`open-metadata/openmetadata` 1.12.8 and
    `openmetadata-dependencies`), not hand-rolled manifests — canonical, and
    the chart owns the server Deployment, the DB migration job, search index
    bootstrap, and secret templating that we should not reimplement.
  - **No Airflow.** Since 1.12 ingestion can run without Airflow. We set
    `deployPipelinesConfig.enabled: false` and run ingestion as **one-off
    Kubernetes Jobs** (the `openmetadata/ingestion` image running
    `metadata ingest -c <yaml>`), not the K8sPipelineClient — simplest, most
    legible, no RBAC/ServiceAccount machinery. Drops the entire Airflow tier
    (api-server, scheduler, dag-processor, triggerer, statsd), the single
    biggest footprint saving.
  - **Single-node OpenSearch, no host kernel change.** Run OpenSearch in
    single-node / development mode (`discovery.type=single-node`), which puts
    it in development mode where the `vm.max_map_count` bootstrap check is a
    non-fatal warning, not a startup blocker. This means **we never touch the
    host's `vm.max_map_count`** — no `minikube ssh sysctl`, no `/etc/sysctl`,
    no privileged sysctl init container. (Ephemeral `sysctl -w` would revert on
    reboot anyway, but single-node mode avoids it entirely.) Heap trimmed to
    ~1 GiB; storage trimmed from the 30 GiB default.
  - **Reuse the CloudNativePG Postgres** as OpenMetadata's backend (a dedicated
    `openmetadata` database in the existing cluster), not the chart's bundled
    MySQL — keeps the all-Postgres, operator-managed story (CAP-003) and saves
    a stateful service. OpenMetadata's own operational store is *not* a data
    product; reusing the cluster for it is a deployment convenience, distinct
    from the per-service data-product schemas.
  - **Footprint:** server ~2 GiB + OpenSearch ~2 GiB + (backend ~0, reused) +
    transient ingestion Job ≈ 4–5 GiB on top of the existing stack → ~12–16 GiB
    of 24. No profile bump.
- **Consequences:**
  - (+) Canonical install, demo-sized, fits the profile, host kernel untouched
  - (+) Ingestion is a legible one-off Job, no orchestrator to run
  - (−) **DB-reuse is the verification risk.** Pointing the official chart at
    our Postgres means overriding its `database` config + `dbScheme: postgresql`
    + a credentials secret, and provisioning an `openmetadata` database/role in
    CNPG. None of this is renderable offline; if the chart's DB keys or the
    secret wiring are off, the server's migration job fails. Fallback if it
    fights us: the chart's bundled MySQL (default, most-tested) — at the cost
    of introducing MySQL. Decided to attempt PG-reuse first per the
    all-Postgres preference, with bundled MySQL as the documented escape hatch.
  - (−) Highest cluster-only uncertainty in the project so far — expect one or
    two live fix cycles on the values files.

### Outcome (verified on Fedora 44, r27)

Deployed green. The server's `run-db-migrations` init container connected to
CloudNativePG over **`sslmode=require`** (no fallback to `prefer` needed —
`require` works against CNPG's self-signed server cert), ran its migrations,
and populated **168 tables** in the `openmetadata` database. The version API
(`/api/v1/system/version`) serves 1.12.8, proving the server booted and reached
Postgres. OpenSearch came up single-node with no host-kernel change. The lean
footprint fit the 24 GB / 16 CPU profile with no bump. All CAP-022 decisions
held.

### Lessons — chart secret wiring (the three live fix cycles)

Every blocker on the way to green was a Helm *secret-wiring* issue, not a
sizing, SSL, or Postgres-reuse problem. None were catchable by `helm template`
inspection or YAML parsing alone — they only surfaced at install/admission
time. Recorded so the next person deploying OpenMetadata (or any large
third-party chart) doesn't rediscover them:

1. **Don't name a user-supplied secret the same as one the chart generates.**
   The chart *generates* a Helm-owned secret `openmetadata-db-secret` (holding
   the assembled `DB_HOST`/`DB_PORT`/`DB_USER`/... connection fields) and reads
   the DB password from a *separate* secret named by
   `database.auth.password.secretRef`. Initially we created our password secret
   as `openmetadata-db-secret` too — Helm refused to install because it won't
   adopt a resource it didn't create (`invalid ownership metadata; missing
   app.kubernetes.io/managed-by`). Fix: name the password secret something
   distinct (`openmetadata-db-app-secret`). Lesson: before creating any secret
   a chart references, `helm template | grep "kind: Secret"` to see which names
   the chart *itself* owns, and stay clear of them.

2. **"Feature disabled" ≠ "secret unreferenced."** Even with the pipeline
   service client disabled (`pipelineServiceClientConfig.enabled: false`), the
   chart still templates an `AIRFLOW_PASSWORD` env var on *every* container —
   including the `run-db-migrations` init container — sourced via `secretKeyRef`
   from a secret named `airflow-secrets`. Because we disabled the Airflow
   dependency, that secret was never created, so the init container failed with
   `CreateContainerConfigError: secret "airflow-secrets" not found` and never
   started. Kubernetes validates *all* `secretKeyRef`s at container-create time
   regardless of whether the value is ever used. Fix: create a placeholder
   `airflow-secrets` (dummy value; nothing reads it). Lesson: disabling a
   feature in values doesn't always remove its secret references from the
   rendered manifests — grep the rendered output for `secretKeyRef`/`secretRef`
   and ensure every referenced secret exists.

3. **The error you see can be downstream of the real cause.** The first failures
   presented as a DB-secret ownership error, which looked like a database-config
   problem; the real issue was a naming collision. Later the init container's
   `CreateContainerConfigError` looked like it might be the long-feared
   `sslmode` connection failure; it was actually the missing `airflow-secrets`,
   and the container hadn't even started — so no DB connection had been
   attempted yet. Lesson: read pod *events* (`kubectl describe`) and container
   *state*, not just logs, before theorising — `CreateContainerConfigError`
   means the kubelet couldn't even build the container config, which is always a
   missing/!malformed env/volume/secret reference, never an application error.

These reinforce the project-wide pattern: a class of failures (image
tool-presence, dropped config properties, and now chart secret wiring) is
invisible to Claude's static checks and only appears in-cluster. A
"render the chart, list every secret it owns and references, confirm each
exists with the right shape" pre-flight would have caught all three before the
first install.

## CAP-023 — Catalog ingestion + cross-product lineage: one-off Jobs, app-role read, bare Kafka, explicit lineage via the REST API

- **Date:** r27b
- **Status:** accepted (packaging + wiring decisions); **verified on Fedora 44,
  r27b** — every API/connector verify-point held first try (see Outcome)
- **Context:** r27 (CAP-022) deployed OpenMetadata but left the catalog empty of
  mesh content. CAP-018 set the destination — the catalog ingests from Postgres
  + Kafka (+ Apicurio) and represents cross-product lineage. CAP-022 already
  pre-decided the *mechanism*: ingestion runs as one-off Kubernetes Jobs
  (`openmetadata/ingestion` running `metadata ingest -c <yaml>`), not Airflow,
  not the k8s pipeline client. r27b decides how those Jobs are *packaged and
  wired*, and how lineage is declared. Apicurio ingestion is explicitly out of
  scope (deferred to r27c) — r27b ingests Postgres + Kafka and declares the
  spine.
- **Decisions:**
  - **(A) Job packaging: kubectl-applied Jobs, not Helm.** The ingestion
    workflow configs (`postgres.yaml`, `kafka.yaml`) plus two helper scripts
    (`get_token.py`, `lineage.py`) ship under `openmetadata/ingestion/`,
    delivered as a single ConfigMap (`om-ingestion-config`) that all three Jobs
    mount read-only at `/opt/ingestion`. `scripts/ingest-openmetadata.sh`
    creates the ConfigMap and runs the Jobs in sequence, deleting any prior Job
    of each name before applying. *Rejected:* a Helm subchart of Jobs — a Job's
    pod template is immutable, and these are meant to be re-run, so `helm
    upgrade` would fight us. Same reasoning as CAP-021's init-container-vs-hook
    call: long-lived resources go through Helm, one-off re-runnable Jobs are
    cleaner as kubectl-applied manifests driven by a script (mirroring how
    `setup-openmetadata.sh` does its kubectl provisioning).
  - **(B) Postgres read credential: reuse the `capstone_app` role.** The CNPG
    app role owns every service schema (it created them — CAP-003), so one
    credential reads them all; the password comes from the existing
    `capstone-postgres-app` secret via `secretKeyRef`. No new role, no
    superuser. Ingestion is scoped to the `capstone` database, so the
    `openmetadata` operational database is never touched — the catalog does not
    catalog itself.
  - **(C) Kafka ingestion is bare — no schema registry.** The Kafka connector
    gets bootstrap servers only (`capstone-kafka-kafka-bootstrap:9092`); topics
    are cataloged as entities, but their Avro schemas are not linked. Wiring
    `schemaRegistryURL` at Apicurio's ccompat endpoint *would* enrich
    `order-placed` with its registered `order-placed-value` schema — but that is
    exactly the long-pending "Apicurio connector vs REST" question, which
    belongs with proper Apicurio ingestion (r27c), not bolted onto r27b. Keeping
    Kafka bare keeps Apicurio out of this iteration's scope.
  - **(D) Lineage is declared explicitly via the REST API, not inferred.**
    OpenMetadata derives lineage automatically only from query logs / dbt, which
    the capstone has none of, and the spine crosses entity types
    (Table → Topic → Table), which the first-class lineage API handles cleanly.
    `lineage.py` resolves the three FQNs to ids and `PUT`s two directed edges
    (`PUT /api/v1/lineage`). It runs as the *third* Job, after the Postgres and
    Kafka Jobs, because the entities must exist to be linked. *Rejected:* a
    custom-lineage ingestion YAML — keeps the `metadata ingest` idiom but its
    Topic↔Table support is shakier than the API. Both stay stdlib-only Python in
    the ingestion image, so no dependency is added.
  - **Auth refinement (supersedes the "ingestion-bot JWT" phrasing in the r27b
    plan):** the Jobs authenticate by **admin login**
    (`POST /api/v1/users/login` → `accessToken`), not by retrieving the
    ingestion-bot's stored JWT. Reading the bot's auth mechanism needs admin
    credentials anyway, so logging in as admin and using that token directly is
    strictly simpler and self-contained — no extra secret, no host-side token
    plumbing. Each Job fetches its own token in-cluster via `get_token.py`. The
    ingestion-bot path remains the production alternative for unattended
    pipelines.
  - **The spine (the demonstrable payoff of the whole CAP-018 arc):**
    `capstone-postgres.capstone.orders.orders` (Table, order-service) →
    `capstone-kafka.order-placed` (Topic) →
    `capstone-postgres.capstone.notifications.notifications` (Table,
    notification-service). The first time the mesh's cross-product data flow is
    queryable metadata rather than tribal knowledge.
- **Consequences:**
  - (+) The catalog now holds the mesh's tables and topics, with the
    cross-product lineage explicit and browsable — CAP-018's destination
    reached for Postgres + Kafka.
  - (+) Ingestion is re-runnable and legible (three Jobs, plain manifests,
    stdlib helpers); no orchestrator, no new dependency, no committed secret.
  - (−) **The OpenMetadata 1.12.8 API/connector specifics are the verification
    risk** — the Postgres `authType.password`/`sslMode` keys, the Kafka
    `bootstrapServers`/`MessagingMetadata` keys, the basic-auth login shape, the
    lineage PUT payload, and the lineage-by-name response shape are not
    renderable offline. This is r27b's analog of r27's secret-wiring cycles;
    expect at least one live fix cycle. Every such spot is flagged `VERIFY-POINT`
    in the file that contains it.
  - (−) Kafka topics carry no schema link yet (decision C); Apicurio ingestion
    and the registry linkage are r27c.

### Outcome (verified on Fedora 44, r27b)

Green first try. `ingest-openmetadata.sh` ran all three Jobs to completion and
`smoke-om-lineage.sh` passed every assertion — both services, the three spine
entities, and the topic's one-upstream/one-downstream lineage. The flagged
verification risk did **not** materialize: the OM 1.12.8 Postgres connector
(`authType.password`, `sslMode: require` against CNPG), the bare Kafka connector
(`bootstrapServers` + `MessagingMetadata`), the admin basic-auth login, the
lineage `PUT /api/v1/lineage` payload, and the `GET /api/v1/lineage/topic/name/{fqn}`
response shape all matched as written. Unlike r27 (three secret-wiring fix
cycles), r27b needed no live fixes. Worth noting against the project-wide "static
checks miss cluster-only failures" pattern: this time the cluster agreed with the
offline-authored configs on the first run — the verify-point flags were
appropriate caution, not a deferred bug.

## CAP-024 — Istio canary: order-service v1→v2 contract evolution via weighted subset routing

- **Date:** r26 (built after r27/r27b — see sequencing note)
- **Status:** accepted (design + implementation); **verified on Fedora 44 (r26.2)**
- **Context:** The r26 design intent framed Istio as "safe contract evolution +
  observable inter-product traffic," with the headline being a data product
  taking its REST API through a v1→v2 change and Istio splitting live traffic
  between versions — a canary of a *contract*, not just a binary. r26 builds
  exactly that on order-service (the REST/OpenAPI exemplar, whose contract
  Apicurio already holds and whose lineage OpenMetadata now shows — r27b).
- **Decisions:**
  - **Target = order-service** (the only pure-REST service with a published
    contract). The v2 change is additive and backward-compatible: GET /version
    reports the subset, and v2 advertises a new `currency` field on order
    responses — the canonical "evolve the contract without breaking clients"
    move you'd actually canary.
  - **One image, env-toggled subsets** (`API_VERSION=v1|v2`), not two image
    builds. v1 and v2 run the same image with different env and a different
    `version` pod label; Istio shifts traffic between them. This keeps the
    demo's focus on the traffic-management mechanism rather than an image
    pipeline. Documented as a demo simplification — in production v1/v2 are
    distinct tags from distinct commits, and the Istio mechanism is identical.
  - **Routing through the istio-ingressgateway**, not client-side. A `Gateway` +
    a `VirtualService` (weighted route over v1/v2 subsets) + a `DestinationRule`
    (subsets by the `version` label) — the §11 Bookinfo pattern, now first-party
    on a capstone service. The smoke hits the gateway (port-forwarded under
    rootless podman, the §11 Option A), so no client needs meshing.
  - **Weights as `__W_V1__`/`__W_V2__` placeholders** in `istio/routing.yaml`;
    `smoke-canary.sh` substitutes them, so the same file drives 90/10, 50/50,
    0/100 — the progressive-canary operation is just re-applying the
    VirtualService.
  - **Selector immutability handled explicitly.** The v1 Deployment's selector
    is narrowed to include `version: v1` so it owns only its subset, disjoint
    from the v2 overlay's `version: v2`. Because a Deployment selector is
    immutable, enabling the canary on an already-deployed v1 requires deleting
    the old Deployment once before `helm upgrade` recreates it. The smoke
    detects a stale selector and prints the one-line migration; the §17 prose
    documents it.
  - **Scoped meshing, mTLS deferred.** r26 meshes order-service for the canary
    (sidecar via the inject annotation; the namespace is injection-labeled so
    new/recreated pods join, while the already-running operator-managed infra
    pods — Postgres, Kafka, Apicurio, OpenMetadata — keep running sidecar-less
    and must not be restarted under the label). Mesh-wide mTLS and observable
    inter-product traffic (PeerAuthentication STRICT, Kiali) are deliberately
    *not* in r26: STRICT would break unmeshed callers, and injecting the
    operator pods is hazardous. They belong with the observability iteration.
- **Consequences:**
  - (+) The "data products evolve their contracts without a flag-day break"
    principle is concrete and demonstrable: deploy v2, shift 10% → 50% → 100%,
    watch the response shape change. Leans on the now-verified Apicurio (holds
    v1/v2 OpenAPI) and OpenMetadata (lineage) layers.
  - (+) First-party Istio manifests on a capstone service; the §11 pattern
    generalized off Bookinfo.
  - (−) The selector-immutability one-time delete is a rough edge (mitigated:
    detected + instructed).
  - (−) Istio API/install specifics (the `networking.istio.io/v1` kinds, the
    ingressgateway Service, subset-by-label routing, sidecar injection timing)
    are not renderable offline — the cluster-only risk class. Flagged
    `VERIFY-POINT` in `istio/routing.yaml`.
  - (−) The env-toggle means "v2" is the same binary; honest about it, but a
    purist canary would use two image tags.

### Outcome (verified on Fedora 44, r26.2)

The mechanism worked on the first cluster apply; the two failures along the way
were both in the scaffolding around it, not the canary:

- **Install convention (r26.1).** The deliverable first told the operator to
  `helm upgrade --install capstone ./charts/capstone`, but this project installs
  each component as its own release (`scaffold-service.sh`:
  `helm upgrade --install <svc> charts/capstone/charts/<svc>`), and the umbrella
  declares no `dependencies:` — so that command would deploy nothing. Corrected
  to the per-service release. A worthwhile reminder that the deploy convention is
  a fact about the repo to look up, not assume.
- **Native sidecars (r26.2).** The smoke asserted istio-proxy by scanning
  `.spec.containers`, but Istio 1.29 on k8s ≥1.29 injects the proxy as a *native*
  sidecar — an initContainer with `restartPolicy: Always`. Both pods were already
  `2/2` (meshed); the assertion was a false negative. Fixed to check
  initContainers too. This is the modern Istio default and worth remembering for
  any future "is it meshed?" check in this project.

Once past those, the canary measured cleanly: a 90/10 VirtualService produced
v1=91/v2=9 of 100 requests through the ingress gateway, and shifting to 50/50
produced v1=45/v2=55. Every Istio API VERIFY-POINT (the `networking.istio.io/v1`
kinds, the `istio: ingressgateway` selector, subset-by-`version`-label routing)
held as authored offline — the flags were appropriate caution, not deferred bugs.
Reconciliation row r26 → ✅; verified count → 128.

## CAP-025 — KEDA as elastic data products: dual scalers (Kafka lag + HTTP add-on), placed to avoid the canary

- **Date:** r26 (decision locked); **implemented in r26b**
- **Status:** implemented (r26b); cluster-verification pending (Fedora 44)
- **Context:** The r26 design intent framed KEDA as "elastic data products" —
  autoscaling a product on the demand placed on it, back to zero when idle. The
  §17 platform-stack table promises *both* KEDA scaler types ("scale
  order-service on HTTP load; scale Kafka consumers on lag"), but the intent
  elaborated only the Kafka-lag path. This decision records both, and resolves
  *which service gets which* so the scalers don't collide with the CAP-024
  canary.
- **Decisions:**
  - **Kafka consumer-lag scaler → notification-service.** A `ScaledObject`
    (kafka scaler, §12 Pattern A) scales the `order-placed` consumer on
    consumer-group lag, to zero when idle. notification is a consumer — no
    HTTP/Istio path to conflict with.
  - **HTTP add-on scaler → graphql-gateway** (NOT order-service). The KEDA HTTP
    interceptor and Istio's VirtualService both want to own a service's ingress
    path; putting HTTP scaling on order-service would collide with the canary
    there. The gateway is a natural synchronous-read load target and is not the
    canary subject, so the two capabilities live on different services cleanly.
    This means updating the §17 stack-table line from "order-service on HTTP
    load" to "graphql-gateway on HTTP load" when r26b lands.
  - **Both scale-to-zero**, the §12 building blocks reused as first-party
    capstone manifests.
- **Consequences:**
  - (+) Both KEDA scaler types demonstrated, each idiomatic to its service; no
    proxy-path collision with the canary.
  - (−) KEDA HTTP interceptor + (if the gateway is later meshed) an Istio
    sidecar on the same workload is a known interaction to validate — the r26b
    cluster-only risk, by analogy to the verify-points elsewhere.
  - (−) Implementation deferred to r26b to keep r26 to one concern (the canary).

### Implementation (r26b)

Shipped as first-party capstone manifests under `examples/17-capstone/keda/`:
`notification-scaledobject.yaml` (keda.sh/v1alpha1 ScaledObject, kafka trigger on
the `notification-service` consumer group / `order-placed` topic, lagThreshold 5,
min 0 / max 3) and `gateway-httpscaledobject.yaml` (http.keda.sh/v1alpha1, target
graphql-gateway service:80, concurrency target 5, min 0 / max 3). Install via
`scripts/setup-keda.sh` (KEDA 2.19.0 + HTTP add-on 0.12.2 into the `keda` ns, the
§12 versions). Both KEDA-scaled Deployments gained `sidecar.istio.io/inject:
"false"` so the injection-labeled namespace doesn't mesh them — keeping the
mesh scoped to order-service (CAP-024) and the autoscaling paths clear of Envoy.
The §17 stack-table line was corrected to "Scale graphql-gateway on HTTP load."
Two smokes prove the full 0→up→0 lifecycle: `demos/smoke-keda-kafka.sh` (produces
a 500-message raw burst to create lag — the consumer auto-commits and skips
undecodable messages, so no Avro path is needed) and `demos/smoke-keda-http.sh`
(drives /health load through the interceptor to wake the gateway from zero).
Validated statically (bash -n, pyyaml parse, disjoint targets). Cluster-only
risk: KEDA + HTTP-add-on API/install specifics, flagged `VERIFY-POINT` in the
HTTPScaledObject.

## CAP-026 — Resource calibration: fix the gateway crash-loop, right-size for observability (research-backed)

- **Date:** r28
- **Status:** accepted; cluster-verification pending (Fedora 44)
- **Context:** r26b's HTTP smoke kept "failing" in ways that turned out to be the
  graphql-gateway pod crash-looping (RESTARTS 2 in 21s on a 256Mi limit) plus
  KEDA scale-up/down timing. Rather than keep bumping smoke timeouts, we stopped
  to calibrate resources against reality before adding the (load-bearing)
  observability stack. Researched realistic sizing for the heavy/uncertain
  tenants: istiod default request ~1Gi (low actual on a tiny mesh), istio-proxy
  sidecars 128Mi each (only order-service's 2 pods are meshed); kube-prometheus
  production guides quote 2–4Gi but assume 15–30d retention + 50–100Gi storage —
  a single-node demo with short retention is far leaner; Tempo monolithic mode is
  a single light container; the OTEL Collector is a light Go binary.
- **Decisions:**
  - **Six Python services → 192Mi req / 512Mi limit** (was 128Mi/256Mi). A
    FastAPI + Strawberry + grpcio service needs ~350–450Mi peak; 256Mi OOM-killed
    the gateway. This is the crash-loop's primary fix.
  - **Add a `startupProbe`** (path /health, failureThreshold 30 × periodSeconds
    2 = 60s grace) to all six. A `startupProbe` gates liveness/readiness until the
    app has booted, so the prior 5s liveness `initialDelaySeconds` no longer kills
    a Python service mid-import. The crash-loop's secondary fix.
  - **Observability sized lean for r29:** OTEL Collector 128Mi/256Mi, Prometheus
    512Mi/1Gi (short retention, small PV), Tempo (monolithic) 256Mi/512Mi, Grafana
    128Mi/256Mi — ~1Gi req / ~2Gi limit total.
  - **No cluster profile bump.** 24Gi/16CPU is adequate: current usage ~12–13Gi
    (OpenMetadata ~3.5–4Gi dominates), projected ~14Gi after observability,
    leaving ~10Gi free — which also gives KEDA scale-ups room to schedule
    promptly. OpenMetadata/OpenSearch/Kafka/Istio/KEDA left as-is.
- **Consequences:**
  - (+) The "KEDA flakiness" was a symptom; this addresses the cause. r26b's HTTP
    smoke should pass on the recalibrated gateway (no OOM, no premature liveness
    kill).
  - (+) Reassuring scope: a rolling restart of the recalibrated service pods, not
    a `minikube delete` / full rebuild.
  - (−) istiod over-reserves (~1Gi) for our tiny mesh; left alone since we have
    headroom (could right-size later if observability pushes us tight).
  - (−) Per-pod limits/probes are not visible offline — verified on the cluster
    (the restart + a clean r26b HTTP run).

### Outcome (Fedora 44, r28 + r28.2)

r28 fixed the crash loop on the first apply — graphql-gateway came up 0/0 with
zero restarts (the 256Mi OOM was real; 512Mi + startupProbe resolved it). But the
HTTP smoke kept timing out on a slow/erratic scale-up (230–400s) that turned out
to be a SECOND, separate issue: the KEDA HTTP interceptor's
`interceptor.replicas.waitTimeout` defaults to **20s**, too short for a cold start
here (KEDA activation + image pull + Python boot + startupProbe). Every held
request 502'd with "context deadline exceeded" before a backend existed, which
ALSO starved KEDA of the stable pending-request pressure it activates on — so
scale-up only crawled up on churn. **r28.2** raises waitTimeout to 180s in
setup-keda.sh; the interceptor now holds the cold-start request through the whole
boot, KEDA gets steady pressure and activates promptly, and a single cold-start
request returns 200. Documented in §17 as a cold-start caveat. Lesson: KEDA HTTP
on a single node has THREE timing knobs that bite — pod resources (OOM),
interceptor waitTimeout (cold-start hold), and the 300s scale-down cooldown —
none visible offline.

---

## CAP-027 — Observability, metrics half: a lean Prometheus + Grafana that adds nothing to the services

- **Date:** r29
- **Status:** accepted; cluster-verification pending (Fedora 44)
- **Context:** The KEDA HTTP saga (~12 rounds, six independent runtime-only
  failures) was the argument for observability making itself: a single graph of
  gateway replicas over time would have shown the wake, the cold-start lag, and
  the near-zero oscillation at a glance. The capstone services are NOT
  instrumented (no app `/metrics`, no OTEL SDK — confirmed by grep), so the
  question was how to observe without rebuilding six images.
- **Decisions:**
  - **Scope split: metrics now (r29), traces later (r29b).** Distributed tracing
    needs either app instrumentation or meshing every service — both bigger moves
    (and meshing all services conflicts with the KEDA-unmeshed decision in
    CAP-025). Metrics deliver the high-value scaling visualization with zero app
    changes, so they go first.
  - **Leverage telemetry that already exists, add nothing to the services.** Two
    free sources: the Istio sidecar on the meshed order-service exports
    `istio_requests_total` (Prometheus's default pod-scrape job picks it up via
    the `prometheus.io/scrape` annotations Istio injects), and `kube-state-metrics`
    exposes `kube_deployment_spec_replicas` / `_status_replicas_ready` — the direct
    recorded signal of KEDA scaling.
  - **Lean standalone stack, not kube-prometheus-stack.** A single Prometheus
    (prometheus-community/prometheus) with alertmanager, pushgateway, and
    node-exporter OFF and kube-state-metrics ON; 24h retention; emptyDir (no
    PVC/StorageClass dependency). Grafana (grafana/grafana) with the Prometheus
    datasource and one dashboard provisioned (pinned datasource uid=`prometheus`
    so the dashboard's panel refs resolve deterministically). Honors CAP-026's
    sizing: Prometheus 512Mi/1Gi, Grafana 128Mi/256Mi, plus kube-state-metrics
    ~64Mi/128Mi (the one addition beyond CAP-026's list). No profile bump.
  - **Chart versions unpinned (latest from repo).** Pin with `--version` for a
    reproducible build; left open here so the install keeps working as charts
    move (and because exact current chart versions weren't verifiable offline).
  - **The payoff dashboard ("Capstone — Scaling & Traffic")** leads with
    desired-vs-ready replicas for graphql-gateway + notification-service
    (step-style), which makes KEDA scaling — including the oscillation from
    CAP-026 — something you watch rather than infer; second panel is order-service
    request rate by response code from the mesh.
- **Files:** `observability/prometheus-values.yaml`,
  `observability/grafana-values.yaml` (inline dashboard JSON),
  `scripts/setup-observability.sh`, `demos/smoke-observability.sh`, §17 new
  section "Seeing it: metrics with Prometheus and Grafana".
- **Consequences:**
  - (+) The capstone is now observable for its scaling and mesh traffic without
    touching service code.
  - (+) Fits existing headroom (~1Gi req added; cluster was ~12–13Gi of 24Gi).
  - (−) No traces yet — a GraphQL query's fan-out across services isn't visible
    until r29b. Documented as the explicit next step.
  - (−) Dashboard/scrape correctness is cluster-only (validated offline: YAML
    parses, embedded dashboard JSON is valid, datasource uid matches panel refs).

---

## CAP-028 — Observability, traces half (backend): Tempo monolithic, no collector, source deferred

- **Date:** r29b
- **Status:** accepted; cluster-verification pending (Fedora 44)
- **Context:** With metrics in place (CAP-027), the remaining observability piece
  is distributed tracing. The KEDA marathon taught a hard lesson about dropping
  multiple untestable new things at once, so this is scoped to isolate variables.
- **Decisions:**
  - **Backend now (r29b), source later (r29c).** r29b deploys the trace *backend*
    (Tempo + Grafana datasource), verifiable on its own; r29c instruments a
    service to emit traces. If traces later don't appear, the failure is
    unambiguously the instrumentation, not the pipeline — the opposite of the
    KEDA debugging experience.
  - **Tempo in monolithic mode** (grafana/tempo single-binary), local storage
    (emptyDir, no PVC), 1h retention, OTLP receivers on (gRPC 4317 / HTTP 4318),
    256Mi/512Mi. Tempo's own recommendation for demo/test setups.
  - **No OpenTelemetry Collector** — a deliberate deviation from CAP-026's sketch.
    The collector's value is fanning telemetry out / processing it, but our
    metrics come from Prometheus *scraping* (CAP-027), not OTLP, so the collector
    would do nothing but forward traces that Tempo receives directly on its own
    OTLP port. Instrumented services (r29c) send OTLP straight to
    `tempo.observability:4317`. A collector can be added later if OTLP-based
    metric/log aggregation or tail-sampling is ever wanted; it isn't now.
  - **Grafana Tempo datasource** provisioned alongside Prometheus (uid=`tempo`,
    url `http://tempo.observability:3200`).
- **Files:** `observability/tempo-values.yaml`, grafana-values.yaml (+Tempo
  datasource), setup-observability.sh (+Tempo install), `demos/smoke-tracing.sh`,
  §17 traces-backend paragraph.
- **Consequences:**
  - (+) Leaner than the original sketch (one fewer component to run/debug).
  - (+) Backend verifiable independently (smoke-tracing: Tempo ready + Grafana
    datasource provisioned/reachable).
  - (−) No traces visible until r29c instruments a service — by design.
  - (−) Chart-schema correctness (tempo values keys, OTLP receiver wiring) is
    cluster-only; validated offline only as parseable YAML.
  - **Repo addendum (r29.2):** the grafana/* helm charts (grafana, tempo) were
    migrated to the `grafana-community` repo effective 2026-01-30; the old
    `grafana/*` charts now emit "this chart is deprecated". setup-observability.sh
    uses `grafana-community/grafana` and `grafana-community/tempo`
    (https://grafana-community.github.io/helm-charts). Values schemas unchanged
    (same charts, relocated). prometheus-community is unaffected.

---

## CAP-029 — Traces source: instrument the gateway with OpenTelemetry (pip-in-image, env-gated, gateway-scoped)

- **Date:** r29c
- **Status:** accepted; cluster-verification pending (Fedora 44)
- **Context:** With the trace backend verified (CAP-028), something has to emit
  spans. The gateway is the entry point for the federated read path, so a single
  GraphQL query there produces the most instructive trace (HTTP server span +
  REST client span to order-service + gRPC client span to inventory-service).
- **Decisions:**
  - **Auto-instrument via pip-in-Containerfile, not poetry.** The builder
    `pip install`s `opentelemetry-distro` + `opentelemetry-exporter-otlp-proto-grpc`
    into the venv and runs `opentelemetry-bootstrap -a install`, which inspects the
    installed libs (FastAPI, httpx, grpc) and pulls matching instrumentations.
    Going through pip (not poetry) means NO `poetry.lock` regeneration — important
    since we can't run `poetry lock` in the build/authoring environment, and it
    keeps an observability concern out of the app's dependency manifest.
  - **Wrap the entrypoint** with `opentelemetry-instrument` (CMD becomes
    `opentelemetry-instrument uvicorn app.main:app ...`). It activates the
    instrumentations and is a no-op without `OTEL_*` env, so the same image runs
    untraced.
  - **Env-gated on the Deployment** (`tracing.enabled`, default true):
    `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`
    (tempo.observability:4317), `OTEL_EXPORTER_OTLP_PROTOCOL=grpc`,
    traces-only (`OTEL_METRICS/LOGS_EXPORTER=none`), sampler ratio (1.0 for the
    demo).
  - **Scoped to the gateway** (not all six services). The async consumers
    (payment/shipping/notification) aren't on the read path, and uniform
    auto-instrumentation across heterogeneous services (Kafka consumers, gRPC
    servers) is uneven — so backends emit no spans yet, and their hops appear as
    the gateway's *client* spans. Full multi-service traces are a mechanical
    extension, deliberately deferred.
- **Files:** services/graphql-gateway/Containerfile (OTEL install + wrapped CMD),
  graphql-gateway values.yaml (`tracing:` block) + deployment.yaml (OTEL env),
  demos/smoke-trace-flow.sh, §17 traces paragraph.
- **Consequences:**
  - (+) A real distributed trace of the federated query, visible in Grafana's
    Tempo explorer — the federation section made concrete.
  - (+) Instrumenting the load-bearing KEDA gateway is low-risk here: the span
    exporter is async/fire-and-forget (Tempo down ≠ request impact), and the
    added startup/memory is absorbed by the r28 startupProbe (60s) + KEDA
    waitTimeout (180s) + 512Mi limit.
  - (−) Partial coverage: backend server spans are absent until those services
    are instrumented too.
  - (−) Unpinned OTEL package versions (bootstrap aligns instrumentation versions
    to the installed SDK); pin for a fully reproducible image. Instrumentation
    correctness and the Tempo search format are cluster-only — smoke-trace-flow's
    trace-found check is therefore best-effort (the HTTP 200 is the hard part).
  - **Export-protocol addendum (r29c.2):** the first cluster run proved the
    instrumentation (all instrumentations installed, gateway 200) but Tempo had
    ZERO traces (`q={}` empty). Cause: OTLP **gRPC on :4317** with an
    `http://...:4317` endpoint silently dropped spans (the grpc exporter attempts
    TLS against a plaintext port; BatchSpanProcessor drops on failure → still 200).
    Fixed by switching to **OTLP HTTP/protobuf on :4318** (`otlpProtocol:
    http/protobuf`, endpoint :4318; Containerfile installs the
    `opentelemetry-exporter-otlp` meta-package). Validated against a working
    user-provided otel-lgtm reference (Java/Podman Compose) using exactly
    `OTEL_EXPORTER_OTLP_ENDPOINT=http://lgtm:4318` + `PROTOCOL=http/protobuf`.
    Also hardened smoke-trace-flow.sh: TraceQL (`q=`) search, not legacy `tags=`,
    plus a gateway-log capture right after the query (before KEDA scale-to-zero).
    Lesson: http/protobuf is the robust OTLP default; gRPC needs the insecure flag.

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

- **Alembic introduction point** (follows from CAP-004) — *resolved*:
  introduced in r25c for notification-service via an init container
  (CAP-021). Other services keep `create_all` until they need to evolve.
- **GraphQL gateway scaling** — single replica assumed; revisit
  if demos need more.
- **OpenMetadata ingestion mechanism** — *partly resolved (CAP-023, r27b):*
  Postgres + Kafka are ingested via one-off Jobs and lineage is declared via the
  REST API. The remaining open question is narrowed to **Apicurio/schema-registry
  linkage** — the official Apicurio connector vs publishing contracts through the
  REST API, and whether to wire the Kafka connector's `schemaRegistryURL` at
  Apicurio's ccompat endpoint. Deferred to **r27c** (Apicurio ingestion).

### r26 design intent — KEDA + Istio as data-mesh capabilities (not bolted on)

Recorded now so the framing survives until r26 is built. r26 wires KEDA and
Istio into the capstone, framed explicitly as serving data-mesh principles
rather than as standalone feature demos (both already appear earlier — §12
KEDA, mid-section Istio):

- **KEDA = elastic data products.** Autoscale the notification consumer on
  Kafka consumer-group lag (the §12 ScaledObject pattern, now applied to a
  capstone data product), so a data product scales with the demand placed on
  it and back to zero when idle. Maps to "data as a product": products own
  their compute and scale independently.
- **Istio = safe contract evolution + observable inter-product traffic.** The
  headline demo (user-requested): take a single service's REST API through a
  **v1 → v2 contract change**, deploy v2 alongside v1, and use Istio traffic
  management (`VirtualService` + `DestinationRule` subsets) to **split live
  traffic** between versions — a canary of a *data product's contract*, not
  just a binary. This is the concrete demonstration of the data-mesh principle
  that products evolve their interfaces without a flag-day break: Apicurio
  holds both contract versions (OpenAPI v1 and v2), the registry can check
  compatibility, OpenMetadata shows the lineage, and Istio controls *who sees
  which version* during migration. Note the terminology distinction: Istio
  *control-plane revisions* + revision tags are for canarying Istio upgrades
  themselves (a secondary "even the mesh upgrades by canary" note); the
  data-product-evolution story is **workload-version traffic shifting** via
  VirtualService/DestinationRule subsets.
- **Visual demonstration (stretch, user-requested):** make the traffic split
  *visible* — e.g. a small live view (or Kiali's graph) showing the v1/v2
  weight shifting, or a blue/green-style indicator, so the canary is legible
  as it happens rather than only inferable from logs. Mechanism TBD at r26
  (candidates: Kiali traffic graph; a tiny inline widget polling each version's
  share; or a generated SVG of the weight split). Decide when r26 is built.
- **Scope note:** keep it to a single API on one service (even a minimal REST
  change — e.g. a renamed/added field, v1 vs v2 response shape) to keep the
  example small and the principle clear.

## CAP-030 — Operational hardening: idempotent bring-up + recovery scripts

**Status:** decided, shipped r30 (offline-validated; cluster-verify pending).

**Context.** The r29c verification exposed two single-node-minikube failure modes
that cost a long debugging session, neither caused by the work under test:
(1) etcd crashlooping in place on `bind: address already in use` (:2380) after a
long uptime, taking the whole control plane down — Exit 1, NOT an OOM; (2) the
in-cluster registry losing all locally-built images across `minikube stop/start`,
surfacing as `ImagePullBackOff: not found`. Recovery was ad-hoc and re-derived
live.

**Decision.** Encode recovery in two scripts and document the failure modes in §17.
- `scripts/cluster-up.sh` — idempotent bring-up: starts the profile; probes
  control-plane health and, if unhealthy, **auto-cycles the node** (stop/start)
  to clear a wedged etcd; diffs the registry catalog (`/v2/<name>/tags/list`)
  against `services/` and **rebuilds ONLY missing images** (per the user's
  "faster, smarter" choice); bounces ImagePull-stuck pods; waits for settle;
  prints the status report. Heals an already-provisioned cluster — does NOT
  re-install operators (they survive a cycle).
- `scripts/cluster-status.sh` — read-only one-shot: profile, control-plane
  health (etcd-wedge aware), missing-image diff, per-namespace pod health, KEDA
  HTTPScaledObject readiness, verdict. Turns the ten-command diagnosis into one.
- §17 gains an "Operating the cluster: bring-up and troubleshooting" section with
  both failure modes, framed diagnostic-first ("read the failing component's exit
  reason before theorizing about resources" — Exit 1 ≠ 137; `not found` ≠
  connection refused).

**Why not re-run all setup-* every time.** The user chose "full capstone every
run," but operators/CRDs/PVCs survive a node cycle; only registry images don't.
So bring-up heals images + bounces pods rather than reinstalling operators
(slow, order-dependent, unnecessary). First-time provisioning remains the
setup-* sequence.

**Consequences.** A reader who stops their cluster overnight runs one command to
get back to green instead of debugging a wall of red. Validated offline: `bash -n`
on both scripts; registry diff uses the same catalog API as build-image.sh.
Cluster-verify: run `cluster-up.sh` from a stopped/wedged state and confirm green.

  - **r29b.1 addendum (CAP-028).** Hardened `smoke-tracing.sh` from a "backend is
    standing" check into an end-to-end ingest proof: it POSTs a synthetic OTLP/HTTP
    JSON span to Tempo :4318 (random 16-byte trace id / 8-byte span id, ns
    timestamps) and reads it back via TraceQL on :3200. This is the check whose
    absence let the r29c export bug slip from the backend stage to the gateway —
    with it, a future "no traces" is localized to the emitter, not the pipeline.
    Hard-asserts both the POST (HTTP 200) and the readback (searchable within
    ~60s). Validated offline: `bash -n`; OTLP/JSON payload parses.
## CAP-031 — Presentation groundwork + phase roadmap (A–E)

**Status:** decided, shipped r31 (assets in place; feature/content phases pending).

**Context.** Post-observability, the remaining work is feature demos, a narrative
that has outgrown one page, a presentation deck, and a replayable walkthrough. The
user provided a "Data Mesh 101" deck and 15 paired SVG+Excalidraw diagrams to
build from, and refined the plan.

**Decisions.**
- **Presentation lives at repo-root `presentation/`** (matches the root-dir
  convention of `assets/`, `scripts/`, `onboarding/`). The 101 deck +
  diagrams are under `presentation/data-mesh-101/`; `presentation/README.md` is
  the design-system source of truth.
- **Design system captured from the 101 deck:** Red Hat brand — accent
  `#EE0000`, text `#151515`, muted `#5A5A5A`, white/off-white `#FFFFFF`/`#FBFAF7`,
  warm `#E6E0D6`; headers Overpass SemiBold, body Red Hat Text (Calibri fallback
  documented). Layout grammar: red title/section panels with a geometric motif,
  white content slides with red ALL-CAPS eyebrow + bold dark title, Red Hat logo
  footer. The new deck reuses this so both read as one family.
- **Phases A & B are demonstrations, not permanent features** — add a new API /
  bump v1→v2, walk the Apicurio + OpenMetadata + Istio-canary affordances, then
  back out and replay. They show data-mesh value from the API/consumer
  perspective, including the various ways to retrieve data and discover metadata.
- **Phase C restructures the single capstone page into a section set** (overview
  + dedicated sections per concept: data mesh, k8s value, Apicurio, OpenMetadata,
  KEDA, Istio/mTLS, Kafka backbone, recoverability, observability+Kiali). Adopted
  diagrams get promoted into `assets/diagrams/` under the `NN-name` convention.
- **Phase E acceptance = the demo vision:** presenter replays with CLI narration
  AND graphical views (live Tempo trace/spans, OpenMetadata lineage, Kiali canary
  live-vs-after, correlated metrics).
- Full plan recorded in `_plans/capstone-roadmap.md`.

**Sequencing.** A → B → C → D → E (features → narrative → deck → walkthrough).
**Next:** Phase A, scoped in detail at the next session start.

**Consequences.** Roadmap and assets are committed and reviewable; the design
system is pinned so Phase D doesn't re-derive it. No runtime/cluster surface in
r31 — pure groundwork.
## CAP-032 — Phase A (part 1): review-service data product

**Status:** decided, shipped r32 (offline-validated; cluster-verify pending).

**Context.** Phase A demonstrates the add-a-data-product-to-the-mesh workflow,
designed to be added and then backed out (a replayable demo). Decisions (user):
a **new standalone service** (best "data as a product" demonstration; produces a
new OpenMetadata lineage node; cleanly reversible as a whole product) with its
**own Postgres schema** (idiomatic; ingestible by OpenMetadata).

**Decision (part 1 — the product itself).**
- New service **review-service**: product reviews/ratings, REST-only, minimal
  deps (no Kafka/gRPC), scaffolded from the order-service template via
  `scaffold-service.sh review reviews`, then given a domain surface.
- Domain: `Review(id, sku, rating 1-5, reviewer, comment, created_at)` in its own
  `reviews` schema. Reviews are keyed by product **`sku`** — the identifier the
  inventory/product domain owns — which is the basis for the lineage edge
  (reviews -> products) declared in part 2.
- REST: `POST /reviews`, `GET /reviews` (+`?sku=` filter), `GET /reviews/{id}`,
  plus `/version` (read by discovery) and the standard `/health`+`/healthz`.
- Seeded with a few rows at startup (idempotent: only when empty) so the catalog
  and lineage demo has data immediately.
- Chart aligned with the **r28 calibration** (requests 192Mi / limit 512Mi +
  startupProbe 30x2s) — the scaffolder predates r28, so the generated chart was
  bumped to avoid repeating the cold-start/OOM class.
- `demos/smoke-reviews.sh` asserts the full REST surface (probes, version, seeded
  rows, create, fetch-by-id, sku filter).

**Explicitly temporary.** review-service is a *demonstration* data product, not a
permanent mesh member. Part 2 (r33) adds the discovery layer (publish OpenAPI to
Apicurio, ingest into OpenMetadata with lineage) and a replayable `up`/`down`
demo harness whose `down` removes the product entirely (helm uninstall + drop
schema + delete Apicurio artifact + remove catalog entry), returning to baseline.

**Build note.** review-service has no committed `poetry.lock` (the scaffolder
defers it); run `poetry lock` in `services/review-service/` before the first
image build (the Containerfile's `poetry export` step needs it).

**Consequences.** Offline-validated: `py_compile` all modules; values.yaml
parses; deployment braces 24/24 with startupProbe; smoke `bash -n`. Cluster-verify:
`./demos/smoke-reviews.sh` green against the running capstone.
## CAP-033 — Phase A (part 2): discovery, catalog, and the replayable demo

**Status:** decided, shipped r33 (offline-validated; cluster-verify pending).

**Context.** Part 1 (r32) shipped the review-service product, verified. Part 2
adds the discovery layer and wraps the whole thing in a replayable demo, per the
Phase A intent (add → show → back out → repeat).

**Decision.**
- `openmetadata/ingestion/reviews_lineage.py` — declares/removes a single
  lineage edge `inventory.stock -> reviews.reviews` (products referenced by
  reviews). Mirrors the proven `lineage.py` (stdlib, OM_HOST/OM_JWT env) but is
  SEPARATE from it so the temporary product never touches the permanent
  orders->order-placed->notifications spine. `up` PUTs the edge, `down` DELETEs it.
- `demos/demo-add-data-product.sh up|down` — the replayable harness:
  - **up**: build+deploy review-service → publish its `/openapi.json` to Apicurio
    as `review-service-openapi` (same v3 POST pattern as
    publish-discovery-contracts.sh) → re-run `ingest-openmetadata.sh` (catalogs
    the new reviews schema automatically — postgres.yaml ingests every schema) →
    declare the reviews->products lineage → verify the catalog entry → print the
    three "ways in" (REST, Apicurio contract, OpenMetadata catalog+lineage).
  - **down**: remove the lineage edge → delete the reviews schema entity from the
    catalog → delete the Apicurio artifact → `helm uninstall` → `DROP SCHEMA
    reviews CASCADE` on the CNPG primary. Returns the mesh to baseline.
- Reuses proven machinery (publish pattern, ingest-openmetadata.sh, get_token.py)
  so the `up` path is low-risk.

**VERIFY-POINTS (cluster-only; the `down` path's most likely to need a tweak,
same class as the existing OM files' caveats):**
  * OM lineage delete: `DELETE /api/v1/lineage/table/{fromId}/table/{toId}`.
  * OM schema delete: `DELETE /api/v1/databaseSchemas/name/{fqn}?hardDelete=true&recursive=true`.
  * Postgres drop: `kubectl exec <primary> -c postgres -- psql -U postgres -d capstone`
    (CNPG primary container name + superuser).
  * Apicurio v3 delete: `DELETE /apis/registry/v3/groups/default/artifacts/{id}`.
The `down` steps are best-effort (warn, don't hard-fail) so a partial back-out
still progresses and reports what to finish manually.

**Consequences.** Offline-validated: `py_compile` reviews_lineage.py + the inline
publish python; harness `bash -n`; usage/arg handling. Cluster-verify:
`./demos/demo-add-data-product.sh up` lands the product through all three layers
(REST + Apicurio + OpenMetadata lineage), then `down` returns to baseline; replay
to confirm idempotence. This completes Phase A.
## CAP-034 — Ingestion Jobs must opt out of Istio sidecar injection

**Status:** decided, shipped r34 (offline-validated; cluster-verify pending).

**Context.** Phase A's `demo-add-data-product.sh up` failed at the OpenMetadata
ingestion step: the `om-ingest-postgres` Job pod ran `0/2` (istio-init +
istio-proxy injected) and the `ingest` container exited 1. The capstone namespace
was `istio-injection=enabled`, so the Job got a sidecar. A meshed Job is wrong:
the istio-proxy starts as a peer container that races the ingest container at
startup, and — fatally for a Job — the proxy never exits, so the pod can't reach
`Completed`. (The `pagila`/`acmecorp_gold` text seen in the logs was the ingestion
image's bundled SAMPLE config printed in its banner, NOT the mounted ConfigMap;
the live ConfigMap was confirmed correct. So this was a single cause, not two.)

**Decision.** Add `sidecar.istio.io/inject: "false"` to the pod-template
annotations of all three ingestion Jobs (`job-postgres.yaml`, `job-kafka.yaml`,
`job-lineage.yaml`). Ingestion Jobs are short-lived batch work talking directly
to Postgres/Kafka/OpenMetadata; they should never be meshed.

**Broader finding (not fixed here, flagged for a deliberate decision).** The
capstone namespace is now labeled `istio-injection=enabled` (namespace-wide),
whereas the documented state was *selective* injection (per earlier notes, only
order-service was meshed). A node cycle appears to have left the namespace with
broad injection, so now every capstone pod gets a sidecar (services show 2/2).
Namespace-wide mTLS is defensible (arguably desirable for the mesh story), but
it's a drift from the documented selective model and should be made a conscious
choice — either embrace namespace-wide injection in the setup (and update the
mesh narrative) or pin selective injection. The Job opt-out above is correct
either way. Tracked for the Phase C Istio/mTLS section.

**Consequences.** Offline-validated: all three Job manifests parse;
`inject=false` present; `restartPolicy: Never` intact. Cluster-verify: re-run
`./demos/demo-add-data-product.sh up` — the ingestion Jobs now complete (`1/1
Completed`, unmeshed), and the run proceeds to lineage + the catalog check.
## CAP-035 — bootstrap-capstone.sh: one-command full bring-up

**Status:** decided, shipped r35 (offline-grounded; first cluster run pending).

**Context.** A 21-hour-old node degraded past recovery (full crashloop incl. the
control plane; a containerd-shim panic; `cluster-up.sh`'s stop/start couldn't
heal it). Disk was fine (11%), so the verdict was a clean rebuild
(`minikube delete`). That exposed the real gap: **there is no one-command full
bring-up.** The README froze at r20, and the actual order lived scattered across
seven setup-* scripts, helm installs for kafka/apicurio/postgres/six services,
`kubectl apply` for the KEDA scalers and Istio canary, plus seed + discovery +
ingestion. Every recovery this session was manual archaeology because of it.

**Decision.** `scripts/bootstrap-capstone.sh` — health-gated, idempotent, ordered
full bring-up from a fresh node, with every command lifted verbatim from the
proven smokes/setup scripts (not invented). Tiers, each gated before the next:
profile+registry → Istio → CNPG operator → **Postgres CR** (OpenMetadata depends
on it, so it precedes OM) → Kafka operator+CR (`kubectl wait kafka/capstone-kafka
Ready`) → KEDA → OpenMetadata (scaled to 1 + rollout-waited, since a prior session
can leave it at 0) → observability → images (build only-if-missing) → apicurio →
six services (rollout-waited, skipping the KEDA-zero gateway) → scalers → seed one
order. Catalog population (discovery + ingestion) and the canary are printed as
explicit follow-ons rather than run inline (warm-server port-forwards; the canary
is Phase B). Ends with a `cluster-status.sh` report.

**Why printed follow-ons, not inline.** Discovery/ingestion need a warm OM and
port-forwards and were the flaky bits all session; keeping them out of the
critical bring-up path makes bootstrap reliable and the catalog step explicit.

**This becomes Phase E step 1** ("stand the whole thing up") and the canonical
answer to "how do I get a capstone from nothing."

**Honest caveat.** Grounded but not run offline (no cluster in the authoring
env); every individual step is proven, but ordering/gating get their first real
exercise on the rebuild. Expect possibly one tweak on first run. Validated:
`bash -n`; all 19 referenced charts/manifests/scripts exist.

**Earned follow-ons (deferred to r36, not blocking the rebuild):**
  * `cluster-up.sh` settle check waits on *core* workloads Ready, not all-pods-
    Running (the false 4-min timeout: KEDA-zero + Completed jobs never let it reach
    "no not-Running pods").
  * `cluster-status.sh` flags **scaled-to-zero** expected workloads (an OM at
    `0/0` showed no unhealthy pods, so it hid).
  * `demo-add-data-product.sh` gets an OM-reachability pre-flight (scale/wait or
    fail fast) instead of dying deep in ingestion.

**Process note (owned).** Several blockers this session were node decay, but one —
OpenMetadata left scaled to zero — was my earlier wrong-theory suggestion during
the etcd-wedge debugging. The node was already failing; that advice added churn.
The lesson recorded: when the whole node is unhealthy, rebuild early rather than
peel symptoms.
## CAP-036 — Raise the node's PID ceiling (podman pids-limit default)

**Status:** WITHDRAWN (superseded by CAP-037). The PID-ceiling diagnosis was
WRONG. The 2048 we measured was the node's *root* cgroup; pods live in
`kubepods.slice` whose `pids.max` is 509255 (0.3% used), so a PID cap never
constrained the pods. The live root-cgroup write also fails on a rootless node
(`Operation not permitted`). The r36 script edits were reverted. The true cause
is the istio-proxy startup race — see CAP-037. Kept here as an honest record of
a wrong turn: the lesson is to confirm *which* cgroup bounds the workload before
treating a number as the limit.

**Context.** On the freshly-bootstrapped node, the last service to start
(order-service — the one meshed app pod) was stuck `RunContainerError`:
`runc create failed: unable to start init: fork/exec /proc/self/fd/6: resource
temporarily unavailable` (EAGAIN, exit 128). The app never ran — the runtime
couldn't fork its init. Probes ruled out everything else: kubelet `podPidsLimit`
unset (-1), no containerd pids cap, image CMD correct
(`uvicorn app.main:app ...`), layers pulled fine, global `pid_max`=4194304 /
`threads-max`=509255 huge. The smoking gun: the node container's **root cgroup
`pids.max = 2048`** with **`live tasks: 1966`** (96% full). That 2048 is podman's
default `--pids-limit` applied to the minikube node container — a cap on TOTAL
processes across ALL pods on the node. The full capstone (CNPG, Kafka, KEDA,
OpenMetadata+OpenSearch JVMs, Prometheus/Grafana/Tempo, six services, and — under
namespace-wide injection — six Envoy sidecars) sits right under 2048, so the
kubelet can't fork the next pod's init.

**Decision.** Raise the node's PID ceiling. cgroup v2 `pids.max` is writable live,
so:
  * **Immediate (no rebuild):** `minikube ssh -p capstone -- 'echo max | sudo tee
    /sys/fs/cgroup/pids.max'` then `kubectl rollout restart deploy/order-service`.
  * **Durable (repo):** `setup-capstone-profile.sh` raises `pids.max` to `max`
    right after `minikube start`; `cluster-up.sh` does the same after BOTH its
    start and its auto-cycle restart (a stop/start resets podman's default, so it
    must be re-applied every time the node container starts). Idempotent and
    harmless if already raised.

**Why not kubelet podPidsLimit / containerd config.** Both were unset; the cap
originates from podman's container-creation default, which lands on the node's
root cgroup. Writing the cgroup is the direct, driver-agnostic lever and needs no
node recreate.

**Related, deliberately NOT changed here (forces the Phase C Istio decision).**
The capstone namespace is `istio-injection=enabled` (namespace-wide), which is a
drift from the documented *selective* injection design — the order-service
deployment comment explicitly says "we mesh order-service for the canary, not the
whole namespace." Namespace-wide injection put an Envoy on all six services,
~doubling sidecar process pressure and contributing to the 1966 task count (and it
was the root of the r34 ingestion-Job sidecar problem too). Reverting to selective
injection (mesh only order-service) would roughly halve sidecar pressure AND fix
the Jobs class — but changing injection scope on a running cluster is disruptive
(existing meshed pods must restart to drop sidecars; the webhook namespaceSelector
mechanics need a cluster to verify), so it is recorded as the **Phase C Istio/mTLS
decision**, now clearly justified. The pids.max raise is the correct durable fix
regardless of which injection model is chosen.

**Consequences.** Offline-validated: both scripts `bash -n` clean and raise
pids.max (setup on start; cluster-up on start + cycle). Cluster-verify: after the
live `echo max` + rollout restart, order-service reaches `2/2` Ready, completing
the bring-up. Future bootstraps get the headroom automatically.

## CAP-037 — order-service startup resilience (mesh proxy race + retry)

**Status:** decided, shipped r37 (offline-validated; cluster-verify pending).

**Context.** After the node rebuild, order-service crash-looped. Peeling the
layers (and correcting several wrong theories along the way — image, then a PID
ceiling): the app container *runs*, then exits with
`socket.gaierror: [Errno -2] Name or service not known` raised inside asyncpg's
`_create_ssl_connection` during FastAPI startup, followed by
`Application startup failed. Exiting.` CoreDNS proved healthy
(`capstone-postgres-rw.capstone.svc.cluster.local` → NOERROR) and the env was
correct (`PG_HOST` = that FQDN). The failure is the **istio-proxy startup race**:
order-service is the one meshed app pod, and its `lifespan` makes outbound
connections (Postgres via `init_schema`, then Kafka+Apicurio via `start_producer`)
the instant it starts — before Envoy has programmed routes, so the first connect
fails. The app exited on first failure (no retry), so it crash-looped. This bites
*now* because namespace-wide injection meshed order-service (the drift flagged in
CAP-034/036); under the documented selective model it would still be meshed (it's
the canary), so the fix is needed regardless.

**Decision (defense in depth — both, since each is correct alone).**
  1. **Hold the app until the proxy is ready.** Pod annotation
     `proxy.istio.io/config: '{"holdApplicationUntilProxyStarts": true}'` on
     order-service — Istio delays the app container until Envoy serves, closing
     the race directly.
  2. **Retry the startup connects with capped backoff.** `init_schema` (db.py)
     and `start_producer` (events.py) now retry (≤30 attempts, delay capped 4s,
     ~seconds in the common case) instead of exiting on first failure — robust
     against a transient-unready dependency on any cold start, mesh or not. The
     half-open Kafka producer is stopped between attempts.
  3. **Startup-probe headroom.** order-service `probes.startup.failureThreshold`
     30 → 60 (60s → 120s budget), since the app's HTTP server only serves after
     `lifespan` completes; the retries must fit inside the probe window.

**Why both.** With native sidecars the hold may be partly automatic, but the
annotation makes intent explicit; the retry is the cause-agnostic safety net that
also covers a slow Postgres/Kafka cold start. Neither alone is as robust as the
pair.

**Scope.** Applied to order-service (the failing, dependency-heavy, meshed
service). The retry pattern is good practice for any service that connects at
startup; propagating it to the others is a noted follow-on, not done here.

**Consequences.** Offline-validated: db.py + events.py `py_compile`; annotation
value is valid JSON; values.yaml parses (startup budget 120s); deployment.yaml
annotations intact. Cluster-verify: rebuild order-service image, redeploy, and it
reaches 2/2 Ready through a cold start without crash-looping; then resume Phase A.

## CAP-038 — Postgres: exclude from mesh + size for crash-recovery

**Status:** decided, shipped r38 (live-patched + chart fix; cluster-verify pending).

**Context.** With order-service finally past its own startup race, its retry loop
surfaced a persistent `ConnectionResetError` to `capstone-postgres-rw:5432` —
because **Postgres itself was crash-looping**, for two stacked reasons:

1. **It was meshed.** Namespace-wide injection put an istio-proxy on the CNPG
   instance pod (`istio-init`/`istio-proxy`/`bootstrap-controller`/`postgres`,
   `1/2`). CNPG runs its own TLS on the instance-manager status/replication
   ports; the injected Envoy intercepted and re-wrapped those connections,
   breaking CNPG's TLS — the `postgres` container exited 2 amid `crypto/tls`
   read churn, and the operator reported "Instance Status Extraction Error: HTTP
   communication issue" (it couldn't reach the manager). This is the same
   namespace-wide-injection drift behind CAP-034 (ingestion Jobs) — operator-
   managed infra must not be meshed, exactly as the order-service chart comment
   always said.
2. **It was undersized.** Once unmeshed (`1/1`), Postgres started but was
   `OOMKilled` at its `512Mi` limit during startup crash-recovery (WAL replay
   after the unclean restarts). 512Mi is the tiny-FastAPI budget from CAP-026; a
   database with an instance-manager and recovery spikes needs real headroom.

**Decision.**
  * **Exclude Postgres from the mesh** via the CNPG Cluster `spec.inheritedMetadata`
    (annotation `sidecar.istio.io/inject: "false"`), which CNPG propagates to the
    instance pods. Persisted in `charts/capstone/charts/postgres/templates/cluster.yaml`
    so a fresh bootstrap never meshes it.
  * **Raise Postgres resources** (`charts/capstone/charts/postgres/values.yaml`):
    request 256Mi→512Mi, limit 512Mi→**2Gi** — headroom for the instance-manager
    plus WAL-replay recovery.

**Broader model (the Phase C Istio decision, now decided in practice).** The
"selective injection" the capstone always documented — mesh only order-service
for the canary, keep sidecars off operator-managed infra — is the correct model,
and namespace-wide injection has now demonstrably broken three things (ingestion
Jobs, the order-service chase, Postgres). r38 opts Postgres out explicitly;
Kafka/Apicurio/OpenMetadata currently tolerate their sidecars, so they are left
as-is for now, but Phase C should opt all operator-managed infra out (or remove
the namespace-wide label and rely on per-workload opt-in) to make the model
uniform. Recorded so it is a conscious choice, not drift.

**Consequences.** Live-patched the running cluster (inject:false already applied;
resources patch to follow) and fixed the chart. Offline-validated: values.yaml
parses (req 512Mi / lim 2Gi); cluster.yaml renders structurally with
inheritedMetadata + resources intact. Cluster-verify: Postgres returns `1/1` and
stays Ready (no OOM, no TLS crash), the CNPG cluster reports healthy, and
order-service connects on its next retry and goes `2/2` — closing the bring-up.

## CAP-039 — Phase B: complete the v1→v2 canary (align v2 + repeatable demo)

**Status:** decided, shipped r39 (offline-validated; cluster-verify pending).

**Context.** The canary was scaffolded at r26 (CAP-024): `istio/routing.yaml`
(Gateway + weighted VirtualService with `__W_V1__/__W_V2__` + DestinationRule
v1/v2 subsets), `smoke-canary.sh` (deploys v2, drives 90/10→50/50, asserts the
split), `istio/order-service-v2.yaml` (v2 = same image, `API_VERSION=v2`), and
the `/version` canary signal (v2 reports `api_version=v2` + an additive
`currency` field). Phase B's job was to make it actually run on the current
cluster and give it a clean rollback.

**Problem found.** `order-service-v2.yaml` predated tonight's order-service
hardening, so v2 diverged from v1: no `holdApplicationUntilProxyStarts` (CAP-037),
no startupProbe, and resources at 256Mi vs v1's 512Mi (CAP-026) — v2 would hit
the same proxy-startup race v1 just got fixed for, and risked OOM. (v2 reuses the
v1 image, so it inherits the db.py/events.py startup retry for free — but the pod
annotations and resources are overlay-local and had to be brought into line.)

**Decision.**
  * **Align v2 with v1:** add the `proxy.istio.io/config`
    `holdApplicationUntilProxyStarts` annotation, add the 120s startupProbe, and
    raise resources to 192Mi/512Mi. v2's env was already correct (matches v1's
    rendered chart env exactly).
  * **Add `demos/demo-canary.sh up|shift|down`** — the presenter-facing,
    repeatable, backable-out counterpart to the verification-facing
    smoke-canary.sh. `up [w1 w2]` deploys v2 + opens the split (default 90/10);
    `shift w1 w2` moves it (50/50, 0/100, …); `down` drains to v1, removes the
    Gateway/VirtualService/DestinationRule and the v2 Deployment, restoring a
    v1-only baseline. This is the "repeatable / backable-out" the roadmap asked
    for and parallels Phase A's demo-add-data-product.sh up/down.

**The drift lesson (ties to CAP-038's theme).** A hand-maintained v2 overlay will
keep drifting from the v1 chart (this is the second time: it missed CAP-037/038).
Noted option for later: parametrize the order-service chart so v2 is a second
helm release (`--set version=v2,apiVersion=v2`) with the shared Service rendered
once — eliminating the overlay. Deferred (it changes smoke-canary and revisits
CAP-024's overlay choice); the alignment above is the right scope for tonight.

**Consequences.** Offline-validated: v2 manifest parses with all three alignments;
demo-canary.sh `bash -n` clean and its `down` targets exactly the objects
routing.yaml creates; `/version` confirmed to emit v2 + currency. Cluster-verify:
`./demos/smoke-canary.sh` lands the 90/10 and 50/50 splits in-band, and
`demo-canary.sh up → shift → down` cycles cleanly. A+B together demonstrate the
data-mesh value from the API/contract perspective (add a product, then evolve its
contract under canary).

## CAP-040 — Idle-node decay: kube-proxy /dev loss wedges Service routing

**Status:** documented (operational finding); recovery = node cycle.

**Context.** Returning to the capstone after ~17h idle, the v1→v2 canary's v2 pod
would not create: the sidecar-injection webhook call to the istiod ClusterIP
`10.x:443` was refused. Diagnosis ruled out istiod (pod Ready, logged
`webhook service at [::]:15017`, endpoints listed `https-webhook=15017`, and an
in-cluster `nc` to the istiod POD IP `:15017` succeeded) — but `nc` to the istiod
SERVICE ClusterIP `:443` failed. Service-IP refused while pod-IP open = a
kube-proxy/Service-routing fault, not an Istio fault.

Root cause: **kube-proxy was CrashLoopBackOff** with a node-level error —
`runc create failed: error creating device nodes: mount src=/dev/bsg/0:0:0:0 ...
no such file or directory`. A device node present at node creation had vanished
from the rootless-podman node container's `/dev` during the idle period, so
kube-proxy couldn't init. With kube-proxy down, ClusterIP routing was broken
cluster-wide — which is why the istiod webhook ClusterIP refused AND why the
whole capstone namespace was stuck `Init:1/2` (init containers couldn't reach
Services). One root cause, many symptoms.

**Lesson / guidance (tutorial-worthy).**
  * **Symptom→cause shortcut:** "connection refused to a healthy Service's
    ClusterIP, but the backing pod IP is reachable" = Service-routing/kube-proxy,
    NOT the backing workload. The decisive test is `nc <svc> <port>` vs
    `nc <podIP> <targetPort>` from an unmeshed throwaway pod — Service fails /
    pod open pins it to kube-proxy.
  * **Idle-node decay is real on single-node rootless minikube:** a node that
    sat idle can lose `/dev` device nodes, wedging kube-proxy and thus all
    Service routing. Piecemeal restarts (istiod, the deploy, even kube-proxy
    itself) don't fix it because the node container's `/dev` is degraded.
  * **Recovery:** cycle the node — `./scripts/cluster-up.sh` (detects the wedge,
    stop/starts, rebuilds registry images, bounces stuck pods), then
    `./scripts/cluster-status.sh`. A stop/start re-creates the node container
    with fresh `/dev` + kube-proxy + Service rules. Full
    `minikube delete && bootstrap-capstone.sh` if the cycle doesn't clear it.
  * **Operational habit:** when resuming a capstone after a break, run
    `cluster-up.sh` (or at least `cluster-status.sh`) BEFORE demoing — don't
    assume the node is exactly as you left it. Worth stating in §17's
    "Operating the cluster" section alongside the existing etcd-wedge and
    registry-loss notes.

**Phase C tie-in.** This was a kube-proxy fault, not Istio — but it again showed
that namespace-wide injection couples every pod-create to the istiod webhook
being routable. Selective injection would have let non-mesh infra keep deploying
even with the istiod ClusterIP unreachable. Another point for that decision.

## CAP-041 — Node PID ceiling: raise podman pids_limit at node creation

**Status:** decided, shipped r40 (guard in profile script + host containers.conf).
**Supersedes:** CAP-036 (withdrawn — that tried a live cgroup write, which fails
on a rootless node). This is the correct, creation-time fix.

**Context.** On every fresh bootstrap, seven tiers come up clean but order-service
fails its rollout with `StartError` / exit 128 /
`fork/exec /proc/self/fd/6: resource temporarily unavailable` (EAGAIN), crash-
looping. Confirmed decisively this time: the node container's ROOT cgroup
`pids.max=2048` (podman's `--pids-limit` default) with `pids.current=2043` —
**99.8% full**. That 2048 caps TOTAL processes across all pods on the node; the
full meshed capstone (CNPG, Kafka, KEDA, OpenMetadata+OpenSearch JVMs,
observability, six services, six Envoy sidecars) runs ~2000+ tasks, so the
kubelet can't fork the last/heaviest pod's init. order-service is the casualty
because it's meshed (app + Envoy) and starts last. (kubepods.slice pids.max is
huge — 509255 — which is why earlier I wrongly ruled PID out; the cap is on the
node *root* cgroup, not the pods slice.)

**Why CAP-036's approach failed.** It tried `echo max > /sys/fs/cgroup/pids.max`
live on the running node — `Operation not permitted` on rootless (the node
container's top-level pids.max is owned by the parent and locked from inside).

**Decision.** Raise podman's default at CREATION time via host
`~/.config/containers/containers.conf`:
```
[containers]
pids_limit = 0          # 0 = unlimited (or a high number ≥ 8192)
```
Then recreate the node (`minikube delete -p capstone && bootstrap-capstone.sh`)
so the node container is born without the 2048 cap. `setup-capstone-profile.sh`
now GUARDS this: it reads the effective podman pids_limit and hard-fails with
the exact fix if it's a low number (< 8192 and not 0), the same way it already
guards fs.inotify limits. The repo can't set a user's host containers.conf, but
it can refuse to build a node that would suffocate.

**§1 prerequisite.** This belongs in the §1 prerequisites alongside the inotify
sysctl tweak: rootless podman defaults to pids_limit=2048 per container, which is
too low for a node hosting the whole capstone — set pids_limit=0 in
containers.conf before first bring-up.

**Consequences.** Offline-validated: guard parses `pids_limit = 0`→accept and
`= 4096`→reject correctly; `bash -n` clean. Cluster-verify: set containers.conf
pids_limit=0, `minikube delete && bootstrap-capstone.sh` → node root pids.max is
no longer 2048, order-service forks and reaches 2/2, bootstrap hits a true 8/8
for the first time. Then Phase B canary verification can finally run.

## CAP-042 — Kiali for mesh topology, wired to the existing observability stack

**Status:** decided, shipped (Phase E.0); `unverified` until a cluster run.

**Context.** The demo walkthrough's final act is the live mesh topology — the
products and the traffic between them, canary split included. The capstone
observability stack (CAP-027/028/029: Prometheus + Tempo + Grafana in the
`observability` namespace) has no topology view; Kiali is the piece that
provides it. Kiali is already proven in §11 (r12g) via the full Istio
`samples/addons/` bundle, but that bundle also installs its OWN Prometheus,
Grafana, Jaeger, and Loki.

**Decision.** Add Kiali as its own run-once step (`scripts/setup-kiali.sh`),
installing ONLY `samples/addons/kiali.yaml` — not the full addons bundle — and
patching the `kiali` ConfigMap's `config.yaml` so `external_services` points at
the capstone's EXISTING `observability`-namespace Prometheus
(`prometheus-server.observability`), Grafana (`grafana.observability`), and Tempo
(`tempo.observability:3100`). Single observability stack, no second TSDB. Kiali
is additive and isolated: it runs after `setup-istio.sh` + `setup-observability.sh`
and touches nothing they own. Verification is `demos/smoke-kiali.sh` (Ready +
config wired to capstone Prometheus + `/healthz` + `/api/namespaces` lists
`capstone` + a best-effort graph-API probe).

**Why not the §11 approach (full samples/addons).** That stands up a parallel
Prometheus/Grafana/Jaeger/Loki, which would (a) duplicate and conflict with the
capstone stack, (b) bloat the node's footprint right after CAP-041's PID-ceiling
fight, and (c) split metrics across two TSDBs so the dashboard and the topology
disagree. Single-stack wiring keeps one source of truth.

**Why standalone, not folded into setup-istio.sh.** Kiali is opt-in and only
needed for the demo/topology view; keeping it a separate script means a cluster
that just needs the canary doesn't pay for it, and it can be skipped or removed
without touching the Istio install.

**Consequences.** Offline-validated: `bash -n` clean on both scripts; the
ConfigMap patch is a JSON merge on `data."config.yaml"` only (preserves the
addon's labels/metadata; idempotent). Cluster-verify (pending): run
`setup-istio.sh` → `setup-observability.sh` → `setup-kiali.sh`, then
`smoke-kiali.sh` should PASS and, after a traffic-generating demo, the Kiali
graph (namespace `capstone`) should show the products and their edges with the
canary split. VERIFY-POINT: the addon ConfigMap is assumed to be named `kiali`
with key `config.yaml`; if the installed Kiali/Istio version differs, adjust the
patch in `setup-kiali.sh` and the config check in `smoke-kiali.sh`.

## CAP-043 — Phase E presenter walkthrough: orchestrator over the existing demos

**Status:** decided, shipped; `unverified` until a presenter run on the cluster.

**Context.** The deck's "What you can see it do" slide names five things a live
demo would show: a trace whose spans cross three products, KEDA scaling on lag,
a contract canaried by weight, OpenMetadata lineage, and the live Kiali
topology. Each is already a working script in `demos/` (CAP-024–029, CAP-042).
What was missing was a single replayable thread for a talk.

**Decision.** `demos/walkthrough.sh` orchestrates the five existing
scripts in order with narration between them — it does NOT reimplement their
logic. Presenter-driven: Enter to advance between acts so the operator controls
the tempo, can pause for questions, and can investigate a failure without
losing context (resources stay in place; the underlying smoke scripts already
behave this way). The walkthrough's only new logic is:

- A preflight that checks each component the chosen acts need (kubectl,
  `capstone` ns, Tempo, Istio, KEDA, OpenMetadata, Kiali) with a fix message
  pointed at the specific setup script. Skippable via `--no-preflight`.
- `--only ACT` to rehearse a single act and `--skip ACT` to drop one (both
  validated against the act list — typos fail fast instead of no-opping).
- The Kiali act starts a port-forward the presenter shows in the browser
  through the rest of the discussion, then tears it down on exit (trap).

Rejected alternatives: a standalone narrated re-implementation (would duplicate
demo logic and drift), and a thin menu (less of a narrative — the linear
five-act arc is the point).

**Consequences.** Offline-validated: `bash -n` clean; `--help` and arg
validation exercised. Cluster-verify pending: a full run-through on a healthy
capstone profile. Because the walkthrough shells out to the existing scripts,
any future fix to a demo (e.g. the Kiali web_root fix from CAP-042) is picked
up automatically.

## CAP-044 — Bootstrap installs everything the walkthrough needs; preflight enforces it

**Status:** decided, shipped; `unverified` until a full bootstrap run.

**Context.** With Phase E shipped (CAP-043, the `walkthrough.sh` orchestrator),
two acts hit a class of failure that was unfair to the operator: lineage
(`smoke-om-lineage.sh`) failed because ingestion hadn't been run, and topology
(`smoke-kiali.sh`) failed because Kiali wasn't installed. Both were
documented-but-manual steps from earlier iterations (Kiali only existed as
CAP-042; `ingest-openmetadata.sh` was always a footer recommendation in
bootstrap rather than a step bootstrap ran). The walkthrough's preflight could
detect them, but the underlying principle was wrong: a presenter shouldn't have
to remember manual steps to make the demo work.

**Decision.** Two changes:

1. `scripts/bootstrap-capstone.sh` is now the single command that produces a
   walkthrough-ready cluster. Step 9 (new) runs `setup-kiali.sh`; step 10
   (new) runs `ingest-openmetadata.sh`. Both are idempotent: Kiali via JSON
   merge-patch on the addon ConfigMap (CAP-042), ingestion via
   delete-then-apply Jobs that the script's header already documents as
   re-runnable (OpenMetadata upserts by FQN; the lineage PUT is idempotent).
   The footer "to populate the catalog and finish" message that previously
   told operators to run those manually is replaced by the walkthrough as the
   top-line follow-on.

2. `demos/walkthrough.sh` preflight adds two checks for these dependencies,
   each with a fix message pointing at the specific script (`setup-kiali.sh` /
   `ingest-openmetadata.sh`) *or* a re-run of bootstrap. This is belt and
   suspenders: a clean bootstrap should always satisfy them, but if an
   operator runs the walkthrough on a partial or out-of-date cluster, the
   preflight tells them exactly what to fix instead of failing mid-act.

**Rejected alternative.** Folding `setup-kiali.sh` and `ingest-openmetadata.sh`
into `walkthrough.sh` itself. Rejected: the walkthrough is a *demo* script and
should fail fast on missing prerequisites, not install them. If it installed
Kiali, by the same logic it should install Istio, observability, KEDA, etc. —
and then it's a bootstrap script, not a demo. The walkthrough/bootstrap
separation is preserved.

**Consequences.** Offline-validated: `bash -n` clean on `bootstrap-capstone.sh`
and `walkthrough.sh`; all step numerators renumbered 1/10..10/10. The ingest
check is a Job-existence test (`om-ingest-postgres`, `om-ingest-kafka`,
`om-declare-lineage` all present in `capstone`), since OpenMetadata's catalog
state isn't trivially queried from kubectl alone. Cluster-verify (pending):
on a fresh profile, `bootstrap-capstone.sh` finishes with all 10 steps green
and `./demos/walkthrough.sh` (no flags) gets to act 5 without operator
intervention beyond pressing Enter — including running the trace act, the one
remaining sore spot from this iteration (see follow-ups: KEDA HTTP cold-start
race, not addressed here).

## CAP-045 — Gateway HTTPScaledObject min:1, not min:0 (live-demo amendment to CAP-025)

**Status:** decided, shipped; `unverified` until a cluster run.

**Context.** With the walkthrough's trace act (CAP-043, act 1), the gateway's
scale-from-zero path consistently produced HTTP 502 with header
`X-KEDA-HTTP-Cold-Start: true`. Diagnosis (after extensive elimination — see
the iteration log): the KEDA HTTP add-on 0.12.2 interceptor has a hardcoded
~15-second cold-start budget (`DialRetryTimeout`), and the graphql-gateway's
uvicorn cold start exceeds it. The interceptor gives up before the gateway is
ready, returns 502, KEDA then scales the gateway back down within its
30-second `scaledownPeriod`, and the next request triggers the same race.

**What didn't work, for the next-engineer record.**
- Raising `KEDA_RESPONSE_HEADER_TIMEOUT` to 15s (env-var present but the field
  it maps to in 0.12.2 isn't the cold-start budget).
- Setting `KEDA_HTTP_INTERCEPTOR_LOG_REQUESTS=true` (not honored by 0.12.2;
  the env-var name is `KEDA_HTTP_*` *without* the `INTERCEPTOR_` infix).
- The `autoscaling.keda.sh/paused-replicas` annotation (works on KEDA's core
  `ScaledObject`, not on the HTTP add-on's `HTTPScaledObject`).
- A pre-warm GET in `smoke-trace-flow.sh` (the warmup succeeded in waking the
  gateway, but KEDA HTTP scaled it back down between the warmup and the real
  POST faster than the script could send the second request).

The 0.14 docs name a `readinessTimeout` / `KEDA_HTTP_READINESS_TIMEOUT` knob
that *would* solve this, but 0.12.2 doesn't expose it and we're on 0.12.2 in
the capstone. A chart upgrade is its own iteration (new `InterceptorRoute`
CRD, different config shape).

**Decision.** Change the gateway's `HTTPScaledObject` from `replicas.min: 0` to
`replicas.min: 1`. The gateway always has one warm replica ready for the first
request; the autoscaler still scales out to `max: 3` under load. The
notification-service `ScaledObject` continues to scale to zero on Kafka lag
(CAP-025), so the "elastic data products" story is told by the event consumer
half of the architecture — which can cleanly scale to zero because Kafka lag
is a backlog signal, not a request-latency one.

**Narrative implication** (for the deck and the §17 prose). The honest split
is now: *event consumers scale to zero on lag (cheap, deterministic);
synchronous read gateways stay warm at a low baseline and scale out on traffic
(deterministic first-request latency).* Both are "elastic data products" —
just calibrated to their workload's character. This is actually a more honest
story than "everything scales to zero", which papers over the cold-start cost
of synchronous interfaces.

**Consequences.** Offline-validated: YAML loads, smoke script lints. The
pre-warm code added to `smoke-trace-flow.sh` during the failed cold-start
debugging is reverted (no longer needed; with `min: 1` the gateway is warm).
Cluster-verify pending: with the updated HTTPScaledObject applied, the
walkthrough's trace act runs to completion on the first attempt. Follow-up
options if scale-to-zero on the gateway is ever wanted: upgrade the HTTP
add-on to 0.14 and configure `readinessTimeout`, or trim gateway imports so
uvicorn starts within 0.12.2's hardcoded 15-second ceiling.

## CAP-046 — Phase F: upgrade KEDA HTTP add-on 0.12.2 → 0.14.0; HTTPScaledObject → InterceptorRoute

**Status:** **superseded by CAP-047** — the upgrade was attempted on the
`phase-f-keda-http-014` branch and discovered an upstream interceptor regression
that affects KEDA's own Getting Started tutorial. Branch discarded; cluster
remains on 0.12.2. See CAP-047 for the outcome, the upstream issue filing
(kedacore/http-add-on#1668), and the resulting walkthrough adjustment. This
entry kept as historical record of the decision and the migration design.

**Context.** The walkthrough's trace act (CAP-043) hit a 502 wall that nine+
rounds of in-place debugging could not resolve cleanly. The minimum we knew
for certain (see the iteration log for the full sequence):

  * The gateway is healthy: bypass tests (direct POST to its Service while
    scaled to one replica) returned 200 with the correct GraphQL response.
  * The interceptor returned 502 with `X-Keda-Http-Cold-Start: true` on
    actually-cold requests, and `X-Keda-Http-Cold-Start: false` on requests
    against a known-warm gateway — both reproducible across all three
    interceptor pods individually.
  * 0.12.2's interceptor exposed neither a configurable cold-start budget
    (the `DialRetryTimeout` field shown in its startup config has no
    corresponding env var) nor request-level diagnostic logging
    (`KEDA_HTTP_INTERCEPTOR_LOG_REQUESTS=true` was not honored).
  * `replicas.min: 1` on the HTTPScaledObject (CAP-045) did not resolve the
    warm-gateway 502, suggesting a second bug in 0.12.2's forwarding path on
    top of the cold-start ceiling.

The 0.14 release explicitly addresses the cold-start configurability gap (the
`readiness` timeout is now a per-route configurable field on the new
`InterceptorRoute` CRD), restructures the resource model along cleaner
separation-of-concerns lines, and is a maintained version — 0.12.2 is two
minor releases behind and unlikely to receive backport fixes.

**Decision.** Upgrade the chart to 0.14.0 and migrate `graphql-gateway`'s
routing from the deprecated `HTTPScaledObject` (v1alpha1) to two resources:
`InterceptorRoute` (v1beta1) for routing/cold-start/timeouts, and a plain
KEDA `ScaledObject` for replicas/cooldown. Done on a `phase-f-keda-http-014`
branch — if the upgrade goes poorly we merge nothing and the cluster rolls
back with `helm rollback keda-add-ons-http`. Done in one branch (not several
commits on `main`) so any inadvertent breakage of the four working acts
(scale, canary, lineage, topology) is contained.

**What changes in source.**

  * `scripts/setup-keda.sh` — `KEDA_HTTP_VERSION` 0.12.2 → 0.14.0.
  * `keda/gateway-httpscaledobject.yaml` — DELETED.
  * `keda/gateway-interceptorroute.yaml` — NEW. Routing + cold-start config:
    `target.service`, single `rules[]` entry with hosts, `scalingMetric`
    (preserved from prior), `timeouts.readiness: 60s` (the fix), and
    `timeouts.responseHeader: 30s`.
  * `keda/gateway-scaledobject.yaml` — NEW. `scaleTargetRef` to the Deployment,
    `minReplicaCount: 0` (scale-to-zero restored — CAP-045's `min: 1`
    workaround is no longer needed since the 60s readiness budget absorbs
    uvicorn cold start), `maxReplicaCount: 3`, `cooldownPeriod: 30`, trigger
    `external-push` pointing at `interceptorRoute: "graphql-gateway"`.
  * `scripts/bootstrap-capstone.sh` — applies the two new manifests instead
    of the one old.
  * `demos/smoke-keda-http.sh` and `demos/smoke-trace-flow.sh` — comment and
    fail-message updates; `smoke-trace-flow.sh` curl timeout bumped from 30s
    to 90s to give the 60s readiness budget room.

**Narrative implications** (deck/tutorial copy that benefits from this).
The "elastic data products" framing is now coherent without the asterisk
CAP-045 introduced: BOTH halves scale to zero — the event consumer
(notification-service) on Kafka lag, and the read gateway on HTTP idle —
calibrated to their workload's character. The `readiness` timeout is the
explicit, configurable cold-start budget per route; the deck and §17
observability/elasticity chapters can describe this honestly rather than
hand-waving past it.

**Things explicitly NOT changing in this phase.**

  * The Istio canary (order-service v1/v2 VirtualService/DestinationRule) —
    unaffected by HTTP add-on version.
  * The Kafka consumer-lag scaler (`keda/notification-scaledobject.yaml`) —
    plain KEDA ScaledObject, unaffected.
  * Kiali / observability stack / OpenMetadata / Istio control plane —
    unaffected.

**Verification plan.** On the branch, after `helm upgrade`: confirm the new
CRDs `httpscaledobjects.http.keda.sh` (still present, deprecated) and
`interceptorroutes.http.keda.sh` (new) exist; confirm the interceptor pods
report 0.14.0; apply the two new manifests; confirm
`kubectl get interceptorroute,scaledobject -n capstone` shows both Ready;
run `./demos/walkthrough.sh --only trace --no-preflight` — must pass first
try; then `./demos/walkthrough.sh --skip trace --no-preflight` — the four
previously-verified acts must still pass. If both groups pass, merge the
branch into main and promote CAP-046's reconciliation row to `verified`. If
either fails: `helm rollback keda-add-ons-http`, abandon the branch, and the
trace act stays a known issue (CAP-045's `min: 1` workaround retained).

**Rejected alternatives.** Stay on 0.12.2 and bypass the cold-start race with
`min: 1` (CAP-045): partially worked but didn't fix the warm-gateway 502s, and
leaves us on an unmaintained add-on version. Trim gateway imports to fit
under 0.12.2's hardcoded 15s ceiling: real research, multi-iteration, doesn't
address that 0.12.2 will keep accumulating bugs. Replace the interceptor with
an Ingress controller: scope creep, abandons the "elastic synchronous gateway"
demo. The upgrade is the right call.

## CAP-047 — Phase F deferred: KEDA HTTP 0.14.0 has an upstream Go panic; trace demo bypasses the interceptor

**Status:** decided, shipped on `main`; documented; cluster on KEDA HTTP 0.12.2.
The upstream fix tracking issue is `kedacore/http-add-on#1668`; this CAP is
revisited when that issue closes against a tagged release ≥ 0.14.1 (binary,
not chart).

**Context.** CAP-046 attempted to migrate the gateway from `HTTPScaledObject`
(v1alpha1) to `InterceptorRoute` (v1beta1) by upgrading the chart from
`0.12.2` to `0.14.1` (app version `0.14.0`). On the `phase-f-keda-http-014`
branch with the upgrade applied, the trace act still failed — but the failure
mode was a clean Go panic in the interceptor's POST forwarding path
(`invalid concurrent Body.Read call` from `net/http`), not the cold-start
race CAP-046 was designed to fix. Reproduced against KEDA's own Getting
Started sample (`traefik/whoami`) with the maintainers' own manifests, copied
verbatim — both `POST` (clean panic with stack trace) and `GET` (silent hang,
no log, no response) failed to forward.

**Diagnosis (for the audit trail).**

  * Panic is in Go's `net/http`, raised when the server's full-duplex code
    path reads a request body that is concurrently being read by something
    else — golang/go#68560.
  * The full-duplex code path was introduced upstream in
    `kedacore/http-add-on#1386` ("Support full-duplex http1.1"), which
    shipped in v0.12.0 and is in every version since, including v0.14.0.
  * v0.11.1 (the last release *before* PR #1386 landed) does NOT panic on
    the same workload — confirmed by rolling the cluster back and re-running.
    However, v0.11.1's interceptor failed a different way (Service-dial
    timeouts) for reasons unrelated to KEDA HTTP version (see the unrelated
    networking note in the iteration log), so v0.11.1 is not a viable
    fallback for our specific cluster either.
  * Bypass tests confirm the workload is fine: a port-forward directly to
    the `graphql-gateway` Service (no interceptor in the path) returns
    `200 OK` with the correct GraphQL response. The bug is in the
    interceptor's request-body handling, not anything about the gateway.

**Decision.**

1. **Defer the upgrade.** Discard the `phase-f-keda-http-014` branch.
   The cluster stays on chart `0.12.2`, with `gateway-httpscaledobject.yaml`
   from `main` (per CAP-045: `replicas.min: 1`). No source code on `main`
   changes for the chart version or the manifests — the branch was the place
   the upgrade lived, and it is not merged.

2. **File the upstream issue.** Bug filed at
   `https://github.com/kedacore/http-add-on/issues/1668`. The report
   reproduces against KEDA's own Getting Started tutorial (their sample app,
   their exact manifests, copied from `keda.sh/http-add-on/0.14/getting-started/`),
   demonstrating that v0.14.0's tutorial does not actually work end-to-end.
   That framing — "your tutorial is broken on your latest release" — is the
   strongest possible argument for a fast upstream fix, regardless of our
   specific use case.

3. **Adjust the trace demo to bypass the interceptor.** The walkthrough's
   trace act now port-forwards directly to the `graphql-gateway` Service
   (`kubectl port-forward -n capstone svc/graphql-gateway 8080:80`) and
   sends the GraphQL query there. The trace itself — HTTP server span at
   the gateway, REST client span to order-service, gRPC client span to
   inventory-service, all stitched in Tempo — is unchanged. Only the
   *entry path* differs from the production-shaped story (no KEDA HTTP
   interceptor in the path). The act demonstrates the same data-mesh
   observability story (the three signals, spans across products) while
   the upstream interceptor bug is resolved.

4. **Keep the slide story intact.** Slide 33 ("Elastic reads: the KEDA
   HTTP add-on") and slide 49 ("What you can see it do") in the deck
   are unchanged conceptually. Speaker notes on both slides document
   the current demo state and link to the upstream issue, so a future
   presenter knows what to skip and why. The visual story of HTTP scaling
   the read gateway is still the right architectural picture — only the
   live demo of HTTP-add-on scale-from-zero is paused.

**What changes in source (this iteration).**

  * `demos/walkthrough.sh` — Act 1 (trace) replaced. Now: open a
    background `kubectl port-forward` to `svc/graphql-gateway`, wait for
    the local endpoint to bind, send one GraphQL POST, surface the HTTP
    status and any trace-id headers, tear down the port-forward. The
    cleanup trap is extended to handle the new `TRACE_PF` pid (in
    addition to the existing `KIALI_PF`). Preflight gains two checks
    that the trace act needs: `graphql-gateway` Deployment available
    and `graphql-gateway` Service exists. Header comment updated.
  * `_plans/capstone-decisions.md` — CAP-046 status updated to
    "superseded by CAP-047"; CAP-047 (this entry) added.
  * `_plans/reconciliation-plan.md` — the prior CAP-046 row marked
    "superseded by CAP-047"; new CAP-047 rows added (one for the
    walkthrough trace-bypass change, one for the deferred upgrade).
  * `presentation/data-mesh-openshift/Data_Mesh_on_OpenShift.pptx` —
    speaker notes appended on slides 33 and 49 documenting the demo
    status and the upstream issue. Slide bodies and diagrams unchanged.

**Pickup criteria for re-attempting the upgrade.** The upstream issue
`kedacore/http-add-on#1668` closes with a fix released in a tagged version
of the add-on (binary, not only the chart). At that point CAP-046's
migration plan is re-runnable on a fresh branch: bump the chart, apply the
two new manifests, retest the trace act through the interceptor, and if
it passes, merge and supersede CAP-047 in the same step. The work product
from the CAP-046 attempt (the migration design, the manifest shapes,
the discovery of the per-route `timeouts.readiness` field) all remains
valid and is recorded in CAP-046's body for that future revisit.

**Rejected alternatives.**

  * Pin to v0.11.1 in the tutorial. The interceptor doesn't panic there,
    but it predates the InterceptorRoute model the rest of the upstream
    docs and ecosystem are moving toward, and v0.11.1 had a separate
    Service-routing issue in our cluster that we never resolved. Pinning
    backward to an older minor version is a worse story than a temporary
    bypass.
  * Drop the trace act from the walkthrough entirely. Loses the strongest
    "see it run" payoff on slide 49 — and the trace story is independent
    of the HTTP add-on. The bypass keeps the trace's value with one less
    component in the path.
  * Drop the HTTP add-on from the deck. The architectural argument
    (HTTP scaling for the gateway is the right tool for a read-volume
    workload, distinct from Kafka-lag scaling for an event consumer) is
    correct regardless of the temporary bug; removing the slide would
    misrepresent the design.

**Consequences.**

  * Walkthrough remains five acts: trace (bypassed entry), scale, canary,
    lineage, topology. The trace act's narrative now includes the
    one-liner "we port-forward to the gateway directly while the
    upstream HTTP-add-on fix is pending."
  * The "elastic data products" story in the deck stays split honestly
    by workload character (CAP-045's framing): event consumers scale to
    zero on Kafka lag right now; the read gateway's scale-from-zero on
    HTTP traffic is documented and visualized but its live demo is
    paused. Both pieces are still in the deck.
  * `keda/gateway-httpscaledobject.yaml` on `main` is unchanged — it
    still carries `replicas.min: 1` from CAP-045. That partial
    workaround is still useful for the cluster: it ensures the gateway
    is always warm during the walkthrough, even though we're not relying
    on the HTTP add-on to scale it from zero in the demo.
