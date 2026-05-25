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

## The one part that fights back: getting images to the kubelet

This is worth its own section because it's the single part of the capstone that
reliably trips people up, and it's a direct consequence of a deliberate choice made
back in §3: the capstone uses the **rootless-podman driver with the containerd
runtime**, because that's the most realistic local mirror of how Kubernetes runs in
production. The cost of that realism is that getting a locally-built image to the
kubelet is not as simple as you'd expect.

The intuitive approaches are unreliable on this driver. `minikube image build` can
exit successfully without the image actually landing in the profile's containerd
store, so the pod then fails to pull. `minikube image load` can report "image not
found" for an image that's plainly present, because the lookup goes through the
rootless podman socket in a way that doesn't resolve.

The reliable answer the capstone standardizes on is **minikube's built-in registry
addon**: build on the host with podman, push to the registry, and let deployments pull
from it like any ordinary image. The one detail that catches everyone is that the
registry has *two addresses*. With the podman driver the host-side port is not 5000 —
minikube assigns one (something like `127.0.0.1:41685`) and tells you when you enable
the addon — while *inside* the cluster the kubelet reaches the same registry at
`localhost:5000`. So you **push** from the host to `127.0.0.1:<assigned-port>` and the
cluster **pulls** from `localhost:5000`. The build script discovers the host port
automatically; the charts pull from the in-cluster address.

One environment variable makes or breaks all of this: `MINIKUBE_ROOTLESS=true`. If
it's not set in your shell, minikube routes host operations through `sudo podman`,
which can't see your rootless container — producing a spread of failures that look
like a broken cluster but aren't. The capstone scripts both persist it and export it
at the top of every script; if you run minikube commands by hand, export it first.

None of this is unique to the capstone — it's inherent to the rootless driver — but
the capstone is where it bites, because it's the first place you build and deploy your
*own* images at scale. Get the registry workflow right once here, and every service
afterward is the same three commands. (The deeper operational sharp edges of running
all this on a single node are collected as gotchas, separate from this build-level
friction.)

With a service shipped and running, the next question is how products describe
themselves so others can find and trust them — contracts and the catalog.
