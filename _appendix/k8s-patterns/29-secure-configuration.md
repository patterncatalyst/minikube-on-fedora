---
title: "Secure Configuration"
order: 29
part: "Security"
description: "Treat a Secret as a credential, not a ConfigMap with a different name: know what base64 doesn't do, keep credentials out of images and logs, and survey where to go once a raw Secret isn't enough."
duration: "25 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain exactly what encoding a Secret's value as base64 does and doesn't protect against
- Create a Secret with `stringData` and read back its `data`, and explain why `kubectl describe` and `kubectl get -o yaml` show two different things
- Name the two places a credential leaks most often in practice (the image, the logs) and the concrete habit that closes each one
- Describe, at a survey level, what External Secrets Operator, Sealed Secrets, and SOPS each add on top of a raw Kubernetes Secret, and when a team would reach for one

## Why this matters

A `Secret` and a `ConfigMap` are nearly the same Kubernetes object: same API shape, same `data` field, same `configMapKeyRef`/`secretKeyRef` mechanics every earlier chapter in this family already covers. The entire reason `Secret` exists as a separate kind, rather than everyone just using `ConfigMap` for credentials too, is that treating a password differently from a database schema name is a decision worth making explicitly rather than by habit. A schema name leaking into a log line is an inconvenience; a Postgres password leaking the same way is an incident. Secure Configuration is the pattern for making that distinction count for something beyond the resource kind's name: understanding exactly what a `Secret` protects against, where it doesn't protect at all, and what to reach for once a raw `Secret` stops being enough.

`inventory-service`'s Postgres credentials are the worked example, held in their own `inventory-db-credentials` Secret rather than reusing the shared `patterns-postgres-app` credential this appendix's other examples share. That's narrower than this disposable Postgres container can enforce (it only recognizes one role, so both Secrets carry the same values here), but the pattern this chapter demonstrates holds regardless: each service owning a distinctly named Secret, rather than every service in a namespace sharing one, is what makes revoking or rotating one service's credential possible without touching every other service that happens to share it.

## What base64 buys

Create a Secret from a literal value and Kubernetes stores it as base64:

```bash
kubectl --context mof-patterns create secret generic inventory-db-credentials \
  --from-literal=username=capstone_app --from-literal=password=changeme \
  --from-literal=dbname=capstone -n patterns --dry-run=client -o yaml
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: inventory-db-credentials
  namespace: patterns
type: Opaque
data:
  username: Y2Fwc3RvbmVfYXBw
  password: Y2hhbmdlbWU=
  dbname: Y2Fwc3RvbmU=
```

`stringData` is the same thing from the other direction: a field that takes plain text at creation time and lets the API server do the base64 encoding, so the manifest in this chapter's example reads `password: changeme` directly rather than a pre-encoded string nobody can review by eye. Both end up in the same place. What matters is what that place is: base64 is a reversible encoding, not encryption, and decoding it is a one-line command available to anyone, not a specialized attack:

```bash
kubectl --context mof-patterns get secret inventory-db-credentials -n patterns -o jsonpath='{.data.password}' | base64 -d
# changeme
```

`kubectl describe secret` redacts the values, printing byte counts instead of content, which is a real and useful default (it keeps a credential off a terminal someone's screen-sharing or a CI log that runs `kubectl describe` for debugging), but it's a UI convenience in one specific tool, not a property of the Secret itself. `kubectl get -o yaml`, `kubectl get -o jsonpath`, and anything with `get secrets` RBAC permission on the object see the full, trivially decodable value. A `Secret`'s actual protection comes from two places this chapter's earlier siblings already cover: RBAC (AccessControl, scoping exactly who can `get` a given Secret by name) and etcd encryption-at-rest (a cluster-level configuration this appendix's minikube profile doesn't enable, which encrypts Secret data as stored on disk so a stolen etcd backup doesn't hand over every credential in the cluster in plain, decodable form). Without encryption-at-rest configured, a `Secret`'s data sits in etcd no more protected than a `ConfigMap`'s; base64 alone was never the thing doing that job.

## Choosing env or file, for a credential specifically

`EnvVarConfiguration` and `ConfigurationResource` already established the mechanical difference between a `secretKeyRef` env var and a mounted Secret volume, and that difference matters more for a credential than for an ordinary setting. `inventory-service`'s Deployment demonstrates both at once, redundant here so this chapter's checks have both to inspect:

```yaml
env:
  - name: PG_PASSWORD
    valueFrom:
      secretKeyRef:
        name: inventory-db-credentials
        key: password
volumeMounts:
  - name: db-credentials
    mountPath: /etc/inventory/credentials
    readOnly: true
volumes:
  - name: db-credentials
    secret:
      secretName: inventory-db-credentials
      defaultMode: 0400
```

An environment variable is readable by the process that reads it, inherited automatically into every child process that process spawns, and visible to anything with access to `/proc/<pid>/environ` inside the same Linux namespaces. A file mounted at `defaultMode: 0400` has none of that: nothing reads it unless something explicitly opens the path, nothing inherits it into a child process by accident, and the permission bits add a restriction an env var has no equivalent for. For a schema name or a feature flag, that narrower exposure is a nice-to-have at best. For a password, it's close to the entire point: a credential an application reads from a path instead of its environment is choosing to be harder to exfiltrate by accident, not just by a smaller margin but by removing an entire exposure surface (process environment dumps, child-process inheritance) that a file was never going to have.

![A Secret reaching inventory-service two ways (an env var and a 0400-mode file), with the Secret's own object flagged as base64, not encrypted, in etcd]({{ "/assets/diagrams/appendix-29-secure-configuration.svg" | relative_url }})
*Both paths read from the same inventory-db-credentials Secret; the file path narrows exposure the way the chapter's prose describes, and neither path changes what the Secret object itself looks like at rest.*

## Secret types beyond Opaque

Every Secret this appendix has created so far, including this chapter's `inventory-db-credentials`, is `type: Opaque`: an unstructured bag of key-value pairs with no validation beyond what the application reading it chooses to enforce. Kubernetes defines several other built-in types that add validation and a documented shape for common credential patterns. `kubernetes.io/basic-auth` requires exactly `username` and `password` keys, rejecting a Secret missing either at creation time rather than letting an application discover the gap at runtime. `kubernetes.io/tls` requires `tls.crt` and `tls.key`, the shape an Ingress controller or a mesh sidecar expects when a Secret is referenced for TLS termination. `kubernetes.io/dockerconfigjson` holds container registry credentials in the exact shape the kubelet's image pull machinery expects, referenced from a Pod's `imagePullSecrets` rather than mounted into a container at all. None of these change how RBAC or etcd encryption treat the Secret; the type field is purely a validation and intent signal, worth reaching for when a Secret's shape matches one of these patterns exactly, since `kubectl create secret tls` or `kubectl create secret docker-registry` then does the right field-naming automatically instead of leaving it to whoever wrote the YAML by hand.

## Two places a credential leaks in practice

The theory of Secret handling is usually solid by the time a team reaches for Kubernetes at all; the practical leaks happen in two specific, avoidable places. The first is the container image itself: an `ARG` or `ENV` instruction in a `Containerfile` that bakes a credential in at build time persists in that image's layer history forever, pullable by anyone who can pull the image, long after the credential itself has been rotated. `inventory-service`'s own `Containerfile` already gets this right by construction, not by discipline: its multi-stage build copies only compiled dependencies and application code into the runtime stage, with Postgres credentials never touching a build argument or an `ENV` line at all, arriving exclusively through the Secret this chapter creates, at deploy time, never at build time. That's the structural fix worth replicating everywhere: a Containerfile with no `ARG` or `ENV` capable of holding a credential at all can't leak one through its image history, regardless of how careful any individual build invocation is.

The second leak is logging. A connection string that embeds a password (`postgresql://capstone_app:changeme@host/db`, the shape `inventory-service`'s own `database_url` property builds) is a natural thing to log during a connection failure, and an unhandled exception's stack trace is a natural thing to log in full, and either habit puts a credential in a log aggregator, a CI job's console output, or an incident ticket's pasted traceback, outside of Kubernetes entirely and outside of anything RBAC or encryption-at-rest was ever scoped to protect. The concrete habit that closes this is narrower than "be careful with logging": never log a full connection string or a raw exception message from a database client without first confirming neither one can carry the password, and prefer structured logging that names the fields being logged explicitly (`host`, `port`, `database`) over an f-string that happens to interpolate an object's `__repr__` and might include more than intended.

## Rotation and the immutable Secret

`ImmutableConfiguration`'s `immutable: true` field applies to `Secret` exactly as it does to `ConfigMap`, and for a credential specifically, it closes a gap that matters more than it does for an ordinary setting: without it, anyone (or anything) with write access to a Secret can silently replace a password every Pod referencing it is relying on, with no record beyond whatever external change-management system happened to be watching. A credential rotation workflow built around immutable Secrets looks like: create a new, differently-named Secret with the new password already set in Postgres, update the Deployment to reference the new name (an ordinary rolling update, with the same rollback story every other Pod template change gets), confirm every Pod has rolled, and only then revoke the old password. Nothing about that workflow is specific to Secure Configuration as a pattern distinct from ImmutableConfiguration; it's the same mechanism, applied to a resource kind where "nobody can silently swap value" is a security property, not a convenience.

## Beyond a raw Secret

Everything this chapter covers works with Kubernetes `Secret` exactly as it ships, and for a self-contained cluster where credentials are created with `kubectl` or a Helm chart's templating, that's often enough. Three tools exist for the gap that opens once credentials need to live somewhere outside the cluster itself, or need to be safe to commit to a Git repository the way the rest of a GitOps-managed manifest set already is; none of them is installed in this appendix's example, and the survey here goes only deep enough to know which one solves which problem.

**External Secrets Operator** syncs credentials from an external secrets manager (HashiCorp Vault, AWS Secrets Manager, and similar) into ordinary Kubernetes Secrets, via a CRD and a controller that polls the external source and keeps the in-cluster Secret current. It fits a team that already has credentials living in a dedicated secrets manager (for rotation, audit, and access control the secrets manager already handles well) and wants Kubernetes workloads to consume them as ordinary Secrets without duplicating that management inside the cluster.

**Sealed Secrets** solves the opposite problem: a Secret's plain manifest can't be committed to a Git repository safely, since anyone with repo read access could read every credential in it. Sealed Secrets encrypts a Secret's values client-side into a `SealedSecret` custom resource, safe to commit because only a controller running inside the target cluster (holding the matching private key) can decrypt it back into a real Secret. It fits a GitOps workflow where every other manifest is already committed and reconciled automatically, and a Secret is the one resource kind that workflow can't otherwise handle the same way.

**SOPS** (Secrets OPerationS) takes a third approach: it encrypts individual values inside an otherwise-ordinary YAML or JSON file, using a key held in a KMS, PGP, or age key, leaving the file's structure (and any non-secret values in it) readable in plain text while only the sensitive fields are ciphertext. A deployment pipeline decrypts the file at apply time, using the same key. It fits a team that wants one file format shared across secrets and ordinary configuration, with just the sensitive fields protected, rather than a dedicated custom resource exclusively for credentials.

All three answer the same underlying question (how does a credential get into the cluster without ever sitting in a Git repository or a CI variable in plain, decryptable-by-anyone form) with a different point in the pipeline where the encryption happens. Picking among them is a question of what's already in a team's toolchain, not a question this chapter's example needs to settle by installing one.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Environment, Configuration & Security (25%)
> **Competency:** Create a Secret with stringData, read it back as base64 and as a decoded value, and explain what base64 does and doesn't protect
> **Drill:** `kubectl get secret inventory-db-credentials -n patterns -o jsonpath='{.data.username}' | base64 -d` (confirms the value is a one-line decode away, not encrypted)

> **🤖 Explore with your agent**
>
> "Create inventory-db-credentials as a kubernetes.io/basic-auth typed Secret instead of Opaque, and show me what error kubectl returns if I try to create it missing the required password key."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f secure-configuration/02-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f secure-configuration/01-secret.yaml
kubectl --context mof-patterns delete -n patterns -f secure-configuration/00-postgres.yaml
```

## Verification: examples/appendix-patterns/secure-configuration/

The runnable example creates `inventory-db-credentials` with `stringData`, decodes it back to confirm base64 isn't encryption, deploys `inventory-service` consuming the same Secret both as an env var and as a 0400-mode mounted file, and confirms the file's permission bits from inside the running container. Full walkthrough in `examples/appendix-patterns/secure-configuration/README.md`.
