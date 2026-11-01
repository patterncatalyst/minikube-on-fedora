---
title: "Env Var Configuration"
order: 18
part: "Configuration"
description: "Populate a container's environment from three sources at once: a literal value in the manifest, a ConfigMap key, and a Secret key, and understand why none of them update a running container."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Set a container's environment variable from a literal value, a `ConfigMap` key (`configMapKeyRef`), and a `Secret` key (`secretKeyRef`), in the same Pod spec
- Explain why a container can't tell, from the inside, which of the three sources populated a given variable
- State precisely when an env var's value is resolved, and why editing the backing ConfigMap or Secret afterward has no visible effect until the container restarts
- Choose which of the three sources fits a given value: fixed constant, environment-shaped setting, or credential

## Why this matters

Every container that does anything useful needs to know things about the world it's running in: which database to connect to, which Kafka cluster to publish to, which credentials to use. None of that belongs in the container image: baking a database hostname into a build artifact means a new image for every environment, and baking a password into one means it's sitting in a registry forever, readable by anyone who can pull the image. Env Var Configuration is the pattern that keeps all of that out of the image and in the Pod spec instead, where it can change without a rebuild.

The twist is that "out of the image" doesn't mean "one mechanism." A Pod spec's `env` block can source each variable from three places at once: a literal string typed directly into the manifest, a key from a `ConfigMap`, or a key from a `Secret`. All three produce the exact same thing from the container's point of view: a plain environment variable, indistinguishable from the others once the process reads it with `os.environ` or `getenv()`. The difference lives entirely in the manifest, in how the variable gets there, not in anything visible once it arrives.

`notification-service`, the §17 data mesh's Kafka-consuming data product, needs both kinds of value this pattern handles: a Postgres connection (the same kind of DB config every data-mesh service needs) and Kafka connection details (a bootstrap address, a topic name, a consumer group, a schema registry URL). The example wires up all three sources against that one container.

## Literal values: the simplest source

A literal is a string typed straight into the Deployment's `env` block, with no indirection at all:

```yaml
env:
  - name: SERVICE_SCHEMA
    value: notifications
  - name: PG_HOST
    value: patterns-postgres.patterns.svc.cluster.local
  - name: PG_PORT
    value: "5432"
```

There's no ConfigMap or Secret involved, no extra resource to create or keep in sync, nothing for RBAC to gate access to. That simplicity is also the limit: a literal can only be changed by editing and reapplying the Deployment, which means it's the right choice exactly when a value is fixed for this service, not something an operator would reasonably want to change independent of a code or manifest change. The Postgres host name here is a good example: it's the in-cluster DNS name of a Service this Deployment was written to talk to, and if that name ever changes, the Deployment almost certainly needs other changes too.

Note the quoted `"5432"`: every environment variable is a string regardless of what YAML type its literal looks like, but YAML itself will happily parse an unquoted `5432` as an integer and hand the Kubernetes API a type it doesn't expect for this field. Quoting removes the ambiguity at the source.

## ConfigMap keys: non-secret, environment-shaped values

A `ConfigMap` holds non-secret configuration as key-value pairs, and `configMapKeyRef` wires one specific key to one specific environment variable:

```yaml
env:
  - name: KAFKA_BOOTSTRAP
    valueFrom:
      configMapKeyRef:
        name: notification-config
        key: kafka_bootstrap
  - name: KAFKA_ORDER_TOPIC
    valueFrom:
      configMapKeyRef:
        name: notification-config
        key: kafka_order_topic
```

The `notification-config` ConfigMap these reference is a separate, ordinary resource:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: notification-config
  namespace: patterns
data:
  kafka_bootstrap: "kafka.invalid:9092"
  kafka_order_topic: "order-placed"
  kafka_group: "notification-service"
  apicurio_url: "http://apicurio.invalid:8080"
```

This is the right home for values that are truly environment-shaped: not secret, but also not fixed the way a literal is. A Kafka bootstrap address is the textbook case: it names infrastructure that changes between a staging cluster and a production one, and an operator should be able to edit it without needing write access to the Deployment, without a new container image, and ideally without even understanding what the application does with it. Separating the ConfigMap from the Deployment also means the same ConfigMap could, in principle, back more than one Pod template, though this example keeps it one-to-one for clarity.

![Three sources feeding one container's environment: a literal value, a ConfigMap key, and a Secret key]({{ "/assets/diagrams/appendix-18-env-var-configuration.svg" | relative_url }})
*SERVICE_SCHEMA is a literal, KAFKA_BOOTSTRAP comes from a ConfigMap key, PG_USER comes from a Secret key; all three land as ordinary env vars.*

## Secret keys: credentials, same mechanism

`secretKeyRef` is the same mechanism as `configMapKeyRef`, pointed at a `Secret` instead:

```yaml
env:
  - name: PG_USER
    valueFrom:
      secretKeyRef:
        name: patterns-postgres-app
        key: username
  - name: PG_PASSWORD
    valueFrom:
      secretKeyRef:
        name: patterns-postgres-app
        key: password
```

The YAML shape is identical to `configMapKeyRef`; only the resource kind changes. What's different is what Kubernetes does around a Secret versus a ConfigMap: RBAC can grant read access to Secrets separately from ConfigMaps (a `Role` that lists ConfigMaps doesn't automatically grant `get` on Secrets), and a cluster with encryption-at-rest configured for its etcd store applies that encryption to Secret data specifically. None of that makes a Secret's contents invisible to someone with `kubectl exec` access to the Pod itself: `kubectl exec notification-service -- env` prints `PG_PASSWORD` in plain text once it's resolved into the container's environment, same as any other variable. A Secret restricts who can read the credential by its name from the Kubernetes API; it does nothing once that credential is sitting in a running container's environment, which is a limitation ConfigurationResource's file-mount option addresses differently.

## When literal, ConfigMap, and Secret aren't enough

Three more `valueFrom` sources exist beyond these: `fieldRef` (expose part of the Pod's own spec or metadata, like its name or namespace, as an env var; `metadata.name` via the downward API is the common one), `resourceFieldRef` (expose a container's own computed resource request or limit, useful for a process that wants to size an internal thread pool or cache off the CPU/memory the scheduler actually granted it), and `envFrom` sources (bulk-expose every key in a ConfigMap or Secret at once, rather than naming them one by one). This chapter's three (literal, ConfigMap key, Secret key) cover the overwhelming majority of real configuration; `envFrom` is worth its own treatment, which ConfigurationResource gives it alongside the file-mount alternative to `valueFrom` entirely.

## Resolution happens once, at container start

Every source in this chapter, regardless of which of the three it is, resolves to a value exactly once: when the kubelet starts the container. From that moment forward, the environment variable is just a string sitting in the container's process environment, with no ongoing connection back to the ConfigMap or Secret it came from. Editing `notification-config` after the Pod is running changes nothing the running container can see:

```bash
kubectl patch configmap notification-config -n patterns \
  --type merge -p '{"data":{"kafka_order_topic":"order-placed-v2"}}'
kubectl exec -n patterns "$POD" -- env | grep KAFKA_ORDER_TOPIC
# still prints the old value
```

The only way to get the new value into the container is to make the container start again:

```bash
kubectl rollout restart deployment/notification-service -n patterns
```

This is the single most important fact to carry out of this chapter, and it's a frequent source of confusion precisely because it's invisible at edit time: `kubectl patch configmap` and `kubectl edit secret` both succeed with no error, giving no signal that the change hasn't actually reached anything yet. Mounted-file consumption, covered in ConfigurationResource, behaves the opposite way: the kubelet syncs a changed value into a running container's filesystem on its own, within roughly a minute, with no restart at all. The two mechanisms look superficially similar (both read from the same ConfigMap and Secret resources), but they behave completely differently once something changes after the Pod is already running, and knowing which one you're using is the difference between a config change that takes effect and one that silently doesn't until someone notices and restarts.

## Choosing a source

The decision isn't really about mechanism; it's about what kind of value you're wiring. A literal fits a value that's fixed for this Deployment and would only ever change alongside a manifest change anyway. A ConfigMap key fits a value that's environment-shaped: not secret, but reasonably something an operator changes independent of a code change, and worth keeping in its own resource so RBAC and audit history can treat it separately from the Deployment. A Secret key fits anything that grants access to something else: a password, a token, a connection string with embedded credentials. Getting this choice right the first time matters more than it looks, because moving a value from one source to another later means touching both the Deployment and whatever created the original value, and because a credential accidentally wired in as a ConfigMap key (rather than a Secret key) is a credential sitting in a resource kind nobody thought to lock down the same way.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Environment, Configuration & Security (25%)
> **Competency:** Configure a Pod's environment from literals, ConfigMap keys, and Secret keys, and understand env var resolution timing
> **Drill:** `kubectl set env deployment/notification-service -n patterns --from=configmap/notification-config KAFKA_GROUP-` (removes one var sourced from the ConfigMap, leaving the rest)

> **🤖 Explore with your agent**
>
> "Add a fourth environment variable to notification-service sourced from the Pod's own downward API (its namespace, via `fieldRef`), and show me the resolved value from inside the running container to confirm it matches `kubectl get pod -o jsonpath='{.metadata.namespace}'`."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f env-var-configuration/02-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f env-var-configuration/00-postgres.yaml
kubectl --context mof-patterns delete -n patterns -f env-var-configuration/01-configmap.yaml
```

## Verification: examples/appendix-patterns/env-var-configuration/

The runnable example deploys `notification-service` with its env block drawing from all three sources, confirms the resolved values from inside the running container, patches the backing ConfigMap to show a running Pod is unaffected, then restarts the Deployment to show the new value finally land. Full walkthrough in `examples/appendix-patterns/env-var-configuration/README.md`.
