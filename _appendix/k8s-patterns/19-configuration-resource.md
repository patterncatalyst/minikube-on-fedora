---
title: "Configuration Resource"
order: 19
part: "Configuration"
description: "Bulk-expose a ConfigMap or Secret as environment variables with envFrom, mount the same resource as files at the same time, and see why one half updates live and the other doesn't."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Bulk-expose every key of a ConfigMap or Secret as environment variables with `envFrom`, instead of naming each key individually
- Mount a ConfigMap or Secret as a volume and read its keys as files inside a container
- Explain why `envFrom` silently drops a key that isn't a valid environment variable name, and where to look when it does
- State why a mounted file updates on its own within roughly a minute of a ConfigMap edit, while a bulk-exposed env var never does

## Why this matters

EnvVarConfiguration's explicit wiring works one key at a time: one `configMapKeyRef`, one env var. That's precise, but it doesn't scale past a handful of settings, and it means every new config value needs a matching line added to the Deployment. Configuration Resource is the pattern for treating an entire ConfigMap or Secret as a single configuration unit instead of a bag of keys to wire individually, consumed in whichever of two shapes the application actually needs: a flat set of environment variables, or a directory of files on disk.

Most applications only need one of those two shapes. A twelve-factor-style process reads its config from the environment and is done. A process built around a config file (an `.ini`, a `.properties` file, anything a library expects to `open()` from a path) needs the file shape instead, and no amount of env vars substitutes for it. The useful case this chapter actually works through is the one where a single resource needs to reach a container both ways at once, because different parts of a deployment's tooling expect different shapes from the same underlying configuration.

`payment-service` is the worked example: a ConfigMap and a Secret, each one bulk-exposed as environment variables and simultaneously mounted as files in the same Pod.

## envFrom: every key, one line

`envFrom` replaces a list of individual `env.valueFrom` entries with a single reference to an entire ConfigMap or Secret:

```yaml
envFrom:
  - configMapRef:
      name: payment-config
  - secretRef:
      name: payment-pg-credentials
```

Every key in `payment-config` becomes an environment variable named exactly after that key (no uppercasing, no transformation), and likewise for every key in `payment-pg-credentials`. `payment-config` holds three keys that happen to match `payment-service`'s own Settings field names:

```yaml
data:
  service_schema: payments
  pg_host: patterns-postgres.patterns.svc.cluster.local
  pg_port: "5432"
```

That alignment isn't an accident; it's what makes `envFrom` worth using instead of EnvVarConfiguration's per-key wiring. When a ConfigMap or Secret's keys already match the names an application's configuration loader expects, `envFrom` turns adding a new setting into editing one resource rather than editing both the resource and the Deployment that references it. The cost is precision: a typo'd or unwanted key in the ConfigMap becomes an environment variable in the container whether anyone meant it to or not, with no per-key filter available on the Deployment side (a `prefix` field exists to namespace the bulk-exposed names, but it has no inverse: there's no way to bulk-expose only some keys).

## The key envFrom can't expose

`payment-config` has a fourth key:

```yaml
data:
  payment-service.conf: |
    [payment-service]
    schema=payments
    note=delivered as a file for tooling that expects a config path, not an env var
```

`payment-service.conf` contains a dot, which makes it an invalid POSIX environment variable name. `envFrom` doesn't fail the Pod over this: the kubelet skips the invalid key and raises a Warning event on the Pod, visible with `kubectl describe pod`, while every other valid key is still exposed normally. That's worth knowing precisely because it fails quietly from the application's point of view: a process that expected a `PAYMENT_SERVICE_CONF` variable (which was never going to be valid regardless) never sees it, and the only signal is an event easy to miss unless something is actively watching for it.

This is also the reason the same ConfigMap gets mounted as a volume in the same Deployment: the file-shaped key reaches the container through the mechanism built for exactly this, instead of being forced into an env var shape it can't take.

![The same ConfigMap and the same Secret, each reaching the container as bulk env vars and as a mounted file]({{ "/assets/diagrams/appendix-19-configuration-resource.svg" | relative_url }})
*envFrom bulk-exposes every valid key as an env var; a volumeMount delivers the same resource's keys as files, including the one envFrom had to skip.*

## Mounting the same resource as files

A `configMap` or `secret` volume projects one key per file, named after the key by default (or renamed with `items`):

```yaml
volumes:
  - name: payment-config-file
    configMap:
      name: payment-config
      items:
        - key: payment-service.conf
          path: payment-service.conf
      defaultMode: 0400
  - name: payment-pg-password-file
    secret:
      secretName: payment-pg-credentials
      items:
        - key: pg_password
          path: pg_password
      defaultMode: 0400
```

`defaultMode: 0400` sets the file's permission bits inside the container: readable by its owning UID only, not writable by anyone and not readable by anyone else, which is the same default a well-configured SSH private key or TLS certificate file would use. `kubectl exec payment-service -- ls -l /config/app/payment-service.conf` confirms the mode landed as `-r--------`.

Mounting `pg_password` as a file alongside bulk-exposing it as an env var looks redundant, and functionally it is here, but it demonstrates a real difference in exposure. An environment variable is visible to the process that reads it and inherited by default into every child process that process spawns, and it's readable by anything with access to `/proc/<pid>/environ` inside the same Linux namespaces. A file has neither property: nothing reads it unless it explicitly opens the path, nothing inherits it automatically, and the mode bits add a second, independent restriction an env var has no equivalent for. A production credential that an application reads from a path instead of its environment is choosing the narrower exposure, and the ConfigurationResource pattern is what makes that choice available without changing how the Secret itself is created.

## Two update models, same underlying resources

Patch the ConfigMap's file-shaped key and the mounted file updates on its own:

```bash
kubectl patch configmap payment-config -n patterns --type merge \
  -p '{"data":{"payment-service.conf":"[payment-service]\nschema=payments\nnote=updated in place\n"}}'
```

Within roughly a minute (the kubelet's sync period for projected ConfigMap and Secret volumes), `cat /config/app/payment-service.conf` inside the running container shows the new content, with no restart, no rollout, nothing beyond the patch itself. Patch one of the bulk-exposed keys instead and nothing changes in the running container's environment at all, for exactly the reason EnvVarConfiguration already established: env vars are resolved once, at container start, and a mounted file is the only one of the two mechanisms the kubelet keeps in sync afterward.

This asymmetry is easy to get backward from intuition alone, since both mechanisms read from the same ConfigMap. A team that assumes env vars will pick up a config change the way a mounted file does will ship a change that silently doesn't take effect until something forces a restart; a team that assumes a mounted file needs an explicit restart the way an env var does will over-engineer a rollout for a change the kubelet was already going to propagate on its own. Knowing which consumption mode a given setting uses, not just which ConfigMap it comes from, is the actual operational knowledge this pattern is testing.

## The subPath exception

There's one way to mount a ConfigMap or Secret as a file that doesn't get the live update this chapter just demonstrated: `volumeMounts.subPath`. Mounting a single key into an existing directory (so it doesn't overwrite the directory's other contents) requires `subPath`, and the kubelet's live-sync mechanism for projected volumes works by atomically swapping a symlinked directory, a trick that only works at the directory level. A `subPath` mount pins the container to a specific file inside that directory tree at mount time and never re-resolves it, so a ConfigMap change never reaches a `subPath`-mounted file no matter how long you wait. `payment-service.conf` in this example is mounted at the directory level (`/config/app`, no `subPath`), which is exactly why it updates live; a service that needs to add a single file into a directory that already has other content unrelated to Kubernetes would lose that update behavior the moment `subPath` enters the picture, and has no mechanism-level way to get it back short of restructuring the mount.

## Resource limits worth knowing

A ConfigMap or Secret is stored as a single object in etcd, and etcd enforces a default 1MiB limit per object (`--max-request-bytes`, rarely raised in practice). That's generous for env-var-shaped config and for most file-shaped config, but it rules out ConfigMaps as a place to store anything resembling an application artifact, a large certificate bundle, or a sizable dataset: those belong on a PersistentVolumeClaim or in the container image itself, not squeezed into a ConfigMap because the pattern happens to be convenient. `envFrom` also accepts an optional `prefix` field, which namespaces every bulk-exposed key under a common prefix (`prefix: PAY_` would turn `pg_host` into `PAY_pg_host`), useful mainly for avoiding a collision when two `envFrom` sources on the same container happen to share a key name (not needed in this example, since `payment-config`'s keys and `payment-pg-credentials`'s keys don't overlap), but worth knowing exists before reaching for per-key renaming instead.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Environment, Configuration & Security (25%)
> **Competency:** Bulk-expose a ConfigMap or Secret with envFrom and mount the same resource as a volume; reason about which consumption mode updates live
> **Drill:** `kubectl exec -n patterns "$POD" -- env | grep -c '^pg_'` (counts the bulk-exposed Postgres variables, confirming envFrom landed all three)

> **🤖 Explore with your agent**
>
> "Add a fifth key to payment-config that's also an invalid environment variable name, apply it, and show me the exact Warning event text the kubelet raises for both skipped keys on the next Pod restart."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f configuration-resource/02-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f configuration-resource/00-postgres.yaml
kubectl --context mof-patterns delete -n patterns -f configuration-resource/01-configmap.yaml
```

## Verification: examples/appendix-patterns/configuration-resource/

The runnable example deploys `payment-service` with a ConfigMap and a Secret each bulk-exposed via `envFrom` and mounted as files, confirms the skipped-key Warning event, checks the mounted files' permissions, then patches the file-shaped ConfigMap key to show the live update the bulk-exposed env vars never get. Full walkthrough in `examples/appendix-patterns/configuration-resource/README.md`.
