---
title: "Init Container"
order: 6
part: "Structural"
description: "Run ordered pre-start setup in a container that must finish before the main container ever starts, worked against notification-service's real Alembic migration."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain why a Pod's main container never starts until every init container has exited successfully
- Read `kubectl describe pod` and `kubectl get pods` output to tell `Init:Error`, `Init:CrashLoopBackOff`, and `PodInitializing` apart
- Wire a real database migration into an init container using the same image as the application it prepares
- Explain the second common use of the pattern, a shared `emptyDir` an init container populates for the main container to read

## Why this matters

Some setup work has to happen exactly once, has to finish before anything else runs, and has no sensible place inside the application's own startup code. A database migration is the clearest case: `notification-service`'s FastAPI process shouldn't be the thing that decides whether to run `alembic upgrade head`, because that decision has nothing to do with serving HTTP requests, and because running it from inside the app risks two replicas racing to apply the same migration concurrently. An init container gives that setup work its own container, its own lifecycle, and a hard guarantee: the kubelet runs every init container to completion, in order, before it starts a single main container.

Structural patterns are about how containers are composed inside one Pod. Init Container is the simplest composition: two containers that never run at the same time, where the second one's existence is conditional on the first one succeeding. That's a stronger guarantee than anything an application can arrange for itself with retries or health checks, because it's enforced by the kubelet, not by code that could have a bug in it.

## Ordering: the Alembic migration gate

`notification-service`'s Containerfile bakes `alembic.ini` and the `alembic/` migrations directory into the same image that runs the FastAPI app. The example's `01-deployment.yaml` adds one `initContainers` entry that runs a migration using that same image, before defining the main container at all:

```yaml
initContainers:
  - name: migrate
    image: notification-service:v1
    imagePullPolicy: Never
    workingDir: /opt/app-root/src
    command: ["alembic", "upgrade", "head"]
    env:
      - name: SERVICE_SCHEMA
        value: notifications
      - name: PG_HOST
        value: patterns-postgres.patterns.svc.cluster.local
      # ...PG_PORT, PG_USER, PG_PASSWORD, PG_DATABASE
```

Same image, same database connection settings as the app container that follows it. The command is different (`alembic upgrade head` instead of `uvicorn`), but there's no separate migration image to build, version, or keep in sync with the app: whatever schema `notification-service`'s SQLAlchemy models declare today is exactly what this migration brings the database to, because they're compiled into the same artifact.

Alembic's own migration runner has no retry loop: `env.py` opens a connection and runs the migration immediately, and if Postgres isn't reachable yet, the process exits non-zero right away. That's a deliberate difference from the app's own startup code (`db.py`'s `init_schema()`, used by other services in this appendix, retries with backoff), and it matters for what a Pod looks like when the dependency isn't ready:

```bash
kubectl get pods -n patterns -w
NAME                                  READY   STATUS                  RESTARTS   AGE
notification-service-7f9d8c7b-x2k9l   0/1     Init:Error              0          4s
notification-service-7f9d8c7b-x2k9l   0/1     Init:CrashLoopBackOff   1          19s
```

`Init:Error` is the init container's most recent attempt failing; `Init:CrashLoopBackOff` is the kubelet backing off between retries, the same backoff behavior a crashing main container gets, just scoped to the init phase. The main container's own status stays `Waiting: PodInitializing` the entire time: it hasn't been created yet, so there's nothing to probe, nothing to log, and no point checking its health. Apply the real Postgres and the next scheduled retry of the `migrate` init container succeeds, the Pod moves to `PodInitializing` one last time while the main container is created, and then to `Running` once the main container passes its startup probe.

![An init container gating the main container's start, with a nonzero exit leaving the Pod stuck PodInitializing]({{ "/assets/diagrams/appendix-06-init-container.svg" | relative_url }})
*The init container's own exit code is the only gate: zero unblocks the main container, nonzero leaves it waiting indefinitely.*

## Why a migration instead of create-all

Most of this appendix's other services (`shipping-service` among them) create their schema with `Base.metadata.create_all`, called from the application's own startup code: a pragmatic, create-if-not-exists approach that's fine for a table whose shape never needs to change after it's first created. `notification-service` graduated off that shortcut specifically because its table *does* need to change over time, and `create_all` has no concept of changing an existing table: it only ever adds what's missing, leaving a column that needs a type change, a new index, or a dropped constraint untouched. Alembic's migration files are different in kind, not just in mechanism: `0001_create_notifications.py` defines both an `upgrade()` and a `downgrade()`, so the schema has a version history a team can move forward or roll back, and a second migration added later composes on top of the first through its `down_revision` pointer rather than overwriting it.

That version history needs somewhere to live, and `notification-service`'s `alembic/env.py` puts it in the service's own schema (`version_table_schema="notifications"`) rather than Postgres's default `public` schema. The §17 data mesh's Postgres instance is shared across several services, each with its own schema; if every service's Alembic kept its version-tracking table in `public`, two services would collide on the same table name and corrupt each other's migration history. Scoping the version table to the same schema the migration targets keeps every service's upgrade history isolated, with no coordination needed between services that happen to share one database instance.

## What actually blocks and what doesn't

An init container's `restartPolicy` inherits the Pod's unless the Kubernetes version and that specific container override it (the native-sidecar mechanism, which gives an individual init container its own `restartPolicy: Always`, is a different pattern covered in its own chapter). For an ordinary init container like `migrate`, the default effectively is "retry on failure, forever, with backoff," because an init container is expected to eventually succeed; there's no concept of an init container that's allowed to permanently fail while the Pod still becomes `Ready`.

Resource requests and limits on an init container are real, not vestigial: the kubelet reserves the init container's own requested CPU and memory while it runs, released once it exits, before the main container's requests are reserved. A heavy one-time migration can legitimately need more memory than the steady-state application container, and an init container is exactly where that extra request belongs, since it's never charged against the Pod once the main container is up.

Multiple init containers run strictly in the order they're listed, each one gating the next. A common structure chains a "wait for dependency" init container ahead of a "run migration" one, so a slow-starting Postgres doesn't get misdiagnosed as a migration failure: the first exits only once it can open a connection at all, and the second assumes that connection already works. This example skips the wait step because Alembic's own connection attempt already produces a clear enough failure signal for the chapter's purpose, but a service with a less legible failure mode (a driver that logs nothing useful on connection refused, say) benefits from splitting the two concerns into two init containers.

## Every new Pod runs it again

An init container isn't a one-time cluster action; it's a per-Pod one. Scale `notification-service` from one replica to three and the `migrate` init container runs three separate times, once per new Pod, against the same database and the same already-applied migration. `alembic upgrade head` is idempotent by design: if the database's version table already records this migration as applied, the command does nothing and exits zero immediately, which is exactly why it's safe to wire into every Pod's startup path rather than treating migrations as a separate, manually-triggered cluster operation. A rolling update behaves the same way: each new-revision Pod created during the rollout reruns the init container, which matters the day a second migration actually does have work to do: the first Pod of the new revision to start applies it, and every other Pod (new or old, mid-rollout) racing to run the same `alembic upgrade head` finds the work already done. Postgres's own row-level locking inside Alembic's transaction is what keeps two simultaneous first-Pods from corrupting each other if a rollout ever creates more than one at once.

## The other half of the pattern: a shared volume

Not every init container talks to a database. The other canonical use, covered in the Kubernetes Patterns literature's own InitContainer example, has nothing to do with ordering against an external dependency and everything to do with handing the main container something it needs that the init container is better positioned to produce: rendering a config file from a template, fetching a TLS certificate, cloning a repository of static assets. The mechanism there is a shared `emptyDir` volume mounted by both containers: the init container writes into it and exits, the main container mounts the same volume and reads from it, and the two containers never need to run concurrently or coordinate beyond that handoff.

`notification-service`'s migration doesn't need this half of the pattern, because the only thing it has to hand the main container is a database state, not a file. A service that generated, say, a per-replica TLS certificate before starting its HTTPS listener would use exactly this shape: an init container writing `/etc/tls/cert.pem` into an `emptyDir`, and the main container mounting the same volume read-only at the path its web server expects. The gating guarantee is identical either way: the main container doesn't start until the init container's write is already on disk, because the init container has already exited by the time the main container's filesystem is assembled.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Design and Build (20%)
> **Competency:** Understand multi-container Pod design, including an init container that must complete before the main container starts
> **Drill:** `kubectl get pod -n patterns -l app.kubernetes.io/name=notification-service -o jsonpath='{.status.initContainerStatuses[0].state}'`

> **🤖 Explore with your agent**
>
> "Add a second init container to notification-service, ahead of the existing migrate one, that only checks Postgres is accepting connections (no migration, just a connectivity check with its own retry loop) and show me both init containers' statuses once the Pod is Running."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f init-container/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f init-container/00-postgres.yaml
```

## Verification: examples/appendix-patterns/init-container/

The runnable example applies `notification-service`'s Deployment before its Postgres exists, to surface `Init:Error` and `Init:CrashLoopBackOff` on the `migrate` init container while the main container sits `Waiting: PodInitializing`, then supplies Postgres and confirms the migration succeeds, the `notifications` schema and table exist, and the main container reaches `Ready`. Full walkthrough in `examples/appendix-patterns/init-container/README.md`.
