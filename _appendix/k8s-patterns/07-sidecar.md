---
title: "Sidecar"
order: 7
part: "Structural"
description: "Run a helper container beside the app in the same Pod, sharing its network and a volume, using the native sidecar mechanism for a correct startup and shutdown order."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain what two containers in one Pod automatically share: a network namespace and, when declared, a volume
- Declare a native sidecar with `restartPolicy: Always` on an `initContainers` entry, and explain why that's different from a plain second container
- Trace the startup and shutdown order a native sidecar gets, and why that order matters
- Decide when a helper belongs in its own container instead of inside the application's own process

## Why this matters

A Pod is one scheduling unit, but it doesn't have to be one process. Two containers in the same Pod share a network namespace, so one can reach the other at `localhost` with no Service, no DNS lookup, and no network policy in between; they can also share a volume, so one can write a file the other reads. Sidecar is the pattern name for putting a second, independent container in that Pod to do something alongside the main application container, rather than folding that something into the application's own code.

The case for a separate container instead of a library the app imports is isolation: a helper written in a different language, maintained on a different release cadence, or with different resource needs doesn't have to become a dependency of the application's build, and a bug in the helper can't corrupt the application process's own memory. The cost is real too: another container to schedule, another image to patch, another thing that can fail. Structural patterns are worth that cost only when the helper doesn't belong inside the app at all.

## A log/metrics-tailing sidecar

`shipping-service`'s example adds a second container, `probe-tailer`, that polls the app's own `/health` and `/healthz` endpoints over `127.0.0.1` every five seconds and appends a timestamped line to a file on a shared `emptyDir` volume:

```python
import urllib.request

def probe(path):
    with urllib.request.urlopen(f"http://127.0.0.1:8080{path}", timeout=2) as resp:
        return resp.status
```

Nothing about `shipping-service` changes. The sidecar reaches it exactly the way an external client would, over HTTP, except the address is `localhost` instead of a Service name, because the two containers share one network namespace by definition: every container in a Pod sees the same `lo` interface and the same port space. `kubectl exec` into the sidecar and `tail` the shared file, and it reads as a lightweight, self-contained health history:

```bash
kubectl exec -n patterns "$POD" -c probe-tailer -- tail -n 5 /var/log/shipping-service/probe-tail.log
2026-11-01T18:04:12+00:00 health=200 ready=200
2026-11-01T18:04:17+00:00 health=200 ready=200
```

A production log sidecar usually does something with more consequence than polling: Fluent Bit or a vector agent tailing a log file an application writes and forwarding each line to a central aggregator, so the application's own code never has to know where its logs end up. The mechanism this chapter demonstrates (poll or tail, write to a shared volume, read from the other container) is the same regardless of what's actually being collected; `probe-tailer`'s payload is kept simple, so the Pod lifecycle mechanics stay the visible thing.

## The native sidecar: an initContainer with restartPolicy: Always

Before native sidecars existed, "sidecar" meant an ordinary second entry under `containers:`, and that had a real problem: Kubernetes starts every container in that list more or less together, with no ordering guarantee between them, and a main container that depends on its sidecar being ready first (an Istio proxy that has to be programmed before the app's outbound calls will succeed, for instance) had no clean way to wait for it. Shutdown had the opposite problem: when the Pod terminates, every container in `containers:` gets `SIGTERM` at roughly the same moment, so a sidecar could disappear while the main container was still mid-request and depending on it.

The native sidecar mechanism, `restartPolicy: Always` set on an entry in `initContainers:`, fixes both ends. `shipping-service`'s example declares `probe-tailer` this way:

```yaml
initContainers:
  - name: probe-tailer
    restartPolicy: Always
    image: registry.access.redhat.com/ubi10/python-314-minimal:10.2-1791464217
    # ...
```

An init container with `restartPolicy: Always` still starts in init-container order (before the main container), but it never blocks the Pod the way an ordinary init container does: the kubelet starts it, and once it's considered started, moves straight on to starting the main container without waiting for this one to exit, because it isn't supposed to exit. Native sidecars reached beta in Kubernetes 1.29 and graduated to stable in 1.33; the `mof-patterns` profile runs v1.36.5, well past that, so every behavior in this chapter is available as-is.

That ordering guarantee is the whole value proposition. `kubectl get pods -w` during startup shows the sidecar's container reach `Running` while the main container is still `PodInitializing`, confirming the start order without any cooperation from either container's own code. On shutdown, native sidecars are stopped last, after every ordinary container has already exited: `shipping-service` gets `SIGTERM` first, and `probe-tailer` keeps running (and keeps being reachable at `localhost:8080` for as long as the main container is still shutting down) until the main container has gone, at which point the kubelet terminates the sidecar too.

![A native sidecar starting before the app and stopping after it, the reverse of an ordinary second container]({{ "/assets/diagrams/appendix-07-sidecar.svg" | relative_url }})
*restartPolicy: Always on an init container entry inverts the usual race: the sidecar brackets the app's whole lifetime instead of merely running alongside it.*

## Resource accounting is different too

An ordinary init container's resource requests are reserved only while it runs and released the moment it exits, which is why a heavy one-time setup step can ask for more than the steady-state application needs without inflating the Pod's long-term footprint. A native sidecar breaks that assumption by design: because `restartPolicy: Always` keeps it running for the Pod's entire life, its requests stay reserved the whole time, stacked on top of every ordinary container's requests for as long as the Pod exists. `probe-tailer`'s own `resources.requests` (20 millicores, 32Mi) stay modest specifically because they're paid for the Pod's whole lifetime, not just its startup, a cost a heavier native sidecar (a full service-mesh proxy, say) has to account for explicitly when sizing the node pool that hosts it, since every Pod running that mesh now costs its proxy's requests in addition to its own.

Multiple native sidecars, if a Pod had more than one, still start in the order they're listed in `initContainers`, each one's "started" state (not its exit, since it isn't expected to exit) unblocking the next entry below it. Once every native sidecar has reported started, the kubelet moves on to the ordinary containers. A native sidecar can also carry its own readiness probe, and if it does, that probe becomes part of the Pod's aggregate `Ready` condition exactly the way an ordinary container's does: a native sidecar that's `Running` but failing its own readiness check holds the whole Pod out of `Ready`, worth knowing before adding one with a flaky health check of its own.

## Why the reversal matters

The startup half protects a main container that depends on its sidecar: an Envoy or Istio proxy that needs to finish programming routes before the application's first outbound call has somewhere to use that guarantee, because the application container is created only once the proxy sidecar is already up and accepting traffic. The shutdown half protects the opposite dependency: a logging or metrics sidecar that needs to flush or forward whatever the main container produced in its last moments has to still be alive when the main container emits that last burst of output, and `SIGTERM` arriving at both containers simultaneously (the ordinary-container behavior) gives no such guarantee.

`probe-tailer` doesn't strictly need either guarantee: its own failure mode (a dropped probe or two during a race) is harmless. The chapter uses it anyway because the lifecycle contract, not the payload, is the clearest thing to show directly, and a toy sidecar makes the start/stop ordering legible without any other moving part complicating the picture. A sidecar doing something a dropped operation would actually cost (shipping a final log line, releasing a distributed lock, deregistering from a service mesh) is exactly where this mechanism pays for its own complexity.

One more distinction matters here: a native sidecar still counts toward the Pod's total container count for resource accounting and toward `kubectl get pods`'s `READY` column (`2/2`, not `1/1`), but it does **not** count as a regular container for the purposes of Job completion. A Job's main container finishing successfully is what the Job considers done, independent of whether its native sidecars are still running. That distinction matters more in the Behavioral family's BatchJob pattern than here, but it's a direct consequence of the same mechanism this chapter introduces.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Design and Build (20%)
> **Competency:** Understand multi-container Pod design, including a sidecar container and its startup/shutdown ordering relative to the main container
> **Drill:** `kubectl get pod -n patterns -l app.kubernetes.io/name=shipping-service -o jsonpath='{.spec.initContainers[0].restartPolicy}'`

> **🤖 Explore with your agent**
>
> "Change probe-tailer's restartPolicy from Always back to the init-container default (remove the field entirely) and show me what happens to the Pod on the next rollout: does the main container ever reach Running, and why."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f sidecar/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f sidecar/00-postgres.yaml
```

## Verification: examples/appendix-patterns/sidecar/

The runnable example deploys `shipping-service` with `probe-tailer` as a native sidecar, confirms the sidecar reaches `Running` before the main container does, reads the tailed health log over `kubectl exec`, then deletes the Pod while watching both containers' states to confirm the sidecar terminates after the main container, not alongside it. Full walkthrough in `examples/appendix-patterns/sidecar/README.md`.
