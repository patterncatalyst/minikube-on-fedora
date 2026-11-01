---
title: "Ambassador"
order: 9
part: "Structural"
description: "Broker an application's outbound connection through a localhost proxy sidecar, worked by letting shipping-service reach Postgres without a single Postgres-aware environment variable."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain what an ambassador sidecar hides from the main container: not whether a dependency exists, but where it lives
- Wire an application to a fixed `localhost` address and let a sidecar decide what's really on the other end
- Change where a connection goes by editing only the ambassador container, with zero changes to the application's own manifest
- Judge when a localhost proxy is worth the extra container versus configuring the application to reach the real address directly

## Why this matters

An application that opens a database connection has to know an address: a hostname, a port, credentials. The straightforward way to give it that address is an environment variable pointing at the real thing, which is exactly what every other chapter in this appendix does. That's fine until the real thing needs to change out from under the application for reasons that have nothing to do with the application's own logic: a connection pooler inserted in front of the database, a service mesh sidecar that needs to intercept outbound TCP before it leaves the Pod, a credential-rotation proxy that refreshes short-lived tokens the application was never written to manage, or (the case this chapter uses) decoupling the application's configuration from the cluster's actual topology.

Ambassador is the pattern for that decoupling: a sidecar proxy, reachable at `localhost` from the main container, that owns the decision of where a connection to that local address ends up. The main container's view of the world never changes: it always talks to `127.0.0.1` on some fixed port, which means every one of those cross-cutting concerns can be added, removed, or reconfigured by changing the ambassador alone.

## shipping-service's defaults were already written for this

`shipping-service`'s own `config.py` carries a comment that, read with this pattern in mind, is describing the Ambassador setup directly:

```python
"""Configuration for shipping-service, sourced from environment variables.

In-cluster, the Postgres connection comes from the CloudNativePG-generated
Secret (`capstone-postgres-app`), surfaced as env vars by the helm subchart.
Locally, the defaults reach Postgres on its published port (127.0.0.1:5432).
"""

pg_host: str = "127.0.0.1"
pg_port: int = 5432
pg_user: str = "capstone_app"
pg_password: str = "changeme"
pg_database: str = "capstone"
```

Those defaults exist so a developer running the service outside the cluster, against a Postgres forwarded to their own machine, doesn't have to set any environment variables at all. The same defaults turn out to be exactly what an ambassador needs: the example's `01-deployment.yaml` sets **no Postgres-related environment variables on the `shipping-service` container whatsoever**, and the service still connects, because `127.0.0.1:5432` with `capstone_app` / `changeme` / `capstone` is precisely what its own defaults already say, and the example's disposable Postgres uses those exact credentials.

## A proxy that never sees a password

The ambassador itself, `postgres-ambassador`, is a plain TCP relay, with no Postgres wire protocol awareness and no credentials of its own:

```python
async def handle(client_reader, client_writer):
    server_reader, server_writer = await asyncio.open_connection(
        UPSTREAM_HOST, UPSTREAM_PORT
    )
    await asyncio.gather(
        pipe(client_reader, server_writer),
        pipe(server_reader, client_writer),
    )
```

It listens on `127.0.0.1:5432` inside the shared Pod network namespace, and for every connection it accepts, opens a second connection to the real `patterns-postgres` Service and copies bytes in both directions until either side closes. `shipping-service`'s own Postgres username and password still travel end to end, inside the TCP stream, exactly as if the application had dialed `patterns-postgres` directly: the ambassador never parses them, never stores them, and would work identically in front of any other binary protocol on a TCP port. This is the simplest possible ambassador: a protocol-blind byte pipe. A more capable one might terminate TLS, inject short-lived credentials it fetches from a secrets manager, or rate-limit connections; all of those add logic on top of the same basic shape, a listener on `localhost` and a client to the real backend.

![shipping-service always connecting to 127.0.0.1:5432; the ambassador alone decides which real backend that address reaches]({{ "/assets/diagrams/appendix-09-ambassador.svg" | relative_url }})
*The app's connection target never changes; only the ambassador's upstream does.*

## Bound to localhost by design

`postgres-ambassador` listens on `127.0.0.1:5432`, not `0.0.0.0:5432`. That choice isn't incidental: a Pod's IP address is routable from anywhere else in the cluster network, so a proxy bound to every interface would accept connections from any other Pod, not just its own main container, turning a scoped convenience into an accidental open relay onto `patterns-postgres`. Binding to the loopback interface instead means only processes sharing this Pod's network namespace, which is to say `shipping-service` and nothing else, can ever reach it. The same scoping is why `shipping-service`'s own `pg_host` default of `127.0.0.1` is more than a developer convenience: it's the address range the ambassador pattern depends on existing at all, and it's unreachable from anywhere a cluster-level attacker or a misrouted connection from another namespace could get to it.

## What shipping-service experiences on failure

`shipping-service`'s own `db.py` creates its SQLAlchemy engine with `pool_pre_ping=True`, which checks a pooled connection is still alive with a cheap round trip before handing it to a query: a defense against a connection going stale while idle in the pool, unrelated to the ambassador itself. What the ambassador changes is what happens on the *first* connection attempt, before any pool exists to go stale: `postgres-ambassador`'s `handle()` function calls `client_writer.close()` immediately if its own `asyncio.open_connection()` to the upstream fails, which `asyncpg` on the `shipping-service` side experiences as a connection actively refused at `127.0.0.1:5432`, the same error shape as if nothing were listening there at all. There's no hang, no slow timeout working its way through retry logic. The ambassador fails fast and visibly, which is exactly the behavior `check_db()`'s own readiness check is built to catch within one probe interval.

## The same slot a service mesh already occupies

`order-service`, elsewhere in the §17 data mesh, runs inside an Istio-injected Pod, where `istio-proxy` intercepts every outbound connection transparently via `iptables` rules rather than a hand-dialed `localhost` address. The application doesn't even configure a proxy address, because the interception happens below the application's own socket calls. That's architecturally the same ambassador slot `postgres-ambassador` fills here, just automated and generalized: a sidecar in the same Pod, on the same network namespace, standing between the application and everything it talks to over the network, capable of adding retries, mutual TLS, or observability without the application knowing any of it is happening. `postgres-ambassador`'s hand-rolled, single-purpose version makes that slot visible and inspectable in a way an automatically injected mesh proxy usually isn't: there's one Python script, one upstream address, and every rule a reader can inspect directly in the Pod spec.

## Moving the target without touching the app

Because the upstream address lives entirely in the ambassador container's own configuration, changing it is a one-container edit that never touches the Deployment's application spec:

```bash
kubectl set env deployment/shipping-service -n patterns \
  --containers=postgres-ambassador UPSTREAM_HOST=patterns-postgres-missing.patterns.svc.cluster.local
```

`shipping-service` keeps connecting to `127.0.0.1:5432` exactly as before; it has no way to know or care that the address behind it just changed. `/healthz` starts failing within one probe interval, because `check_db()`'s live `SELECT 1` can no longer complete, while `kubectl describe pod` for the `shipping-service` container shows nothing wrong with it at all: the application's own code and configuration are untouched and correct. The failure is entirely legible as "the ambassador can't reach its upstream," which is the right place for it to be legible, because that's the component that changed.

This is the practical payoff of the pattern: a platform team can rotate which Postgres instance a fleet of services talks to, insert a connection pooler, or add TLS termination, by changing ambassador sidecars across a rollout, without coordinating an application-level config change (and its own review, rollout, and rollback plan) for every service that depends on the database. The blast radius of a wrong ambassador config is also smaller and more obvious than a wrong application config would be: it fails one specific, well-understood thing (this Pod's path to its backend) rather than any of the dozen things a misconfigured application environment variable could plausibly break.

## Kafka is the same shape

`order-service`, elsewhere in the §17 data mesh, reaches Kafka at `capstone-kafka-kafka-bootstrap:9092` the same way `shipping-service` reaches Postgres here: a plain address in its own configuration, with no awareness of what's listening on it. An ambassador in front of that connection would look identical in structure to `postgres-ambassador`: a TCP (or, for a protocol like Kafka's, potentially a smarter) proxy on `localhost`, with `order-service` itself none the wiser about where its bootstrap connection terminates. This appendix doesn't stand up a live Kafka broker to demonstrate that second case (the `mof-patterns` profile has no Strimzi install, and bringing one up only to exercise an ambassador that behaves identically to the Postgres one wouldn't teach anything new); the mechanism this chapter demonstrates generalizes directly.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Design and Build (20%)
> **Competency:** Understand multi-container Pod design, including a proxy sidecar that brokers the main container's outbound connection
> **Drill:** `kubectl get deployment shipping-service -n patterns -o jsonpath='{.spec.template.spec.containers[0].env}'` (confirm it's empty)

> **🤖 Explore with your agent**
>
> "Add a second ambassador container to this Pod that proxies a made-up port for a fictional 'orders-cache' dependency, pointed at the same patterns-postgres Service for simplicity, and show me shipping-service still needs zero environment variables to pick up both."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f ambassador/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f ambassador/00-postgres.yaml
```

## Verification: examples/appendix-patterns/ambassador/

The runnable example deploys `shipping-service` with zero Postgres-related environment variables and a `postgres-ambassador` sidecar proxying `127.0.0.1:5432` to the real `patterns-postgres` Service, confirms `/healthz` succeeds, then repoints only the ambassador's `UPSTREAM_HOST` at a Service name that doesn't exist to show the connection break and recovery without any change to the application container. Full walkthrough in `examples/appendix-patterns/ambassador/README.md`.
