---
title: "Services & data products"
order: 3
description: The services, the order-service template, and the anatomy of a data product — its ports, its internal transformation, and the container image that ships it.
duration: 30 min
---

*Part of the [capstone]({{ '/capstone/data-mesh/00-index/' | relative_url }}).*

With the [principles]({{ '/capstone/data-mesh/01-concepts/' | relative_url }}) and the
[Kubernetes mapping]({{ '/capstone/data-mesh/02-kubernetes-substrate/' | relative_url }})
in place, this page gets concrete: what the data products in this capstone actually
are, the one service we build end-to-end as a template for the rest, and how a data
product is packaged and shipped as a container image. This is the first
implementation-heavy page — the conceptual scaffolding is behind us.

## What a data product looks like here

A data product, in the abstract, is the *architectural quantum* of a data mesh: the
smallest unit you can independently deploy and operate, carrying everything it needs
to do its job. It has input ports (where data comes in), output ports (where it serves
data out), the transformation logic between them, and the metadata and policies that
make it discoverable and governed.

![Anatomy of a data product — ports in, ports out, transformation and governance inside]({{ '/assets/diagrams/17-data-product-anatomy.svg' | relative_url }})

In this capstone, that abstraction is concrete: **each domain service *is* a data
product.** It owns a slice of the database (its input/internal state), it serves data
through its APIs (output ports), it emits events as other domains' input, and it
publishes a contract and metadata so it can be discovered and depended on. The service
boundary and the data-product boundary are the same boundary — which is the cleanest
way to make domain ownership real rather than aspirational.

## The domain

The domain is order-placement-through-fulfillment, modeled deliberately small so the
architecture stays legible. There are **five domain services**, each a bounded context
owning its data and its contract, plus **one gateway** that composes reads across them
(the gateway is a read-layer convenience, not a domain data product — six images in
all). The five domains:

| Service | Domain | Owns | Talks via |
|---|---|---|---|
| order-service | Order lifecycle | the `orders` schema, the order state machine | REST in from clients, gRPC out to inventory/payment/shipping, publishes `orders.placed` |
| inventory-service | Stock levels | the `inventory` schema | gRPC server, publishes `inventory.updated`, consumes `orders.placed` |
| payment-service | Payments | the `payments` schema | gRPC server, publishes `payments.processed`, consumes `orders.placed` |
| shipping-service | Shipments | the `shipments` schema | gRPC server, publishes `shipments.dispatched`, consumes `payments.processed` |
| notification-service | Notifications | the `notifications` schema | Kafka consumer only — reacts to events, emits notifications |

The variation is deliberate: **not every service exposes every protocol.** Each
exposes the protocols that fit its role, not a uniform surface. notification-service
is event-only because its job is to react, not to be called synchronously; the gateway
exists to compose reads so clients don't have to fan out across five services. The
reasoning behind which protocol goes where is the subject of the
[data planes page]({{ '/capstone/data-mesh/05-data-planes/' | relative_url }}); here the
point is just that the surface follows the role.

Each service owns its own schema in a shared Postgres cluster — one schema per domain,
so the database is partitioned by ownership even though it's one managed cluster. That
"one cluster, one schema per service" choice is what keeps per-domain data ownership
real without running five separate databases on a single learning node.

## Build one service end to end first

Rather than build all six services a layer at a time, the capstone takes a single
service all the way through first — a *walking skeleton*. The point is to prove the
entire spine works before widening: build the image, get it to the cluster, deploy via
helm, have the operator-managed Postgres come up, the service connect, and data
round-trip through a real API call. Once that path is verified on real hardware, the
remaining services are mechanical repetition of the same pattern.

**order-service is that template.** It's a Python service that owns the `orders`
schema. It starts speaking only REST, and gRPC, GraphQL, and event publishing get
layered on in later steps — but the deployment spine is proven first with the simplest
possible surface.

A couple of packaging choices carry across all six images. Dependencies are managed
with a lockfile so builds are reproducible, and the lockfile is exported into the image
rather than carrying the dependency manager into the runtime. The image itself is
multi-stage: a builder stage resolves dependencies, and a slim runtime stage copies
only the resolved environment and the application code, runs as a non-root user, and
serves the app. Standard production hygiene — the capstone just applies it from the
start rather than retrofitting it.

## Getting images to the kubelet

The capstone runs on minikube's Docker driver with the containerd runtime, on Docker
Engine, so the image path has two steps and no registry. Build on the host with
`docker build -f Containerfile`, then copy the image into the profile's containerd
store with `minikube -p mof-capstone image load`. One script does both:

```bash
./scripts/build-image.sh services/order-service order-service v1
```

Three conventions keep this predictable. Images use bare names with an explicit tag
(`order-service:v1`), the charts set `imagePullPolicy: Never` so the kubelet only ever
uses what was loaded, and the script runs `kubectl rollout restart` after a reload,
because with `Never` a running pod keeps its old image until it restarts. Loaded
images live in the node's containerd store, so they should survive `minikube stop` and
`minikube start`; `cluster-up.sh` re-loads any that are missing.

The base image is `ubi10/python-314-minimal` (Python 3.14), with `ubi9/python-314` as
the documented fallback. Python 3.14 is why asyncpg is pinned at 0.32: that is the
release that ships a cp314 wheel.

An earlier iteration of this build pushed images to the registry addon under a
different driver and hit a run of driver-specific failures. Those are kept as
lessons, not repeated here; see Part 4 of
[LESSONS-LEARNED](https://github.com/patterncatalyst/minikube-on-fedora/blob/main/onboarding/LESSONS-LEARNED.md).

With a service shipped and running, the next question is how products describe
themselves so others can find and trust them — contracts and the catalog.
