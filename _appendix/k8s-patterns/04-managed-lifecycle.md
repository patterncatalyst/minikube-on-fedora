---
title: "Managed Lifecycle"
order: 4
part: "Foundational"
description: "Hook into a container's startup and shutdown with postStart and preStop, and size terminationGracePeriodSeconds so SIGTERM never arrives before a container is ready to receive it."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Attach `postStart` and `preStop` exec hooks to a container and explain when each one actually runs
- Explain why Kubernetes sends `SIGTERM` before `SIGKILL`, and what happens if a process ignores the former
- Size `terminationGracePeriodSeconds` so a `preStop` hook and an application's own shutdown both get to finish
- Trace a Pod deletion from `kubectl delete` through endpoint removal, `preStop`, `SIGTERM`, and process exit

## Why this matters

A container doesn't get to decide when it starts receiving traffic or when it stops existing; Kubernetes decides both, and it does so on a schedule the container has no way to opt out of. The gap between "the process has started" and "the process is actually ready to do useful work" is real for almost every nontrivial service, and so is the gap between "Kubernetes has decided to remove this Pod" and "every in-flight request this Pod was handling has finished." Managed Lifecycle is the set of hooks that let a container participate in both transitions instead of being surprised by them.

Get the startup half wrong and a Pod receives traffic (or gets counted ready) before it can actually serve it, producing errors that have nothing to do with the application code and everything to do with timing. Get the shutdown half wrong and a Pod gets killed with requests still in flight, because nothing told it a termination was coming or gave it time to finish what it started. Both failures are infrastructure problems disguised as application bugs, and both have a declarative fix that never touches the container's source.

## postStart: a hook into container start

`lifecycle.postStart` runs immediately after the container's main process starts, in the same container, sharing its filesystem and network namespace. The kubelet does not report the container as `Running` until `postStart` finishes (or fails), which makes it useful for anything that actually has to happen before probes should start treating the container as alive.

`notification-service`'s example sets a minimal one:

```yaml
lifecycle:
  postStart:
    exec:
      command: ["sh", "-c", "date > /tmp/managed-lifecycle-ready"]
```

Exec into the running Pod and the timestamp is right there:

```bash
kubectl exec -n patterns "$POD" -- cat /tmp/managed-lifecycle-ready
```

A real `postStart` hook typically does something with more consequence: register the instance with an external service discovery system, warm an in-memory cache from a snapshot, or (as the pattern's own literature covers) hold the container back with a fixed `sleep` while a slower piece of startup machinery catches up. The mechanism is identical regardless of what the command does; what matters is that it runs inside the container's lifecycle, gating the kubelet's view of "started," rather than as a best-effort side process the application has to remember to launch itself.

`postStart` has a sharp edge worth knowing before relying on it: there's no ordering guarantee between the hook and the container's main process. Both start at effectively the same moment, which is fine for a hook that only needs to run eventually before the container is considered ready, but wrong for a hook a reader might assume runs strictly *before* `ENTRYPOINT`, the way an init container actually does. And if `postStart` itself fails (a non-zero exit from an `exec` hook, or a non-2xx from an `httpGet` one), the kubelet kills the container outright and lets the Pod's restart policy decide what happens next, exactly as if the main process itself had crashed. A `postStart` hook is not a best-effort nicety; a failing one is as fatal as a crashing application.

## preStop and the shutdown sequence

Deleting a Pod doesn't send `SIGTERM` immediately. Kubernetes runs a sequence, and every step in it matters for a service that doesn't want to drop in-flight requests:

1. The Pod is marked for deletion and removed from every Service's endpoint list. New connections stop arriving at this Pod from that moment.
2. If `lifecycle.preStop` is set, the kubelet runs it and waits for it to finish before doing anything else.
3. Once `preStop` returns (or times out), the kubelet sends `SIGTERM` to the container's main process.
4. If the process hasn't exited once `terminationGracePeriodSeconds` elapses from the start of step 2, the kubelet sends `SIGKILL`, which the process cannot catch, delay, or clean up after.

Step 1 and step 3 aren't simultaneous, and the gap between them is exactly what `preStop` is for. Endpoint removal across a cluster isn't instantaneous: kube-proxy and any mesh sidecars need a moment to propagate the change, and without a deliberate pause a Pod can receive `SIGTERM` while a load balancer somewhere still has a connection open to it. `notification-service`'s example uses a fixed sleep to cover that gap:

```yaml
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 10"]
```

A fixed sleep is a blunt instrument (a service with its own connection-draining logic would call into that instead), but it's a common, workable answer for a process that has no finer-grained way to know when it's safe to stop accepting new work: give the cluster a fixed window to notice the Pod is going away before the signal that actually tells the process to exit.

![The sequence from postStart through delete, preStop, SIGTERM, and shutdown]({{ "/assets/diagrams/appendix-04-managed-lifecycle.svg" | relative_url }})
*postStart gates the start of a container's life; preStop delays SIGTERM long enough for the Service to stop routing new traffic first.*

## SIGTERM and terminationGracePeriodSeconds

Once `SIGTERM` actually arrives, what happens next is up to the application, and this is where `notification-service`'s own code matters. Its FastAPI `lifespan` shutdown phase cancels the background Kafka-consumer task and disposes the database connection pool, a graceful sequence that's visible directly in the container's logs the moment `SIGTERM` lands:

```bash
kubectl logs -f -n patterns "$POD"
# ... (nothing for ~10s while preStop sleeps)
# INFO: Shutting down
# INFO: Waiting for application shutdown.
# INFO: Application shutdown complete.
```

That sequence runs in well under a second once it starts. The ten-second gap before it, visible in the same log stream as a silence, is entirely the `preStop` sleep: nothing has told the process to shut down yet, because `SIGTERM` hasn't been sent.

`terminationGracePeriodSeconds` has to cover both numbers, `preStop`'s duration plus however long the application actually takes to exit once signaled, or the kubelet sends `SIGKILL` before the graceful path finishes:

```yaml
spec:
  terminationGracePeriodSeconds: 30
```

Ten seconds of `preStop` sleep plus a shutdown sequence that finishes in under a second leaves a wide margin inside a thirty-second grace period, which is the right way to size it: generous enough that a slower shutdown under load doesn't get cut off, without being so long that a routine Pod deletion or node drain hangs for minutes. A process that ignores `SIGTERM` entirely (no signal handler, or one that swallows it) still gets killed, it just waits out the full grace period first, which is exactly why sizing this value too generously trades a theoretical safety margin for a very real delay on every single Pod termination in the cluster.

Whether `SIGTERM` reaches the application at all depends on something easy to overlook: which process in the container is PID 1. The kubelet sends the signal to PID 1 only. `notification-service`'s Containerfile runs `uvicorn` directly as the container's entrypoint (`CMD ["uvicorn", "app.main:app", ...]`, the exec form, not a shell string), so `uvicorn` itself is PID 1 and receives `SIGTERM` straight from the kubelet. Wrap that same command in a shell (`CMD uvicorn app.main:app ...`, the shell form) and the shell becomes PID 1 instead, swallowing the signal by default unless the script explicitly traps and forwards it. A graceful shutdown handler is only as good as its ability to actually receive the signal it's written to handle.

This chapter uses `notification-service` without a live Kafka cluster behind it: the demonstration is scoped to the container lifecycle contract itself (hooks, signals, the grace period), which is identical whether or not the service's own background consumer has anything to consume. The background task's one failed connection attempt against a Kafka address that doesn't resolve is harmless background noise in the logs; it never touches `/health` or `/healthz`, both of which depend only on the process and on Postgres.

`preStop` supports the same three mechanisms a probe does: `exec`, `httpGet`, and `tcpSocket`. The Kubernetes Patterns book's own Managed Lifecycle example uses `httpGet` against a dedicated `/shutdown` endpoint that logs the call, which is a cleaner design than a fixed sleep wherever a service can expose one: the hook becomes an explicit, observable signal ("I know I'm being drained") rather than an opaque pause, and its duration can vary with how much work the service actually has in flight instead of a conservative worst case baked into the manifest. `notification-service` has no such endpoint, which is exactly why this example falls back to the blunt instrument: a fixed sleep is the correct default when a service offers nothing more specific, and the right upgrade path if that service later adds its own drain signal.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Design & Build (20%)
> **Competency:** Understand multi-container Pod design and the container lifecycle, including startup and shutdown hooks
> **Drill:** `kubectl get pod -n patterns -l app.kubernetes.io/name=notification-service -o jsonpath='{.items[0].spec.terminationGracePeriodSeconds}'`

> **🤖 Explore with your agent**
>
> "Change notification-service's preStop sleep to 40 seconds without raising terminationGracePeriodSeconds past its current 30, delete the Pod, and show me what happens to the application's own graceful shutdown sequence when the grace period runs out first."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f managed-lifecycle/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f managed-lifecycle/00-postgres.yaml
```

## Verification: examples/appendix-patterns/managed-lifecycle/

The runnable example deploys `notification-service` with both hooks wired in, confirms the `postStart` file lands before any probe succeeds, then times a Pod deletion while tailing logs to show the ten-second `preStop` delay followed by the application's own sub-second graceful shutdown. Full walkthrough in `examples/appendix-patterns/managed-lifecycle/README.md`.
