# §17 Capstone — Data mesh on minikube

The full implementation of the §17 capstone: five Python/FastAPI
services exposing REST, gRPC, GraphQL, and Kafka interfaces,
deployed via helm to a dedicated minikube profile, with full
observability, metadata cataloging, and orchestration.

This is the **runnable counterpart** to
[`_docs/17-capstone.md`](https://patterncatalyst.github.io/minikube-on-fedora/docs/17-capstone/).
Read the section page for the data-mesh conceptual background;
this README is the operational entry point for actually running
the system.

## Status

**r20 (current):** skeleton — directory structure, helm chart
scaffolding, profile setup. Nothing deployable yet beyond the
profile itself.

Implementation lands incrementally:

- r21: order-service (the prototype every other service follows)
- r22: inventory, payment, shipping, notification services
- r23: gRPC layer (proto definitions, codegen, wiring)
- r24: GraphQL layer + federated gateway
- r25: Kafka integration
- r26: KEDA + Istio wiring
- r27: observability + OpenMetadata
- r28: Prefect orchestration
- r29: tests + Postman collection + walkthrough prose
- r30: editorial pass + verification

## Directory layout

```
examples/17-capstone/
├── README.md                  ← this file
├── charts/capstone/           ← helm umbrella chart
│   ├── Chart.yaml             ← (r20) chart definition, no deps yet
│   └── values.yaml            ← (r20) feature flags + sizing for every component
├── scripts/
│   ├── setup-capstone-profile.sh    ← (r20) start the capstone minikube profile
│   └── teardown.sh                  ← (r20) stop or delete the profile
├── proto/                     ← (r23) protobuf definitions for gRPC services
├── postman/                   ← (r29) Postman collection for live demos
├── demos/                     ← (r25+) demo scripts: rest, grpc, graphql, kafka, orchestration
└── services/                  ← (r21+) source for the 5 services + GraphQL gateway
    ├── order-service/
    ├── inventory-service/
    ├── payment-service/
    ├── shipping-service/
    ├── notification-service/
    └── graphql-gateway/
```

Empty directories are placeholders; contents arrive in the
iterations listed above.

## Quick-start (r20 — profile only)

```bash
./scripts/setup-capstone-profile.sh
```

This creates a `capstone` minikube profile sized at 24 GB RAM /
16 CPU / 80 GB disk, with the podman driver and containerd
runtime. Other minikube profiles should be stopped first
(`minikube stop -p minikube`, `minikube stop -p istio`) to free
their RAM allocation — the script warns if it detects any other
running profiles.

To stop (preserving state):

```bash
./scripts/teardown.sh
```

To delete entirely:

```bash
./scripts/teardown.sh --remove-profile
```

## Configuration

The helm umbrella chart's `values.yaml` has feature flags for
every component:

```yaml
strimziCluster:        { enabled: true, ... }
apicurio:              { enabled: true, ... }
openmetadata:          { enabled: true, ... }
postgres:              { enabled: true, ... }
observability:         { enabled: true, ... }
prefect:               { enabled: true, ... }
kedaScaling:           { enabled: true, ... }
orderService:          { enabled: true, ... }
inventoryService:      { enabled: true, ... }
paymentService:        { enabled: true, ... }
shippingService:       { enabled: true, ... }
notificationService:   { enabled: true, ... }
graphqlGateway:        { enabled: true, ... }
```

Set any to `enabled: false` for a partial-stack deploy. Useful
when debugging a specific service in isolation or when the host
is RAM-constrained.

## Prerequisites recap

- Fedora 44 (only tested platform)
- 64 GB RAM (24 GB for the capstone profile, headroom for the host)
- 1 TB disk (≥30 GB free for image cache + PVs)
- §1's `fs.inotify.max_user_instances` tweak applied
- Standard §1–§2 tooling: podman, minikube, kubectl, helm
- Other minikube profiles stopped before deploying the full stack
