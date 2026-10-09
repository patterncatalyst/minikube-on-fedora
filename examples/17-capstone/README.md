# §17 Capstone — Data mesh on minikube

The full implementation of the §17 capstone: seven Python/FastAPI
services exposing REST, gRPC, GraphQL, and Kafka interfaces,
deployed via helm to a dedicated `mof-capstone` minikube profile, with full
observability, metadata cataloging, and orchestration.

This is the **runnable counterpart** to
[`_docs/17-capstone.md`](https://patterncatalyst.github.io/minikube-on-fedora/docs/17-capstone/).
Read the section page for the data-mesh conceptual background;
this README is the operational entry point for actually running
the system.

The capstone continues as two standalone projects:
[datamesh-reference-arch-python](https://github.com/patterncatalyst/datamesh-reference-arch-python)
(a fork of this capstone) and
[datamesh-reference-arch-quarkus](https://github.com/patterncatalyst/datamesh-reference-arch-quarkus)
(the same mesh on Quarkus and Camel).

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
│   ├── setup-capstone-profile.sh    ← (r20) start the mof-capstone minikube profile
│   ├── build-image.sh               ← docker build + minikube image load
│   └── teardown.sh                  ← (r20) stop or delete the profile
├── host-access/               ← companion NodePort Services for third-party UIs
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

This creates a `mof-capstone` minikube profile sized at 24 GB RAM /
16 CPU / 80 GB disk, with the Docker driver and containerd runtime
(runc) on Docker Engine. The profile is named `mof-capstone`, not
`capstone`, so it never collides with another project's minikube
profile on the same host; the Kubernetes namespace is still
`capstone`. Other minikube profiles should be stopped first
(`minikube stop -p minikube`, `minikube stop -p istio`) to free
their RAM allocation — the script warns if it detects any other
running profiles.

The script publishes every host-facing port when it creates the
profile (see [Host ports](#host-ports)). Published ports cannot be
added to an existing profile, so if the map changes, recreate it with
`./scripts/setup-capstone-profile.sh --replace`.

To stop (preserving state):

```bash
./scripts/teardown.sh
```

To delete entirely:

```bash
./scripts/teardown.sh --remove-profile
```

## Building service images

Each service builds with Docker Engine and loads into the profile's
containerd store; there is no registry:

```bash
./scripts/build-image.sh services/order-service order-service v1
```

The script runs `docker build -f Containerfile`, then
`minikube -p mof-capstone image load`, then
`kubectl rollout restart` for an existing Deployment. Images use bare
names (`<svc>:v1`) with `imagePullPolicy: Never`. Loaded images are
expected to survive `minikube stop` and `minikube start`. The
services build on `ubi10/python-314-minimal` (Python 3.14, asyncpg
0.32 for its cp314 wheel), with `ubi9/python-314` as the fallback.

## Host ports

Seventeen NodePorts are published to `127.0.0.1` at profile creation
(`CAPSTONE_PORTS` in `scripts/lib/env.sh`). Nothing is forwarded or
tunneled, so the endpoints stay up across shell sessions. Third-party
UIs (OpenMetadata, Kiali, the ingress gateway, the KEDA interceptor,
Postgres) are reached through companion NodePort Services in
`host-access/`, which select the same pods and survive chart upgrades.

| Service | Host URL | NodePort |
|---|---|---|
| order-service | `127.0.0.1:18080` | 30180 |
| inventory-service | `127.0.0.1:18082` | 30182 |
| payment-service | `127.0.0.1:18083` | 30183 |
| shipping-service | `127.0.0.1:18084` | 30184 |
| Apicurio Registry | `127.0.0.1:18085` | 30185 |
| review-service | `127.0.0.1:18086` | 30186 |
| notification-service | `127.0.0.1:18097` | 30197 |
| graphql-gateway | `127.0.0.1:18099` | 30199 |
| OpenMetadata | `127.0.0.1:8585` | 30585 |
| Postgres (primary) | `127.0.0.1:5432` | 30432 |
| Istio ingress gateway | `127.0.0.1:8080` | 30880 |
| KEDA HTTP interceptor | `127.0.0.1:8081` | 30881 |
| Kiali | `127.0.0.1:20001/kiali` | 30201 |
| Prometheus | `127.0.0.1:9090` | 30090 |
| Grafana | `127.0.0.1:3000` | 30300 |
| Tempo (HTTP) | `127.0.0.1:3200` | 30320 |
| Tempo (OTLP/HTTP) | `127.0.0.1:4318` | 30418 |

Credentials are never printed by the scripts. Find them in the
values files: `openmetadata/om-app-values.yaml` for OpenMetadata and
the observability chart values for Grafana.

If the demos report a port as unpublished, the profile predates the
current map; recreate it with `--replace`. Why the earlier
registry-based setup was dropped is recorded in Part 4 of
[LESSONS-LEARNED](https://github.com/patterncatalyst/minikube-on-fedora/blob/main/onboarding/LESSONS-LEARNED.md).

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
- 64 GB RAM (24 GB for the mof-capstone profile, headroom for the host)
- 1 TB disk (≥30 GB free for image cache + PVs)
- §1's `fs.inotify.max_user_instances` tweak applied
- Standard §1–§2 tooling: Docker Engine (docker-ce), minikube, kubectl, helm
- Other minikube profiles stopped before deploying the full stack
