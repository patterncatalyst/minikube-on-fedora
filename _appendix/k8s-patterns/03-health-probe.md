---
title: "Health Probe"
order: 3
part: "Foundational"
description: "Separate liveness from readiness with startup, liveness, and readiness probes, then add a readiness gate that only an external signal can satisfy."
duration: "25 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain the difference between a liveness probe and a readiness probe, and what each one controls
- Configure a `startupProbe` to protect a slow-booting container from a liveness probe that would otherwise kill it mid-boot
- Read `kubectl get pods` and `kubectl describe pod` to tell a crashed container apart from one that's merely not ready
- Add a `readinessGate` and satisfy it manually, to see how a Pod can be fully running and still not `Ready`

## Why this matters

Kubernetes asks two different questions about a running container, and conflating them is one of the most common ways a cluster misbehaves. "Is this container alive?" governs whether the kubelet should restart it. "Is this container ready for traffic?" governs whether the Service should send it any. A container can be alive and not ready (still loading, or its database is unreachable) and a container can, in principle, answer a trivial readiness check while being functionally broken in every way that matters. The two checks exist because the correct response to each failure is different: restart on the first, stop sending traffic on the second, and neither response is a safe substitute for the other.

`inventory-service` exposes exactly the two endpoints the pattern needs: `/health`, which returns `200` as long as the process can respond at all, and `/healthz`, which returns `200` only if it can reach its Postgres instance and `503` otherwise. That's not an accident of naming. It's the liveness/readiness split made concrete: one endpoint answers "is the process up," the other answers "can this process actually do its job right now."

## Liveness and readiness

The example's Deployment wires both endpoints to their matching probe type:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /healthz
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5
```

The kubelet runs `livenessProbe` on its own schedule and, on repeated failure, kills the container and restarts it (counted as a restart in `kubectl get pods`). The same kubelet runs `readinessProbe` independently, and on failure removes the Pod from every Service's endpoint list, without touching the container at all. Scale the example's backing Postgres to zero and watch both behaviors diverge in real time:

```bash
kubectl scale deployment/patterns-postgres -n patterns --replicas=0
curl http://127.0.0.1:8080/health    # still 200: the process is fine
curl http://127.0.0.1:8080/healthz   # 503: it can't reach Postgres
```

`inventory-service`'s restart count stays at zero the entire time. The Pod simply stops receiving traffic, which is the correct response to a dependency outage: restarting a process that's working perfectly, just unable to reach a downed database, accomplishes nothing except noise in the event log. Scale Postgres back to one replica and readiness recovers on its own, with no intervention, because the readiness probe is just checking the current state, not remembering the last failure.

## Startup probe

A liveness probe with a short `initialDelaySeconds` assumes the container finishes booting quickly. `inventory-service` doesn't boot instantly: FastAPI's lifespan startup creates the Postgres schema if it's missing, seeds demo stock rows, and binds a gRPC server for `CheckStock`, all before `/health` answers anything. A liveness probe that starts checking five seconds in would, on a slow node, kill and restart the container repeatedly before it ever finishes that sequence once, a failure mode that looks exactly like a crash loop but is actually just impatience.

`startupProbe` is the fix: while it's active, the kubelet suppresses both liveness and readiness checks entirely.

```yaml
startupProbe:
  httpGet:
    path: /health
    port: http
  failureThreshold: 30
  periodSeconds: 2
```

Thirty attempts at two-second intervals gives the container up to sixty seconds to answer `/health` even once before liveness takes over. The moment it does, the startup probe steps aside permanently for that container's lifetime, and the regular liveness and readiness probes start running on their own schedules from `initialDelaySeconds` zero. `kubectl describe pod` shows this transition directly: the startup probe's events stop appearing in the log the instant the container reports healthy, replaced by the usual liveness and readiness probe activity.

![A startup probe gates liveness and readiness until the container reports healthy; readiness alone is not enough to join the Service's endpoints if a readiness gate is also set]({{ "/assets/diagrams/appendix-03-health-probe.svg" | relative_url }})
*The startup probe holds liveness and readiness back during boot; once it passes, both the readiness probe and any readiness gate must clear before the Service routes traffic.*

## Readiness gates

A readiness probe only checks what the container itself can observe about itself. Sometimes a Pod's actual readiness depends on something external that no HTTP endpoint inside the container can see, like a sidecar finishing its own setup, or (as in this example) an operational signal that a human or a controller needs to confirm before traffic should arrive. A `readinessGate` adds exactly that: a named condition that must be `True` in the Pod's status before Kubernetes considers the Pod ready, on top of whatever the readiness probe already checks.

```yaml
spec:
  readinessGates:
    - conditionType: "patterns.example.com/InventorySeeded"
```

Apply this and `kubectl get pod -o wide` shows something that looks contradictory at first: `READY 1/1` (both containers pass their own health checks) alongside `READINESS GATES 0/1`. The containers are healthy; the Pod as a whole is not Ready, because nothing has set the gate's condition. In production, a controller watching for confirmation that demo stock finished seeding would patch this; for the example, patch it directly to see the mechanism work:

```bash
kubectl patch "$POD" -n patterns --type='json' --subresource=status \
  -p='[{"op": "add", "path": "/status/conditions/-", "value": {"type": "patterns.example.com/InventorySeeded", "status": "True"}}]'
```

`READINESS GATES` flips to `1/1` and the Pod's overall `Ready` condition goes `True`, joining the Service's endpoints for the first time. Nothing about the container changed; only the external signal did. That's the entire value of a readiness gate: it lets a condition no in-container probe could ever check (a dependency acknowledged, a migration confirmed, an operator's sign-off) gate traffic the same way a failed `/healthz` would.

## The three probe mechanisms

Every probe in this chapter so far uses `httpGet`, which is the natural fit for a service that already exposes an HTTP health endpoint. Kubernetes supports two other mechanisms for workloads that don't:

- **`exec`** runs a command inside the container and treats exit code `0` as success, anything else as failure. This is the right choice for a process with no network listener at all, or where the meaningful health signal is a file on disk or a local socket rather than an HTTP response (the reference pattern's own `stat /tmp/random-generator-ready` readiness check is exactly this).
- **`tcpSocket`** attempts a TCP connection to the given port and treats a successful connection as success, with no awareness of what, if anything, answers on the other end. It's weaker than `httpGet` (a process that accepts a connection but never responds to real requests still passes) but it's the only option for a non-HTTP protocol with no richer health contract of its own.
- **`grpc`** (stable since Kubernetes 1.27) calls the standard [gRPC health checking protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md) against a named service on the given port, which is the correct mechanism for `inventory-service`'s own `CheckStock` endpoint if this example extended probing to the gRPC side rather than only the REST side.

All three share the same tuning fields (`initialDelaySeconds`, `periodSeconds`, `timeoutSeconds`, `failureThreshold`, `successThreshold`), and all three can be attached as a `startupProbe`, `livenessProbe`, or `readinessProbe` interchangeably: the mechanism (how the check runs) and the role (what the result controls) are independent choices. A process behind a protocol with no existing health convention of its own almost always ends up on `exec`, checking something indirect like a ready-marker file, precisely because that's the one mechanism with no assumptions baked in about what's listening on the other end.

`successThreshold` is the field most often set wrong, because its default of `1` is correct for a readiness or startup probe but its only legal value for a liveness probe is also `1`: Kubernetes rejects anything else, because "require two consecutive successes before trusting this process is alive again" doesn't make sense for a check whose failure already means killing the container. `failureThreshold` has the matching asymmetry in the other direction: a low value (one or two) on a readiness probe just removes a flaky Pod from the Service's endpoints for a beat, cheap and reversible, while the same low value on a liveness probe restarts a container over what might be one slow response under transient load. A probe failure also leaves a trace independent of the Pod's current status: `kubectl describe pod` records each one as an `Unhealthy` event with the specific HTTP status or exit code that failed, which is usually the fastest way to tell a probe that's misconfigured (wrong path, wrong port) from an application that's actually unhealthy.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Observability & Maintenance (15%)
> **Competency:** Understand and configure liveness, readiness, and startup probes
> **Drill:** `kubectl get pod -n patterns -l app.kubernetes.io/name=inventory-service -o jsonpath='{.items[0].status.conditions}'`

> **🤖 Explore with your agent**
>
> "Add a second readiness gate to inventory-service that models a cache warm-up check, satisfy both gates in sequence, and show me the Pod's conditions after each one."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f health-probe/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f health-probe/00-postgres.yaml
```

## Verification: examples/appendix-patterns/health-probe/

The runnable example deploys `inventory-service` with all three probe types and the readiness gate, confirms the `READY`/`READINESS GATES` split before and after patching the gate, then scales Postgres to zero and back to show readiness diverge from liveness without a restart. Full walkthrough in `examples/appendix-patterns/health-probe/README.md`.
