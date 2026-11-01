---
title: "Observability and Debugging"
order: 30
part: "CKAD gaps"
description: "kubectl's windows into a running pod: logs (including -p, -c, -f), exec, port-forward, describe, get events, and kubectl debug ephemeral containers."
duration: "25 min"
---

## Learning objectives

By the end of this chapter you can:

- Read a container's logs with `kubectl logs`, including a previous crashed
  instance (`-p`), a specific container in a multi-container pod (`-c`), and a
  live stream (`-f`)
- Run a one-off command or open a shell inside a running container with
  `kubectl exec`
- Reach a pod directly from your workstation with `kubectl port-forward`,
  bypassing the Service layer entirely
- Read `kubectl describe pod` and `kubectl get events` to reconstruct what the
  control plane did to a pod and why
- Attach a `kubectl debug` ephemeral container to a running pod to inspect it
  with tools the pod's own image doesn't carry

## Why this matters

A Kubernetes Pattern tells you how to build something correctly. None of them
tell you what to do when a correctly built thing still misbehaves in
production: a readiness probe that passes locally but fails on the cluster, a
process that logs a stack trace once and never again, a connection that times
out for reasons neither the application nor the manifest explains on their
own. That's a different skill from the one the 29 patterns teach, and CKAD
weights it at 15% of the exam on its own.

The skill is narrower than it sounds. Almost every Kubernetes observability
problem reduces to one of five questions: what did this container print, what
does this container's filesystem and process table actually look like right
now, can I reach this pod's port directly, what did the scheduler and kubelet
decide and when, and (when the running image doesn't carry the tools to
answer any of that) how do I get a debugging tool into a pod without
rebuilding it. `kubectl logs`, `kubectl exec`, `kubectl port-forward`,
`kubectl describe` / `kubectl get events`, and `kubectl debug` answer those
five questions in order, and this chapter works through each against
`shipping-service`, the same data product the Predictable Demands and Env Var
Configuration chapters use.

The running example also adds a second, purely trivial container named
`heartbeat` to the pod. It does nothing related to shipping: it exists only so
`kubectl logs -c` and `kubectl exec -c` have a real second container to pick
between, since a single-container pod can't demonstrate what those flags are
for.

## Logs: plain, by container, following, and after a crash

The baseline command reads whatever a container has written to stdout and
stderr since it started: Kubernetes never reads a container's log files, only
the stream the container runtime captures from those two file descriptors.

```bash
kubectl logs -n patterns "$POD" -c shipping-service
```

`shipping-service` has a FastAPI access log and not much else at this stage of
the appendix, so the output is short. The second container's log stream is
entirely separate, and `-c` is the only way to pick it:

```bash
kubectl logs -n patterns "$POD" -c heartbeat
```

Omit `-c` on a multi-container pod and `kubectl logs` refuses outright,
listing the container names it needs you to choose from. There's no implicit
default once there's more than one container, because there's no safe
assumption about which one you meant.

`-f` turns the same command into a live stream, printing new lines as the
container writes them instead of returning once the current buffer is
exhausted:

```bash
kubectl logs -n patterns "$POD" -c heartbeat -f --since=20s
```

`--since` limits how far back the initial read goes before switching to
streaming mode, which matters on a container that's been running for hours:
without it, `-f` first dumps the entire existing buffer before it starts
following, which is rarely what you want when you're watching for something
that's about to happen.

`-p` (`--previous`) is the one flag that isn't about the current log stream at
all: it reads the log of the container instance that just terminated, not the
one that's running now. This only makes sense immediately after a restart,
because the kubelet keeps exactly one previous instance's logs around, not a
history:

```bash
kubectl exec -n patterns "$POD" -c shipping-service -- kill 1
sleep 3
kubectl get pod -n patterns "$POD"       # RESTARTS is now 1
kubectl logs -n patterns "$POD" -c shipping-service --previous
```

Killing PID 1 inside the container (the `uvicorn` process shipping-service
runs as) ends the container the same way a crash would; the kubelet, watching
the container's exit, restarts it under the pod's default `restartPolicy:
Always`. The new container's log starts empty; `--previous` is the only way to
see what the dead one printed on its way out, and it's the first thing to
reach for on a pod showing a `RESTARTS` count above zero in `kubectl get pod`.
Once a second restart happens, the first instance's logs are gone: `-p`
only ever has the one before the current.

## exec: run something inside the container, right now

`kubectl exec` runs a command inside an already-running container, using the
same mechanism a container runtime uses to start the container's own process,
just a second time inside the same namespaces:

```bash
kubectl exec -n patterns "$POD" -c shipping-service -- env | grep SERVICE_SCHEMA
```

That's a one-off: the command runs, prints its output, and exits, same as
running it locally. Add `-it` and a shell command instead of a one-liner, and
`exec` becomes interactive: a real terminal attached to a process running
inside the container's cgroups and namespaces, useful for anything that needs
more than one command to investigate (walking a filesystem, checking multiple
environment variables, running a tool interactively). `exec` only works
against a container the image already has; it cannot add a binary that isn't
there, which is exactly the gap `kubectl debug` closes later in this chapter.

There is no SSH daemon involved anywhere in this mechanism, and that's a
design property of the platform, not a missing feature: a container never
needs to accept inbound connections to be debuggable, because `exec` is
proxied entirely through the kubelet and the API server, using the same RBAC
rules that gate every other `kubectl` verb. A user with `exec` permission on a
pod can run arbitrary commands inside any container of that pod; a cluster
that grants `exec` broadly is granting a lot more than read access, which is
worth remembering when writing the RBAC Roles this appendix's Access Control
chapter covers.

## port-forward: reach the pod directly, bypassing the Service

Every other chapter in this appendix reaches a service through a Kubernetes
`Service` object, port-forwarded or NodePort-published. `kubectl port-forward`
skips that layer entirely and opens a tunnel straight to one pod's port:

```bash
kubectl port-forward -n patterns "$POD" 8080:8080 &
curl -s http://127.0.0.1:8080/healthz | jq .
kill %1
```

The tunnel is proxied through the kubelet on the node running that specific
pod, not through `kube-proxy` or any Service's virtual IP, which makes it the
right tool for exactly one situation: confirming that one particular pod
behaves correctly, independent of whatever a Service's label selector happens
to be matching right now. If three replicas are running and one of them is
misbehaving, port-forwarding straight to that pod's name is the only way to
be certain which one you're actually talking to: a Service in front of all
three would load-balance you to a different replica on the next request.
`port-forward` is a debugging and development tool, not a production access
pattern: it holds one connection open from your workstation to the kubelet
for as long as the command runs, and it dies the moment that connection drops.

## describe and events: what the control plane decided, and when

`kubectl logs` and `kubectl exec` both answer questions about what's happening
*inside* a container. `kubectl describe pod` and `kubectl get events` answer a
different question: what has the control plane itself done to this pod, and
in what order.

```bash
kubectl describe pod -n patterns "$POD"
```

The output's final section, `Events`, is a chronological list of everything
the scheduler and kubelet have reported about this specific pod: which node it
was scheduled to and when, which images were pulled and how long that took,
which probes have failed and how many times, and any reason a container was
killed or restarted. This is the same mechanism Predictable Demands uses to
diagnose a `CreateContainerConfigError` or a `Pending` pod stuck on a missing
PersistentVolumeClaim: `describe pod`'s Events section is where both of
those failures actually say what's wrong, in plain text, rather than just a
generic failed-state name.

`kubectl describe` only shows events still attached to the object by the time
you run it (events expire out of etcd after about an hour by default), and it
only shows events for the one object you named. `kubectl get events` shows
the namespace's whole event stream at once, which matters when a failure
touches more than one object: a ResourceQuota rejection, for instance, is
reported against the ReplicaSet that tried to create the pod, not against any
pod object, since no pod was ever created to attach the event to:

```bash
kubectl get events -n patterns --sort-by=.metadata.creationTimestamp
```

`--sort-by` matters here: without it, `get events` returns results in
whatever order the API server happens to have them in, which is rarely
chronological once more than a few objects have generated events recently.

## kubectl debug: ephemeral containers for a pod that's already running

Every tool so far works with what the pod's own containers already carry.
`shipping-service`'s runtime image, like most production images, has no
shell utilities beyond what the Python process itself needs: no `curl`, no
`ps`, nothing to poke at the network or process table from the inside. That's
a security property worth keeping (a smaller image has a smaller attack
surface), and it means `kubectl exec -- curl ...` fails outright with
"executable file not found" the moment you need a tool the image never
shipped.

An **ephemeral container** solves this by attaching a brand-new,
throwaway container to a pod that's already running, without restarting
anything else in it:

```bash
kubectl debug -n patterns "$POD" -c probe-net \
  --image=registry.access.redhat.com/ubi10/ubi:10.2-1791444044 \
  -- curl -s http://localhost:8080/health
```

The new container shares the pod's network namespace, so `localhost:8080`
reaches the shipping-service container's port exactly as if the curl had run
from inside it: the ephemeral container is a guest in the same pod, not a
separate one. `--target` goes one step further and shares the named
container's *process* namespace too, which is what makes a tool like `ps` (or,
with no `ps` binary at all, a direct read of `/proc`) show the real
application's PIDs instead of just the ephemeral container's own:

```bash
kubectl debug -n patterns "$POD" -c probe-proc --target=shipping-service \
  --image=registry.access.redhat.com/ubi10/ubi:10.2-1791444044 \
  -- sh -c 'for p in /proc/[0-9]*; do printf "%s %s\n" "${p#/proc/}" "$(cat $p/comm 2>/dev/null)"; done'
```

These two commands are the same pair of probes the §17 data mesh's
`examples/17-capstone/demos/debug-ephemeral.sh` script runs against
`notification-service`: one proving the shared network namespace, the other
proving the shared process namespace with `--target`. The two bookend ideas
look superficially alike, so here's the distinction: an **init container**
(Managed Lifecycle's migration-runner, for instance) runs
once, before the application starts, and is gone by the time anything else in
the pod is up. An **ephemeral container** is attached on demand to a pod
that's already running, mid-flight, specifically for debugging. The two are
the before-start and during-run bookends of the same idea, temporary
containers solving opposite halves of the same problem.

One property of ephemeral containers is easy to miss until it surprises you:
they cannot be removed individually. Once attached, a terminated ephemeral
container stays listed in the pod's `ephemeralContainerStatuses` for the rest
of that pod's life: it consumes no further resources once it exits, but the
record of it having existed doesn't go away until the whole pod does. Running
the same probe twice means two entries, not one updated in place, which is
why both commands above use distinct container names.

![kubectl's five windows into a running pod: logs, exec, port-forward, describe/events, and an ephemeral container attached on demand]({{ "/assets/diagrams/appendix-30-observability-and-debugging.svg" | relative_url }})
*Five separate tools answering five separate questions about the same running pod, none of which require changing the pod's own image.*

> **🎓 CKAD exam lens**
>
> **Domain:** Application Observability and Maintenance (15%)
> **Competency:** Understand `kubectl logs`, `exec`, `port-forward`, `describe`, `get events`, and `kubectl debug` ephemeral containers for troubleshooting a running application
> **Drill:** `kubectl exec -n patterns "$POD" -c shipping-service -- kill 1 && kubectl logs -n patterns "$POD" -c shipping-service --previous`

> **🤖 Explore with your agent**
>
> "Misconfigure shipping-service's readiness probe so it points at the wrong path, apply it, then walk me through diagnosing it using only `kubectl describe pod` and `kubectl get events` (no `kubectl logs` allowed) to show what the control-plane view alone can and can't tell you."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f observability-and-debugging/02-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f observability-and-debugging/00-postgres.yaml
kubectl --context mof-patterns delete -n patterns -f observability-and-debugging/01-configmap.yaml
```

## Verification: examples/appendix-patterns/observability-and-debugging/

The runnable example deploys `shipping-service` with a `heartbeat` sidecar,
exercises `logs` (plain, `-c`, `-f`, and `-p` after a forced restart), `exec`,
`port-forward`, `describe pod` / `get events`, and both `kubectl debug`
ephemeral-container probes from the §17 data mesh's `debug-ephemeral.sh`
against it. Full walkthrough in
`examples/appendix-patterns/observability-and-debugging/README.md`.
