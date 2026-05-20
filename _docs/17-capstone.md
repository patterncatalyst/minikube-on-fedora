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
protocol. Per the decision in r19's PRD addition, each service
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
| KEDA + HTTP add-on | Scale order-service on HTTP load; scale Kafka consumers on lag | §12 |
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

## What §17 delivers vs what's coming

This iteration (r20) ships the **skeleton**: the directory
structure under `examples/17-capstone/`, the helm umbrella
chart's `Chart.yaml` and `values.yaml` (with feature flags
for every subchart), the profile setup and teardown scripts,
this prose, and the architecture diagram.

Subsequent iterations fill in the implementation:

- **r21** — order-service: FastAPI + REST + Postgres schema +
  helm subchart + smoke tests. Establishes the pattern every
  other service follows
- **r22** — inventory, payment, shipping, notification —
  identical pattern to order-service, parallelized
- **r23** — gRPC layer: proto definitions, `buf` codegen,
  client/server wiring, `ghz` test scripts
- **r24** — GraphQL layer: per-service subgraphs +
  Strawberry-based federation gateway
- **r25** — Kafka integration: topics, schema registration
  via Apicurio, producers + consumers, demo flows
- **r26** — KEDA + Istio wiring: ScaledObjects, traffic
  shifting, Kiali walkthrough
- **r27** — observability: OTEL Collector deployment,
  Prometheus + Grafana + Tempo, OpenMetadata install with
  schema ingestion
- **r28** — Prefect orchestration: server install, flows for
  metadata sync and nightly reconciliation
- **r29** — tests + Postman collection + walkthrough prose
- **r30** — editorial pass + verification + project close-out

The PRD addition from r19 includes the success criteria and
risk register; refer to `PRD.md` § "Capstone: a data mesh on
minikube" for the full scope statement.

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

## Verification: examples/17-capstone/

The capstone has its own `examples/17-capstone/` directory
containing the helm charts, service source code, demo
scripts, and Postman collection. The directory structure
shipped in r20:

```
examples/17-capstone/
├── README.md                  ← overview & quick-start
├── charts/capstone/           ← helm umbrella chart (skeleton)
│   ├── Chart.yaml
│   └── values.yaml
├── scripts/
│   ├── setup-capstone-profile.sh
│   └── teardown.sh
├── proto/                     ← gRPC proto definitions (r23)
├── postman/                   ← API collection (r29)
├── demos/                     ← demo scripts (r25 onwards)
└── services/                  ← service source (r21 onwards)
```

Empty directories are placeholders for content arriving in
the iterations listed above. Each iteration's reconciliation
plan entry tracks what landed in which directory.

[← Back to §16: Examples]({{ "/docs/16-examples/" | relative_url }})
# §17 prose addition — r21 (order-service)

> Merge instructions: insert the section below into
> `_docs/17-capstone.md`, immediately BEFORE the
> "## What §17 delivers vs what's coming" heading (which r20
> shipped). It documents the order-service implementation and
> the operator-is-cluster-wide teaching point. Once merged,
> delete this file.

---

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
For r21 it speaks only REST; gRPC, GraphQL, and Kafka are
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
minimal for r21: a Deployment and a Service. The Deployment
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

That single passing run proves the entire spine. From here,
r22 adds the other four services as parallel repetitions of
this template; later iterations layer on gRPC, GraphQL, Kafka,
KEDA scaling, the observability stack, OpenMetadata, and
Prefect.
# §17 friction callout — r21c

> Merge instructions: insert the section below into `_docs/17-capstone.md`,
> inside the "## Implementation: order-service (the template)" section,
> immediately after the "### Postgres via an operator — and why that's
> cluster-wide" subsection (or wherever the image-build workflow is first
> discussed). Once merged, delete this file.

---

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
