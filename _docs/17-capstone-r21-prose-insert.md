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
