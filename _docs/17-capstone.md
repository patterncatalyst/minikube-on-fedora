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
