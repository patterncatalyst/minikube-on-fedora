---
title: "Capstone: a data mesh on minikube"
order: 17
description: A working data-mesh implementation that exercises everything from §1–§12 in one coherent system. Five Python/FastAPI services exposing REST, gRPC, GraphQL, and Kafka, deployed via helm to a dedicated minikube profile, with full observability, metadata cataloging, and orchestration.
duration: multi-session
---

This is the section where everything converges. The earlier
sections introduced the building blocks individually — minikube
profiles, kubectl, helm, Istio, KEDA, Strimzi. §17 puts them
together into a single coherent system that demonstrates *when,
how, and why* each one earns its place. It's the longest section
in the tutorial by far, spanning multiple iterations, and the
section that justifies the time invested in §1–§12.

The system we'll build is a **data mesh**: a five-service domain
modeling order-placement-through-shipment, with each service
owning its data, its API surface, and its operational lifecycle.
The services communicate through a deliberate mix of REST, gRPC,
GraphQL, and Kafka — not because we couldn't pick one protocol,
but because each protocol's strengths show up in different
contexts, and the capstone is the place to make those contexts
visible.

## What is a data mesh?

The term **data mesh** was coined by Zhamak Dehghani in 2019 and
formalized in *Data Mesh: Delivering Data-Driven Value at Scale*
(O'Reilly, 2022). It's a response to the recurring failure of
centralized data platforms — monolithic data lakes, monolithic
warehouses, monolithic ETL pipelines — to scale with the
complexity of the organizations using them.

The shift is from "centralize the data, then carve out access"
to **decentralize ownership: let each domain own its data as a
product**, with the platform providing the substrate for those
products to publish, discover, and govern themselves. The
analogy that lands hardest is microservices: just as a
monolithic application gets refactored into bounded contexts
owned by domain teams, a monolithic data platform gets refactored
into bounded data products owned by domain teams.

## The four principles

Dehghani's data mesh rests on four interlocking principles, each
of which shows up explicitly in our implementation:

1. **Domain ownership.** Data is owned, end-to-end, by the
   domain team that produces it. There's no central data team
   that "owns the data warehouse." In our capstone, each of the
   five services owns its data: schema, lifecycle, evolution
2. **Data as a product.** A data product has the same
   discoverability, addressability, trustworthiness,
   self-description, and SLA expectations as any other software
   product. In our capstone, each service publishes its API
   contracts to Apicurio (the registry) and its metadata to
   OpenMetadata (the catalog)
3. **Self-serve data platform.** Domain teams shouldn't have to
   build Kafka, build observability, build a registry, build a
   catalog. The platform team provides these as infrastructure
   that all domains consume. In our capstone, Kafka (via
   Strimzi), the observability stack (Prometheus + Grafana +
   Tempo + OTEL Collector), Apicurio, OpenMetadata, and KEDA
   are all platform infrastructure shared by the five services
4. **Federated computational governance.** Standards are
   enforced *computationally* — by the platform — not by
   meetings and policy documents. Examples in our capstone:
   Istio enforces mTLS between meshed services automatically;
   Apicurio rejects schema-incompatible changes at publish
   time; OpenMetadata enforces required-field policies on
   data products

A data mesh isn't a product, a tool, or a vendor offering.
It's an organizational and architectural pattern. The tools
we use here — Kafka, Apicurio, OpenMetadata, Istio — are
*expressions* of the pattern, not the pattern itself.

## Why this maps to Kubernetes

Kubernetes is unusually well-suited to hosting a data mesh
because the four principles map cleanly onto primitives the
reader is already familiar with from §1–§12:

- **Domain ownership** maps to **Namespaces** and to the
  team-and-RBAC story Kubernetes was designed around. Each
  domain runs in its own namespace, with its own ServiceAccounts,
  Roles, and resource quotas
- **Data as a product** maps to **Services, Deployments, and
  CRDs**. A data product *is* a deployable artifact with a
  service contract; that's exactly what a Service + Deployment
  represents, and CRDs let you extend the type system with
  domain-specific concepts (e.g. `DataProduct`, `Topic`,
  `SchemaRegistration`)
- **Self-serve data platform** maps to **shared cluster
  infrastructure**: operators (Strimzi for Kafka, KEDA for
  scaling, Istio for the mesh), platform addons (metrics-server,
  ingress), and shared observability stacks
- **Federated computational governance** maps to **admission
  controllers, OPA/Gatekeeper policies, Istio
  AuthorizationPolicies, and CRD validation**. The platform
  enforces rules at the boundary, not after the fact

You can deploy a data mesh without Kubernetes (or run on
Kubernetes without it being a mesh). But the alignment is
strong enough that "implement a data mesh on Kubernetes" is a
natural design exercise — and the one we'll undertake here.

## Architecture overview

The system has three horizontal tiers: **external clients**
(top), the **service mesh** running our domain services
(middle), and the **self-serve platform** providing shared
infrastructure (bottom).

![Capstone architecture — data mesh on minikube]({{ "/assets/diagrams/17-capstone-data-mesh.svg" | relative_url }})

The diagram shows the protocol decisions at a glance: REST
crosses the ingress (external clients ↔ services), gRPC
flows synchronously between services inside the mesh, GraphQL
federates across services through a dedicated gateway, and
Kafka carries events asynchronously from producers to
consumers. The OTEL collector receives traces and metrics
from every service via OTLP and fans them out to Prometheus,
Tempo, and Grafana.

We'll cover each tier in detail as the implementation
iterations land. For now, the diagram is the map you'll
return to as we work through the parts.

## The five services

The domain is order-placement-through-fulfillment, modeled
deliberately small (5 services) so the architecture stays
legible. Each service is a **bounded context** owning its
data and its API contract.

| Service | Domain | Owns | Notable protocols |
|---|---|---|---|
| order-service | Order lifecycle | `orders` table, order state machine | REST (external clients), gRPC (calls inventory/payment/shipping), GraphQL (queries), Kafka (publishes `orders.placed`) |
| inventory-service | Stock levels | `inventory` table | gRPC server (called by order), GraphQL (queries), Kafka (publishes `inventory.updated`, consumes `orders.placed`) |
| payment-service | Payments | `payments` table | gRPC server (called by order), GraphQL (queries), Kafka (publishes `payments.processed`, consumes `orders.placed`) |
| shipping-service | Shipments | `shipments` table | gRPC server (called by order), GraphQL (queries), Kafka (publishes `shipments.dispatched`, consumes `payments.processed`) |
| notification-service | Notifications | `notifications` table | Kafka consumer only — subscribes to `orders.placed`, `payments.processed`, `shipments.dispatched` and emits notifications |

Note the deliberate variation: not every service exposes every
protocol. By design, each service
exposes the protocols that *make sense for its role*, not a
uniform multi-protocol surface. notification-service is
Kafka-only because its job is to react to events, not to be
called synchronously.

## Platform components

The self-serve platform is the bottom tier — infrastructure that
all five services consume but none of them own. Most of these
the reader has already met in §11 / §12; the new ones are
flagged.

| Component | Purpose | First introduced |
|---|---|---|
| Strimzi + Kafka | Event backbone; KEDA's consumer-lag scaling target | §12 |
| KEDA + HTTP add-on | Scale graphql-gateway on HTTP load; scale Kafka consumers on lag | §12 |
| Istio + Kiali | mTLS, traffic shifting, fault injection, mesh visualization | §11 |
| Prometheus + Grafana + Tempo + OTEL Collector | Per-service metrics + distributed traces + dashboards | **new in §17** |
| Apicurio Registry | OpenAPI (REST), proto descriptors (gRPC), Avro/JSON schemas (Kafka) | **new in §17** |
| OpenMetadata | Catalog of data products with their schemas, lineage, ownership | **new in §17** |
| Prefect (OSS) | Orchestration for scheduled cross-service flows (metadata sync, reconciliation) | **new in §17** |
| PostgreSQL | One cluster with one schema per service (per-domain data ownership) | **new in §17** |

Per `CONTRIBUTING.md`'s container-image policy, we use UBI 9
base images for our five services. The platform operators
(Strimzi, KEDA, Istio control plane, Apicurio operator,
OpenMetadata operator) ship as upstream images from their
vendors — documented exceptions per the project's UBI policy.

## Prerequisites for §17

§17 has the heaviest resource footprint in the tutorial. Before
starting, confirm:

- **Fedora 44** with the standard tutorial prereqs from §1
  (Podman 5.x, kubectl, helm, minikube)
- **At least 64 GB RAM** (the capstone profile is sized at 24
  GB, leaving headroom for the host, browser, IDE, and any
  other minikube profiles you're keeping idle)
- **At least 1 TB disk** (the image cache for the full stack
  consumes ~30-50 GB; persistent volumes for Kafka, Postgres,
  and OpenMetadata add ~20 GB more under sustained use)
- **The §1 inotify-limits tweak applied** (`fs.inotify.max_user_instances = 512`)
- **Other minikube profiles stopped** before running the
  capstone — the `minikube`, `istio`, and any §12 profiles
  should be `minikube stop -p <name>` to free their RAM
  allocation
- **Poetry, with each service's dev environment installed.** The
  services use Poetry (CAP-001). On the host you need Poetry plus
  a per-service `poetry install`, which creates the dev venv used
  for local tests and for gRPC codegen. Install the dev env for
  each service you're working with, e.g.:

  ```bash
  cd examples/17-capstone/services/inventory-service
  poetry install        # creates the venv, installs deps + dev deps
  ```

  Run this before `scripts/gen-protos.sh` — its Poetry-venv
  fallback needs the venv to exist.
- **Python 3.12 for the dev venv, to match the containers.** The
  service images run UBI 9's `python-312` (Python **3.12** — the
  newest Python with a supported UBI 9 image). Fedora 44, however,
  defaults to Python **3.14**, so a bare `poetry install` builds
  the dev venv with 3.14 — which drifts from the 3.12 runtime and
  can hit wheel-availability gaps on a Python that new (notably
  `grpcio`). Point the dev venv at 3.12 for parity:

  ```bash
  sudo dnf install python3.12          # Fedora ships non-default versions as separate packages
  cd examples/17-capstone/services/inventory-service
  poetry env use python3.12            # pin THIS service's venv to 3.12
  poetry lock && poetry install
  ```

  Repeat `poetry env use python3.12 && poetry lock && poetry
  install` for each service. This keeps your local environment on
  the same Python the container runs (CAP-014).
- **A protobuf/gRPC code generator**, needed to regenerate the
  gRPC stubs (whenever the protos change) that
  `scripts/gen-protos.sh` commits into each service. The script
  tries several generators in order, so on a stock Fedora 44 you
  can use whichever is easiest — no global install required:
  - **`buf`** (preferred — also lints and checks breaking
    changes): see <https://buf.build/docs/installation>; or
  - **the service's Poetry venv** — `grpcio-tools` is already a
    dev dependency, so running `poetry install` in
    `services/inventory-service` makes the generator available
    with nothing else to install; or
  - **a throwaway venv** (Fedora's system Python is
    externally-managed, so install into a venv, not system-wide):
    `python3 -m venv /tmp/protogen && /tmp/protogen/bin/pip
    install grpcio-tools && source /tmp/protogen/bin/activate`,
    then run the script; or
  - **dnf + pipx**: `sudo dnf install pipx && pipx install
    grpcio-tools`.

  This tool is only needed on the machine that *regenerates*
  stubs; the committed stubs mean the service images build
  without it.

The §17 example pre-flight script
(`examples/17-capstone/scripts/preflight.sh`, shipping in a
later iteration) checks each of these before the deploy starts.

## Setting up the capstone profile

§17 uses a dedicated minikube profile named `capstone`, sized
substantially larger than the `minikube`/`istio` profiles from
earlier sections:

```bash
cd examples/17-capstone
./scripts/setup-capstone-profile.sh
```

The script starts (or replaces) a `capstone` profile with:

- **24 GB RAM** / **16 CPUs**
- **podman driver** (rootless, consistent with §3)
- **containerd runtime**
- **disk: 80 GB** for the kubelet's data root plus PVs

After it returns:

```bash
kubectl config use-context capstone
kubectl get nodes
```

You should see one node, status `Ready`. From here, subsequent
iterations install the platform stack (Strimzi, KEDA, Istio,
observability, Apicurio, OpenMetadata, Prefect, Postgres)
followed by the five services.

To stop the capstone profile when you're done (or to free RAM
for other work):

```bash
./scripts/teardown.sh
```

This stops the profile but doesn't delete it — restart with
`minikube start -p capstone`. To delete entirely, pass
`--remove-profile` to `teardown.sh`.

## Implementation: order-service (the template)

We start the build with a single service taken end-to-end —
a *walking skeleton* (CAP-006). The point is to prove the
entire spine works before widening to the other services:
image build → minikube image cache → helm deploy →
operator-managed Postgres → service connects → REST works →
data round-trips. Once that's verified on real hardware, the
remaining four services are mechanical repetition of the same
pattern.

order-service is a Python/FastAPI application that owns the
`orders` schema in the shared capstone Postgres (CAP-003).
As the walking skeleton, it began by speaking only REST; gRPC, GraphQL, and Kafka are
layered on in later iterations.

### Dependencies with Poetry

The service uses **Poetry** (CAP-001) for dependency
management. `pyproject.toml` declares dependencies; `poetry
lock` produces a `poetry.lock` for reproducible builds. The
Containerfile exports the locked dependencies to a pip
requirements list and installs them into an isolated
virtualenv — keeping the runtime image free of Poetry itself.

### A UBI 9 multi-stage image

Per the project's container-image policy, order-service builds
on **UBI 9 Python 3.12** (CAP-005). The Containerfile is
multi-stage: the builder has Poetry and resolves dependencies;
the runtime stage copies only the venv and the application
code, runs as the non-root `1001:0` user, and serves with
uvicorn. (We use the same UBI 9 Python base for both stages
for build reliability; a slimmer runtime base is a deferred
optimization noted in CAP-005.)

### Known friction: getting images to the kubelet on this driver

A candid heads-up, because this is the one part of the capstone that fights
back. The tutorial deliberately uses the **rootless-podman driver with the
containerd runtime** (§3) — it's the most realistic local mirror of how
Kubernetes runs in production, and it's the right pedagogical choice. But
that combination has a genuinely awkward sharp edge: **getting a
locally-built image to the kubelet is not straightforward.**

The intuitive approaches don't work reliably here:

- `minikube image build` may exit successfully without the image actually
  landing in the profile's containerd store — the pod then fails with
  `ErrImagePull` as the kubelet falls back to Docker Hub.
- `minikube image load <name>` can report "image not found" even for an
  image that `podman images` clearly shows, because the lookup goes through
  the rootless podman socket in a way that doesn't resolve.

The reliable answer — and the one this tutorial standardizes on — is
**minikube's built-in registry addon**. You build on the host with podman,
push to the registry, and your deployments pull from it like any normal
image. `setup-capstone-profile.sh` enables the registry; `build-image.sh`
handles build-tag-push; the charts pull from the in-cluster address.

> **The one detail that trips everyone up: the registry has two addresses.**
> With the podman driver, the host-side port is *not* 5000 — minikube
> assigns one (you'll see something like `127.0.0.1:41685`) and will tell
> you so when you enable the addon. But *inside* the cluster, the kubelet
> reaches the same registry at `localhost:5000`. So:
>
> - **You push** (from the host) to `127.0.0.1:<assigned-port>`
> - **The cluster pulls** from `localhost:5000`
>
> `build-image.sh` discovers the host port automatically and pushes there;
> the charts set `image.repository: localhost:5000/<service>`. If you ever
> push by hand, run `podman port capstone | grep 5000/tcp` to find the host
> port.

> **One environment variable makes or breaks all of this:**
> `MINIKUBE_ROOTLESS=true`. If it isn't set in your shell, minikube routes
> host operations (status, ssh, image and registry access) through
> `sudo podman`, which cannot see your rootless container — producing a
> baffling spread of failures that look like a broken cluster but aren't.
> The capstone scripts both persist it (`minikube config set rootless true`)
> and export it at the top of every script. If you run minikube commands by
> hand, `export MINIKUBE_ROOTLESS=true` first.

None of this is unique to the capstone — it's inherent to the rootless
driver — but the capstone is where it bites, because it's the first section
that builds and deploys your *own* images at scale (six of them across the
five services and the gateway). Get the registry workflow right once here,
and every service afterward is the same three commands.

### Postgres via an operator — and why that's cluster-wide

The shared Postgres is managed by the **CloudNativePG
operator** (CAP-002), installed the same way §11 and §12
install their operators: a one-time setup script, separate
from the application helm release.

> **Installing an operator is a cluster-wide act.** This is
> worth pausing on, because it's a different *kind* of change
> from everything we've deployed so far. When you
> `kubectl apply` a Deployment, you add a workload to one
> namespace. When you install an operator, you do two
> cluster-scoped things:
>
> 1. **You register CRDs.** Custom Resource Definitions are
>    *always* cluster-scoped — once `clusters.postgresql.cnpg.io`
>    is registered, the `Cluster` kind exists in *every*
>    namespace on the cluster, not just the one you installed
>    from. You've extended the cluster's type system.
> 2. **You run a controller that watches cluster-wide.** The
>    CloudNativePG controller (in the `cnpg-system` namespace)
>    watches for `Cluster` CRs across all namespaces and
>    reconciles them. It's a control loop spanning the whole
>    cluster.
>
> Treat operator installation with the care you'd give any
> cluster-scoped change — it affects every tenant of the
> cluster, not just your namespace. This is exactly why,
> in a real multi-team setup, operator installation is
> usually a platform-team responsibility, not something
> individual application teams do ad hoc. It's also the
> *federated computational governance* principle in action:
> the platform team installs and governs the operators; the
> domain teams consume the CRs.

Install the operator once:

```bash
cd examples/17-capstone
./scripts/setup-postgres-operator.sh
```

The script registers the CRDs, runs the controller, and
prints exactly what cluster-wide state it changed.

### The Cluster CR

With the operator running, the capstone umbrella chart ships a
`Cluster` custom resource (in `charts/capstone/charts/postgres/`).
The operator sees it and provisions the actual Postgres pods,
services, and credential secrets. The CR is small and
declarative:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: capstone-postgres
spec:
  instances: 1
  bootstrap:
    initdb:
      database: capstone
      owner: capstone_app
  storage:
    size: 5Gi
```

CloudNativePG generates a Secret named `capstone-postgres-app`
holding the application user's credentials. order-service reads
its Postgres connection from this secret — we never hardcode a
password. This is the *Predictable Demands* and *Configuration
Resource* patterns from *Kubernetes Patterns* (Ibryam & Huss):
the service declares exactly what it needs (a database
connection) and sources it from a Kubernetes-native config
object.

### The helm subchart

order-service's helm subchart
(`charts/capstone/charts/order-service/`) is deliberately
minimal: a Deployment and a Service. The Deployment
wires the Postgres connection from the CNPG secret via
`secretKeyRef`, declares resource requests and limits
(*Predictable Demands*), and defines liveness (`/health`) and
readiness (`/healthz`) probes (*Health Probe* pattern). The
readiness probe checks Postgres connectivity, so the pod isn't
marked Ready until it can actually serve data.

### Verifying the slice

The smoke test (`demos/smoke-order.sh`) is the verification:

```bash
cd examples/17-capstone
./demos/smoke-order.sh
```

It builds the image into the capstone profile, deploys the
Postgres Cluster CR and waits for the operator to provision it,
deploys order-service, then exercises the REST surface — POST
an order, GET it back by id, confirm it's in the list — and
finally queries Postgres *directly* to confirm the row actually
persisted in the `orders.orders` table. A `trap` cleans up on
exit. The whole run ends with `✓ SUCCESS` or fails loudly at
the first broken assertion.

That single passing run proves the entire spine. The other
four services follow as parallel repetitions of
this template; later iterations layer on gRPC, GraphQL, Kafka,
KEDA scaling, the observability stack, OpenMetadata, and
Prefect.

## The read layer: GraphQL federation (gateway vs subgraphs)

REST and gRPC each answer questions about *one* service's data. The moment a
client needs a single answer that spans services — "give me this order, and
the current stock for its SKU" — it has to make two calls and stitch the
results itself. GraphQL federation moves that stitching to the server: the
client sends one query, and a gateway assembles the response from multiple
backends, returning exactly the fields the query asked for.

The capstone ships a **`graphql-gateway`** service that does this by
*orchestration*: it's a stateless Strawberry GraphQL server whose resolvers
call the existing services — `order(id)` fetches from order-service over
REST, and the nested `Order.stock` field fetches from inventory-service over
gRPC. One query, two services, two protocols, one stitched response. This is
deliberately the place where all three protocols cooperate in view of each
other, which makes the "right protocol for the interaction" idea concrete:
REST at the edge, gRPC for the tight internal call, GraphQL composing reads.

This is **not** how you would federate GraphQL at production scale, and the
difference is worth understanding:

- **What we do here — gateway orchestration.** A single gateway owns the
  unified schema and calls services under the hood. It's simple, it reuses
  interfaces the services already expose, and it's perfect for demonstrating
  the value. But the schema lives in one place (no domain owns its slice),
  and that one gateway is a scaling and deployment bottleneck.

- **True subgraph federation (the production pattern).** Each service
  exposes its *own* GraphQL subgraph — order-service publishes the `Order`
  type, inventory-service publishes a `Stock` type with an entity key — and
  a federation gateway composes these subgraphs into a single *supergraph*,
  planning each query across the subgraphs that can resolve its fields. You
  reach for this when domain teams must own and evolve their part of the
  graph independently, when you want the supergraph composed and
  breaking-change-checked in CI, and when entity resolution across subgraphs
  and per-subgraph scaling actually matter. It applies the same data-mesh
  principle the capstone teaches — domain ownership — to the graph itself,
  trading the single-gateway bottleneck for real domain autonomy at the cost
  of more moving parts (a subgraph server per service, a composition step,
  query planning).

For a tutorial whose subject is services on Kubernetes, orchestration shows
the idea with one new service and no changes to the existing five. In a real
data mesh, you'd graduate to subgraph federation so each data product owns
its slice of the graph end to end. (See CAP-016 in the decision log.)

## The async spine: events with Kafka

Everything so far has been *synchronous* — a client (or the gateway) calls a
service and waits for the answer. But a data mesh also needs the asynchronous
shape: a service announces that something happened, and other services react
in their own time, without the announcer knowing or waiting for them. That's
what events over Kafka provide, and it's the backbone of loose coupling
between data products.

The capstone establishes this with the smallest real flow. When
order-service persists an order, it publishes an **`order.placed`** event to
a Kafka topic. **notification-service** — which until now was a health-only
skeleton, because it's a *consumer-only* data product by design — consumes
those events. order-service doesn't know notification-service exists; it just
announces the fact. New consumers can be added later (a fulfilment service, an
analytics sink) with zero changes to order-service. That decoupling is the
whole point.

Kafka runs via the **Strimzi operator** (the same operator pattern used for
Postgres and for Istio/KEDA earlier). For local development the cluster is
deliberately minimal: a single **KRaft** node playing both controller and
broker roles, ephemeral storage, and replication factor 1. The topic is
declared as a `KafkaTopic` custom resource and created by Strimzi's Topic
Operator — declarative, like everything else. The Python services use
**aiokafka**, the asyncio-native client, so the producer and consumer live in
the same event loop as the FastAPI app and are started and stopped by its
lifespan (the Managed Lifecycle pattern).

Three honest simplifications, each of which has a production-grade answer
worth knowing:

- **The dual-write problem.** order-service commits the order to Postgres and
  *then* publishes to Kafka — two separate systems. If the process crashes
  between the commit and the publish, the order exists but the event was
  never sent. The robust fix is the **transactional outbox**: write the event
  into an outbox table inside the *same* database transaction as the order,
  then a separate relay reads the outbox and publishes to Kafka, so the two
  can't diverge. The capstone publishes after commit and logs failures,
  noting the outbox as the production pattern.
- **At-least-once delivery.** Kafka may deliver the same message more than
  once (after a consumer rebalance, or a crash before the offset is
  committed). Consumers must therefore be **idempotent** — processing the
  same event twice must be harmless. notification-service keys its store by
  order id, so a redelivery overwrites rather than duplicates.
- **Durability and availability.** A single ephemeral node with replication
  factor 1 loses everything if it restarts and tolerates no broker failure —
  fine for a laptop, unacceptable in production, where you'd run separate
  broker and controller pools, persistent volumes, replication factor 3, and
  `min.insync.replicas` 2.

The consumer now **persists** each event to its own `notifications` table and
exposes the rows at `/received`. The event itself is a **registered Avro
contract** — order-service registers the `order.placed` schema with Apicurio
and serializes against it, and notification-service fetches that schema by id
to decode (the next section explains the registry in full). And the table is
created and evolved by **Alembic migrations** run in a Kubernetes init
container (`alembic upgrade head`) before the app starts — which retires the
startup `create_all` for this service: the app issues no DDL, it just consumes
and persists. The payoff is durability — a notification now survives a pod
restart, which the earlier in-memory version did not.

## Schema migrations, and two kinds of temporary container

Up to now every service created its tables with SQLAlchemy's
`Base.metadata.create_all` at startup. That's fine for a walking skeleton —
it makes a table that doesn't exist — but it does nothing about a table that
*already* exists and needs to *change*. The moment a column is added or a
type changes, `create_all` silently leaves the old shape in place. Real
schema evolution needs migrations, so notification-service — the first
service with a domain table worth evolving — switches to **Alembic**.

Two wrinkles are worth calling out, because both cost people time. First, the
service uses the SQLAlchemy 2.0 **async** engine (asyncpg), and Alembic's
default generated `env.py` is sync-only — point it at an `asyncpg` URL and it
fails. The fix is the async template's bridge: build an `AsyncEngine`, then run
the migration body through `connection.run_sync(...)`, which hands the
migration a normal synchronous connection underneath. The migration functions
themselves stay ordinary sync `op.*` calls — they are *not* awaited, because
Alembic runs them inside that `run_sync` bridge. Second, this is one Postgres
database with a schema per service (the ownership boundary from earlier), so
each service keeps its own `alembic_version` table inside its own schema
(`version_table_schema`) — otherwise every service's migration history would
collide in a shared `public.alembic_version`. The schema therefore has to
exist before the version table is stamped, so `env.py` issues a
`CREATE SCHEMA IF NOT EXISTS` and commits it first.

The more interesting question is *where* the migration runs. Running it inside
the application's own startup is tempting but wrong: every replica would race
to migrate, startup and schema-change concerns would be tangled together, and
a failed migration would look like a failed app. The cloud-native answer is an
**init container** — the Init Container pattern from *Kubernetes Patterns*
(Ibryam & Huss, 2nd ed., Chapter 15), which gives initialization tasks a
lifecycle separate from the main container. notification-service's Deployment
runs a `migrate` init container — same image, same database credentials — that
executes `alembic upgrade head` to completion *before* the application
container starts. Kubernetes guarantees the app container only starts if the
init container exits zero, so the app can assume its schema is present and
issue no DDL of its own. This is exactly what lets us delete `create_all` for
this service: the table is there before the app is.

```yaml
initContainers:
  - name: migrate
    image: "{{ image }}"          # same image as the app
    workingDir: /opt/app-root/src # where alembic.ini lives
    command: ["alembic", "upgrade", "head"]
    env: # same PG_* connection the app uses
      # ...
```

That init container does its work and is gone before the app serves its first
request. Its mirror image — a temporary container you attach to a pod that's
*already running* — is the **ephemeral container**, added with
`kubectl debug`. The two bracket the main container's life: the init container
runs once, before; the ephemeral container appears on demand, during. They
solve opposite problems, and ephemeral containers solve a problem this project
deliberately created. Our runtime images are minimal by design — they carry
the application's virtualenv and nothing else, no `curl`, no `psql`, not even a
debugger. That keeps the image small and the attack surface narrow, but it
means you can't just `kubectl exec` into a running pod and poke around; the
tools aren't there. Rather than bake debug tooling into the production image,
you attach it temporarily:

```console
$ POD=$(kubectl get pod -n capstone \
    -l app.kubernetes.io/name=notification-service \
    -o jsonpath='{.items[0].metadata.name}')

# Attach a throwaway container that shares the pod's network, and hit the
# app's own endpoint from inside the pod — even though the app image has no curl:
$ kubectl debug -n capstone "$POD" -it \
    --image=registry.access.redhat.com/ubi9/ubi \
    -- curl -s http://localhost:8080/received
```

The ephemeral container joins the pod's namespaces — it shares the network, so
`localhost:8080` *is* the application container — and with `--target` it can
share the application's process namespace too, letting you inspect the running
process directly. It has no resources, no probes, and can't be restarted or
removed; it lives and dies with the debugging session and leaves the pod's real
containers untouched. (See the Kubernetes documentation on
[ephemeral containers](https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/)
and `kubectl debug`.) `demos/debug-ephemeral.sh` runs this against a live
notification-service pod so you can see it work. It's a small thing, but it
captures a real cloud-native instinct: keep the running image lean, and reach
for a temporary container — before startup for setup, or mid-flight for
debugging — when you need to do something the lean image shouldn't carry.

## Contracts, the registry, and the catalog

By now the mesh speaks four protocols — REST, gRPC, GraphQL, and Kafka
events — and each of those is, at heart, a **contract**: a promise about the
shape of the data crossing a boundary. order-service's REST API promises a
certain JSON shape; inventory's gRPC service promises the `CheckStock`
message types; the gateway promises its GraphQL schema; the `order.placed`
event promises its fields. In a data mesh, where each service is an
independent data product owned by a different team, these contracts are the
load-bearing structure. A consumer doesn't depend on a producer's code or
database — it depends on the producer's *contract*. So the contracts need a
home: somewhere they're stored, versioned, checked for compatibility as they
evolve, and discoverable by anyone (or anything) that wants to integrate.

That home is a **schema registry**, and the capstone uses **Apicurio**. The
key thing to understand about Apicurio is that it's deliberately
*multi-format*: it doesn't only hold Avro schemas for Kafka. It holds **all
four protocols' contracts, each as its native artifact type** — Avro for the
Kafka events, Protobuf for the gRPC service definitions, OpenAPI for the REST
surfaces (the document FastAPI already generates at `/openapi.json`), and
GraphQL SDL for the gateway's schema. One registry, every contract.

![Contracts, the registry, and the catalog — how the four protocols' contracts live in Apicurio and feed OpenMetadata]({{ "/assets/diagrams/17-capstone-contracts.svg" | relative_url }})

There's an important distinction in *how* those contracts are used, and it's
worth drawing because the two kinds have very different coupling:

- **Runtime serialization contracts.** For Kafka events with Avro, the
  producer and consumer actually talk to the registry at run time: the
  producer serializes the event against the registered schema (and stamps the
  bytes with a schema id), and the consumer fetches that schema by id to
  deserialize. The event literally won't encode or decode without the
  registered schema. This is online, in the hot path, load-bearing. (gRPC's
  Protobuf is similar in spirit — the message types are a hard runtime
  contract — though the stubs are compiled ahead of time rather than fetched.)
- **Discovery contracts.** For REST (OpenAPI) and GraphQL (SDL), the contract
  is *published* to the registry as the source of truth for "what's the shape
  of this service," but nothing fails at run time if the registry is absent —
  the service still serves requests. These exist to be discovered: by humans
  browsing the catalog, by CI checking for breaking changes, and — crucially
  — by the data catalog described next.

The flow diagram makes the two paths concrete: the runtime path (top) is the
Avro serialize → Kafka → deserialize round-trip that touches the registry on
both ends; the discovery path (bottom) is the offline publish-and-ingest that
populates the catalog.

![Contract flow — the runtime serialization path versus the discovery and lineage path]({{ "/assets/diagrams/17-capstone-contract-flow.svg" | relative_url }})

Sitting *on top* of the registry is the data catalog, **OpenMetadata**. Where
Apicurio answers "what is the contract for X," OpenMetadata answers "what data
products exist, who owns them, and how does data flow between them." It builds
that picture by **ingesting** from several sources: the contracts in Apicurio,
the Postgres schemas each service owns (via CloudNativePG), and the Kafka
topics (via Strimzi). From those it assembles **lineage** — the traceable
chain that order-service produces `order.placed`, which is the Avro schema
Apicurio holds, which notification-service consumes. That lineage graph is
what turns a pile of services into a navigable, governed data mesh.

This layering is also why the two arrive in that order. Apicurio is the
*contract* metadata; OpenMetadata is the *lineage and discovery* metadata
derived from it. A catalog with nothing to catalog is empty, so the registry
has to hold the contracts before the catalog has anything truthful to ingest.

A note on honesty about the current state: Apicurio now holds **all four
protocols' contracts**. The `order.placed` event has its **runtime contract** —
its Avro schema is registered, and the producer and consumer serialize and
deserialize against it. And the three **discovery contracts** are published
too: order-service's OpenAPI document, the inventory gRPC Protobuf definition,
and the gateway's GraphQL SDL (exposed at `/sdl` and pushed to the registry by
an offline publish step, not on any runtime path). What's *not* yet built is
the top layer: **OpenMetadata** isn't deployed, so there's no lineage catalog
ingesting all of this yet. That's the remaining step — the registry is now
fully populated as its feedstock, which is exactly the ordering this section
described: contracts first, catalog on top.

## The catalog as a mesh requirement, not an add-on

It's tempting to read a data catalog as monitoring or nice-to-have tooling
bolted onto a working system. In a data mesh it is neither — it's the
mechanism through which three of Dehghani's four principles are actually
fulfilled. Worth being precise about why, because it determines what the
catalog must do rather than what's merely convenient.

The second principle, **data as a product**, sets a quality bar: a data
product must be discoverable, addressable, understandable, and trustworthy.
The discoverability clause is doing real work — a product that no one can find
is, operationally, not a product. Independent teams can't depend on each
other's data by reading each other's code or databases (that's exactly the
coupling the mesh exists to break); they depend on a *published, discoverable*
description. So "data as a product" implies a place where products are
registered and browsed. That place is the catalog.

The third principle, the **self-serve data platform**, says a consumer should
be able to find, understand, and start using a data product without filing a
ticket against the owning team. Self-service is impossible without a single
surface that answers "what products exist, what shape is each one, who owns
it, how fresh is it." Again: the catalog.

The fourth principle, **federated computational governance**, is the one that
makes the catalog load-bearing rather than ornamental. Governance in a mesh is
*federated* (each domain governs its own products) but *computational* (the
rules — ownership, classification, retention, compatibility, and above all
lineage — are expressed as metadata that machines can act on, not as a wiki
page humans are asked to keep current). Lineage is the keystone: the traceable
chain showing that order-service produces `order.placed`, which is the Avro
schema Apicurio holds, which notification-service consumes and persists. With
that chain computable, you can answer the questions governance actually asks —
if this schema changes, who breaks; if this field is sensitive, where does it
flow; if this product is wrong, what's downstream — without a human
reconstructing it from tribal knowledge. That is what turns a pile of
independently-owned services into a *governed* mesh rather than a distributed
mess.

This is why the capstone treats the catalog as a required layer and builds it
on the registry rather than instead of it. The two answer different questions
and the canonical pattern layers them: Apicurio answers *what is the contract
for X* (the precise, versioned, compatibility-checked shape of each boundary);
OpenMetadata answers *what products exist, who owns them, and how does data
flow between them* (discovery, ownership, and lineage across products). The
catalog ingests *from* the contract registry — plus the Postgres schemas each
service owns and the Kafka topics they exchange — so its picture is derived
from ground truth, not hand-maintained. **OpenMetadata** is the capstone's
catalog because it's open-source, runs on Kubernetes, speaks a pull-based
ingestion model with first-class connectors for exactly our sources (Postgres,
Kafka, and schema registries), and represents lineage as a first-class,
queryable entity. Deploying it, pointing its ingestion at the mesh's sources,
and declaring the cross-product lineage is the step that completes the
architecture these two diagrams describe.

## Deploying the catalog without it eating the cluster

OpenMetadata is the heaviest component in the capstone, and its published
production sizing is daunting: the backend database alone is speced at 4 vCPU
and 16 GiB, the search tier at 2 vCPU and 8 GiB across three nodes, and the
ingestion tier (historically Apache Airflow) at another 4 vCPU and 16 GiB.
Summed, that's well over 40 GiB — more than the whole `capstone` profile. Those
are figures for sustained enterprise ingestion load, not for a single-node demo
that catalogs five services, but they make the point: a naïve install does not
fit. Three deliberate choices bring it down to roughly four to five gigabytes
on top of the existing stack, well inside the profile, with no resize:

The largest saving is dropping **Airflow**. Through version 1.11 OpenMetadata
ran ingestion through a full Airflow deployment — an API server, a scheduler, a
DAG processor, a triggerer, and a metrics sidecar, several pods between them. As
of 1.12 ingestion no longer requires it: a workflow is just the ingestion
framework reading a YAML config and pushing metadata to the server's API, which
can run as a one-off Kubernetes Job. The capstone disables the Airflow
dependency entirely and will run ingestion that way, deleting the heaviest tier
outright.

The second choice is running **OpenSearch as a single node in development
mode**. A search engine that memory-maps its index segments normally insists,
at startup, that the host kernel allow at least 262,144 memory-map areas per
process (`vm.max_map_count`) — and refuses to boot if it doesn't. On a
single-machine cluster that would mean changing a host kernel parameter, which
is both intrusive and, on a container-based node, fiddly and non-persistent. The
escape is that this is a *bootstrap check*, and bootstrap checks are only
enforced in production mode. Put the node in single-node discovery mode and it
runs in development mode, where the same limit becomes a non-fatal warning. So
the capstone runs OpenSearch single-node and **never touches the host kernel** —
no `sysctl`, no privileged init container reaching out to the node. One trimmed
search node, a one-gigabyte heap, plenty for a demo catalog.

The third choice is **reusing the Postgres already in the cluster**.
OpenMetadata needs an operational database for its own store — its 168-odd
tables of entities, relationships, and lineage. Rather than stand up the chart's
bundled MySQL (another stateful service, and a second database engine in an
otherwise all-Postgres mesh), the capstone provisions a dedicated `openmetadata`
database and role inside the same CloudNativePG cluster the services use, and
points OpenMetadata's backend at it. This is the one place worth being careful
about the distinction: the `openmetadata` database is OpenMetadata's *own*
operational store, not a data product — the per-service product schemas stay in
their own `capstone` database. Reuse here is a deployment convenience, not a
blurring of ownership.

The install itself is two Helm releases from the official charts — the trimmed
dependencies (OpenSearch only) and the server — plus a small provisioning step
that creates the `openmetadata` database and role in the existing cluster and
the secret holding its password. A reader runs `scripts/setup-openmetadata.sh`
and then `demos/smoke-openmetadata.sh`, which confirms the server is rolled out,
that its version API answers (proving it booted *and* reached Postgres), and
that the `openmetadata` database is populated — proving Postgres reuse, not a
fallback, is the live backend.

A candid note on what that took, because it's the kind of thing tutorials
usually hide. Getting a large third-party chart to deploy against
already-running infrastructure is rarely a clean first pass, and here the
friction was entirely in *secret wiring*, not in any of the architectural
choices above. The chart generates some secrets itself and expects you to supply
others; naming a supplied secret the same as a generated one makes Helm refuse
to proceed, because it won't take ownership of a resource it didn't create. And
a chart can keep referencing a secret for a feature you've disabled — here the
server's containers carried an `AIRFLOW_PASSWORD` reference even with the
pipeline client switched off, and Kubernetes won't start a container whose
secret reference points at nothing, even if the value is never read. Both are
invisible until install time; both are one-line fixes once seen (use a distinct
secret name; create a placeholder for the dangling reference). The lesson worth
carrying to any chart of this size: before installing, render it and list every
secret it both *creates* and *references*, and make sure each one exists with the
shape the chart expects. The decision log records the specifics.

## Pointing ingestion at the sources, and declaring the lineage

A deployed catalog is an empty catalog until something feeds it. OpenMetadata's
model is pull-based: you describe a source — a database, a message broker — and
an *ingestion workflow* connects to it, reads its metadata, and writes entities
back through the server's API. Because the deploy runs no orchestrator (the
Airflow tier was the first thing dropped), each workflow runs as a plain,
one-off Kubernetes Job built on the `openmetadata/ingestion` image, which
carries the `metadata` CLI. A Job mounts its workflow config, fetches a token,
and runs `metadata ingest -c <config>`. There is no scheduler to keep alive
between runs; you re-run the Job when you want to refresh.

Two sources feed the catalog here. The first is Postgres. The workflow points at
the same CloudNativePG read-write Service the services use, authenticating as the
application role — and because that one role owns every service's schema (one
database, a schema per product), a single connection catalogs them all. The
scope is the `capstone` database only, so the catalog never wanders into
OpenMetadata's own operational store. The result is a Database Service whose
tables are the products' tables: orders, notifications, and the rest. The second
is Kafka. That workflow needs only the broker's bootstrap address; it discovers
the topics and records them as a Messaging Service. It stops there deliberately —
the topics' Avro schemas live in the registry, and linking the catalog to the
registry is a later, separate step. Keeping this pass to broker-and-topics keeps
the concern small.

Ingestion gives you an inventory: these tables exist, these topics exist. What it
does not give you is the relationship *between* them — that an order written to
one product's table becomes an event on a topic that a different product consumes
into its own table. That flow is real, it crosses product boundaries, and it is
exactly the thing a mesh catalog exists to make visible. OpenMetadata can infer
lineage from query logs, but there are none here; and this flow runs from a table
to a topic to a table, across entity types. So you declare it, using the
catalog's first-class lineage API: two directed edges that spell out the spine.

> orders (Postgres table) → order-placed (Kafka topic) → notifications (Postgres table)

The first edge is order-service's producer relationship; the second is
notification-service's consumer relationship. A third Job declares them, after
the two ingestion Jobs, because you can only link entities that already exist.
The whole sequence is one script — `scripts/ingest-openmetadata.sh` runs the
three Jobs in order and waits for each — and `demos/smoke-om-lineage.sh` proves
the outcome over the API: both services present, the three entities cataloged,
and the topic carrying an upstream edge from orders and a downstream edge to
notifications. Open the topic's Lineage tab in the UI and the cross-product flow
is drawn for you. That picture — assembled from the products' own ground truth,
not hand-maintained — is what the contract-and-catalog arc was building toward.

## Evolving a contract in the open: the v1→v2 canary

A catalog tells you a product's contract exists and who depends on it. The next
question a mesh has to answer is operational: how does a product *change* that
contract without a flag-day break that strands its consumers? The answer the
mesh offers is a canary — deploy the new version alongside the old, route a
small slice of live traffic to it, watch, and shift more as confidence grows.
Here that plays out on order-service, the REST product whose contract Apicurio
already holds and whose lineage the catalog already draws.

The change is deliberately small and backward-compatible: v2 adds a `currency`
field to order responses — the kind of additive evolution that shouldn't break
anyone, but that you'd still want to roll out gradually rather than all at once.
v2 deploys next to v1 as a second workload sharing the same Service; what
distinguishes them to the mesh is a `version` label. Istio's pieces then do the
shaping: a `DestinationRule` names the two subsets by that label, and a
`VirtualService` assigns each a weight. Send traffic through the ingress gateway
and roughly that fraction reaches each version. Move the weights — 90/10, then
50/50, then 0/100 — and the split moves with them. That is the whole canary: not
a binary switch, but a dial.

Two details earn a mention because they bite in practice. First, both versions
need an Envoy sidecar for the routing to take effect, so order-service joins the
mesh — but only order-service. Injecting the operator-managed infrastructure
(the Postgres and Kafka pods, the catalog) is a different and riskier
proposition, so the mesh here is scoped to the product being canaried; broader
mTLS is left for later. Second, giving each version its own subset means the v1
Deployment's selector has to name `version: v1` so it owns only its own pods —
and a Deployment's selector is immutable, so an already-running v1 must be
recreated once when you enable this. The script detects that situation and tells
you the one-line fix rather than failing cryptically.

`scripts/setup-istio.sh` installs the control plane and turns on injection;
`demos/smoke-canary.sh` deploys v2, applies the routing, drives a hundred
requests at 90/10, shifts to 50/50, and confirms the observed split each time —
and renders a small SVG of it, so the dial is something you can see, not just
infer from logs. The principle underneath: in a mesh, a product owns its own
rollout, and changing a contract is a controlled, observable operation rather
than a coordinated outage.

## Scaling to demand, and to zero: elastic data products

A canary controls *which* version serves traffic; the next question is *how
much* of each product to run at all. In a data mesh the honest answer is "as
much as the demand warrants, and nothing when there's none" — products that
cost nothing while idle and expand when work arrives. KEDA provides that, and
the capstone uses it in the two shapes the mesh actually needs, because its
products take work in two different ways.

The event consumers take work as backlog. notification-service reads the
`order-placed` topic, so the natural signal is consumer-group lag: a
`ScaledObject` watches the gap between what's been produced and what the group
has consumed, and runs one consumer per few messages of lag, up to a bound —
and to zero when the topic is quiet. KEDA reads that lag straight from Kafka
even with no consumer running, so an idle product wakes the moment a backlog
appears and costs nothing in between. That's the §12 Kafka pattern, now earning
its place on a real product rather than a toy consumer.

The synchronous services take work as requests. graphql-gateway answers GraphQL
queries over HTTP, so the signal is in-flight request concurrency, and the tool
is KEDA's HTTP add-on: an interceptor sits in front of the Service, scales the
gateway on how many requests are in flight, and — the part that makes
scale-to-zero usable for a request/response service — holds the very first
request while a replica starts, so waking from zero is invisible to the caller
beyond a cold-start pause. (One install detail earns its keep here: the
interceptor's `waitTimeout` — how long it will hold that first request — defaults
to 20 seconds, and a real cold start on a single node, image pull and Python boot
included, can outrun that. When it does, the held request fails with a
"context deadline exceeded" 502 *before* a backend exists, which also denies KEDA
the steady pending-request signal it scales on. `setup-keda.sh` raises it to 180s
so the cold start fits inside the hold.)

Two placement choices are deliberate. HTTP scaling lives on the gateway, not on
order-service: order-service is the canary subject, and the add-on's interceptor
would fight Istio's VirtualService over that service's ingress path. And both
KEDA-scaled services stay *out* of the mesh — the namespace is injection-labeled
for the canary, so each carries an explicit `sidecar.istio.io/inject: "false"`
to keep the autoscaling path clear of an Envoy sidecar. The mesh stays scoped to
the one product being canaried; everything else scales unmeshed.

`scripts/setup-keda.sh` installs KEDA core plus the HTTP add-on;
`demos/smoke-keda-kafka.sh` and `demos/smoke-keda-http.sh` each prove the whole
arc — scaled to zero, scaled up under load (a message burst for the consumer, a
traffic burst for the gateway), and back to zero once the work is gone. The
principle the two share: a data product's footprint should track its demand, and
zero demand should mean zero footprint.

One subtlety worth knowing, because it's easy to misread: both scalers return to
zero quickly. The Kafka `ScaledObject` carries `cooldownPeriod: 30` and the
consumer scales down within a minute of the backlog clearing; the gateway's
HTTPScaledObject carries `scaledownPeriod: 30` and behaves the same — once traffic
genuinely stops it's back to zero in about half a minute. The catch is what
"traffic genuinely stops" means. The HTTP add-on scales on in-flight
*concurrency*, and an open connection counts — so a client that holds a
connection to the interceptor (a browser tab, or a lingering `kubectl
port-forward`) keeps the metric above zero and the scale-down timer never starts.
Drop the connection and the gateway stands down in ~30 seconds; leave one hanging
and it can look like the service refuses to scale to zero at all. That's a real
operational gotcha, not a KEDA defect: the metric is faithfully reporting that
something is still connected. The bundled `smoke-keda-http.sh` closes its
port-forward before it expects scale-down for exactly this reason, and it asserts
on KEDA's decision — the Deployment's desired replicas reaching zero — rather than
waiting on the last pod to finish terminating.

## Seeing it: metrics with Prometheus and Grafana

Everything so far has been verified by smoke scripts poking the cluster and
reading back exit codes — which works, but it's debugging in the dark. The KEDA
HTTP scaler made that vivid: half a dozen failures that each looked like a
different problem from the outside, when a single graph of "how many gateway
replicas are there, over time" would have shown the wake, the cold-start lag, and
the near-zero oscillation at a glance. A data mesh needs to be observable for the
same reason it needs a catalog: you can't operate what you can't see.

The deliberate choice here is to stay lean and add nothing to the services. You
already have two sources of real telemetry that cost nothing extra. The Istio
sidecar on the meshed order-service exports `istio_requests_total` (request rate,
response codes, latency) with no application code — the mesh measures the traffic
for you. And `kube-state-metrics` turns the Kubernetes API itself into metrics,
including `kube_deployment_spec_replicas` and `kube_deployment_status_replicas_ready`
— desired and ready replica counts for every workload. That second pair is the
one that matters most here: it's the direct, recorded signal of KEDA scaling.

So the stack is just two things, installed by `scripts/setup-observability.sh`
into an `observability` namespace: a single Prometheus (short 24h retention, no
persistence, with `kube-state-metrics` enabled and alertmanager, pushgateway, and
node-exporter all switched off) and a Grafana that comes up with the Prometheus
datasource and one dashboard already provisioned. Prometheus's default pod-scrape
job picks up the Istio sidecar automatically, because Istio annotates meshed pods
with the `prometheus.io/scrape` markers it looks for. Sized to roughly 512Mi/1Gi
for Prometheus and 128Mi/256Mi for Grafana, the whole thing fits inside the
cluster's existing headroom — no profile bump.

The provisioned dashboard, "Capstone — Scaling & Traffic," leads with the panel
that pays off the whole KEDA chapter: desired versus ready replicas for
`graphql-gateway` and `notification-service`, drawn step-style over time. Run
`smoke-keda-http.sh` with the dashboard open and you watch the gateway's desired
count step from 0 to 1 the moment a request arrives, hold while traffic flows,
and fall back toward 0 when it stops — including the brief flapping near zero that
the prose above describes, now something you can see rather than infer. The second
panel charts order-service's request rate by response code straight from the mesh;
drive it with `smoke-canary.sh` and the weighted v1/v2 split shows up as traffic.
`scripts/setup-observability.sh` then `demos/smoke-observability.sh` install the
stack and verify the data is actually flowing before you go looking for graphs.
One login gotcha worth flagging: the Grafana chart preserves an existing admin
password across upgrades, so don't assume the values default — read the real
credentials from the secret with `kubectl get secret grafana -n observability -o
jsonpath='{.data.admin-password}' | base64 -d`. The setup script prints this for
you.

This is the metrics half of observability, and it stands on its own. The traces
half is wired end to end too. `setup-observability.sh` installs Grafana Tempo
(monolithic mode, receiving OTLP directly — no separate collector, since our
metrics come from scraping rather than OTLP), and the gateway's image is
instrumented with OpenTelemetry: its Containerfile pip-installs the OTEL distro
and runs `opentelemetry-bootstrap`, which detects FastAPI, httpx, and gRPC and
pulls the matching instrumentations, and its entrypoint is wrapped with
`opentelemetry-instrument`. With `OTEL_EXPORTER_OTLP_ENDPOINT` pointed at Tempo
(set on the Deployment), a single GraphQL query becomes a distributed trace: a
server span for the incoming request, a client span for the REST call to
order-service, and — when the order exists — a client span for the gRPC stock
check against inventory-service. The fan-out you read about in the federation
section is now a picture in Grafana's Tempo explorer. `demos/smoke-trace-flow.sh`
drives a query through the interceptor and confirms the trace lands; instrumenting
the remaining services (so their server-side spans join the same trace) is a
mechanical extension of the same pattern.

Two notes that save confusion. The instrumentation is a no-op without the
`OTEL_*` env, so the same image runs fine untraced. And spans export
fire-and-forget over a batch processor — if Tempo is down, the gateway doesn't
care, which is the right failure mode for telemetry but also why a missing trace
points at the exporter config or Tempo, never at the request path.

## What the capstone builds, and what's still ahead

The capstone assembles a small but complete data mesh: five domain services
(order, inventory, payment, shipping, notification) plus a GraphQL gateway,
each an independently deployed data product with its own Postgres schema,
communicating over the protocol that fits each interaction — REST for the
order API, gRPC for the order→inventory stock check, GraphQL for federated
reads, and Kafka events for the asynchronous order→notification flow.
Postgres is managed by the CloudNativePG operator and Kafka by the Strimzi
operator, all running rootless on a dedicated minikube profile.

Still ahead, layered on this foundation: extending tracing across every service
(only the gateway is instrumented today, so a query's downstream hops show as
client spans rather than full server-side spans) and scheduled cross-service
orchestration (Prefect). The contract, catalog, traffic-management, autoscaling,
metrics, and tracing layers are now in place — Apicurio versions every contract,
OpenMetadata turns schemas and topics into browsable lineage, Istio shifts live
traffic between contract versions as a controlled canary, KEDA scales each
product to the demand on it and back to zero when idle, Prometheus plus Grafana
make that scaling and the mesh traffic visible, and Tempo turns a GraphQL query
into a distributed trace. Each increment lands the same way: focused and
independently verifiable — the rhythm the protocol work has followed.

## References

- **Zhamak Dehghani**, *Data Mesh: Delivering Data-Driven
  Value at Scale* (O'Reilly, 2022). The canonical source for
  the four principles
- **Bilgin Ibryam & Roland Huss**, *Kubernetes Patterns*
  (O'Reilly, 2nd ed. 2023). Referenced throughout the
  implementation iterations when each pattern shows up.
  Examples repo: <https://github.com/k8spatterns/examples>
- **OpenMetadata documentation**: <https://docs.open-metadata.org/>
- **Apicurio Registry**: <https://www.apicur.io/registry/>
- **Strimzi**: <https://strimzi.io/>
- **KEDA**: <https://keda.sh/>
- **Istio**: <https://istio.io/>

## The examples/17-capstone/ directory

Everything for the capstone lives under `examples/17-capstone/`: the helm
umbrella chart and per-service subcharts, the service source, the protocol
definitions, the operator setup scripts, and the demo scripts that verify
each capability end-to-end against a live cluster.

```
examples/17-capstone/
├── README.md                  ← overview & quick-start
├── charts/capstone/           ← helm umbrella chart
│   └── charts/                ← per-service + platform subcharts
│       ├── order-service/   inventory-service/   payment-service/
│       ├── shipping-service/ notification-service/ graphql-gateway/
│       ├── postgres/          ← CloudNativePG cluster CR
│       └── kafka/             ← Strimzi KRaft cluster + topic
├── services/                  ← FastAPI service source (one dir per service)
├── proto/                     ← gRPC protobuf definitions
├── scripts/                   ← profile + operator setup, codegen
└── demos/                     ← smoke scripts (one per capability)
```

Each capability has a smoke script under `demos/` that deploys what it needs
and asserts the behaviour: the REST round-trip, the gRPC stock check, the
federated GraphQL query, and the Kafka event flow. They're the executable
proof behind the claims in this section.

[← Back to §16: Examples]({{ "/docs/16-examples/" | relative_url }})
