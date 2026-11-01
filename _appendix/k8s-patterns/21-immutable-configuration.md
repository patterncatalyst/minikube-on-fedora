---
title: "Immutable Configuration"
order: 21
part: "Configuration"
description: "Mark a ConfigMap immutable, watch the API server reject an in-place edit, and roll a config change the only way an immutable resource allows: a new name and a new rollout."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Create a ConfigMap with `immutable: true` and explain what the API server does differently once it's set
- Explain why every chapter in this family up to this point has quietly assumed ConfigMaps are mutable, and what changes once they aren't
- Roll a config change forward by creating a new, differently named ConfigMap and updating a Deployment to reference it
- Weigh immutable configuration's safety guarantees against the operational cost of a versioned name for every change

## Why this matters

Every example so far in this family has patched a ConfigMap in place and watched the change propagate, whether instantly (a mounted file) or after a restart (an env var). That workflow is convenient, and it's also the source of a failure mode none of those chapters mentioned: a ConfigMap is a cluster-wide resource that any Pod referencing it by name will pick up, and a mutation to its data has no versioning, no audit trail beyond whatever's in an external change-management system, and no way to tell, from the resource alone, what it looked like five minutes ago. Patch a ConfigMap sitting behind twenty replicas and every one of them either picks up the new value on its own schedule (for mounted files) or keeps running on the old one until an unrelated restart happens to bounce it (for env vars): a rollout nobody declared, with no record that it happened.

Immutable Configuration removes the option that causes this: mark a ConfigMap `immutable: true` and the API server refuses any further write to its `data` or `binaryData` fields, with no exception. A configuration change can no longer be an invisible in-place mutation; it has to be a new resource, referenced by a Deployment update, which means it goes through the same rollout machinery (and the same change history, the same rollback story) as any other Pod template change. The trade is explicit: every config change now needs a new ConfigMap name, which is more ceremony than a quiet patch, in exchange for a guarantee that nothing about a running Pod's configuration can shift out from under it without a visible, auditable Deployment update.

`graphql-gateway` is the worked example, chosen specifically because it's stateless: no Postgres, no schema, nothing beyond the ConfigMap and the Deployment itself, which keeps the version-and-roll mechanism this chapter is actually about from getting lost in unrelated setup.

## Marking a ConfigMap immutable

One field, set at creation:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gateway-config-v1
  namespace: patterns
immutable: true
data:
  service_name: graphql-gateway
  order_rest_url: "http://order-service"
  inventory_grpc_addr: "inventory-service:50051"
```

`immutable` can only be set at creation; there's no way to mark an existing mutable ConfigMap immutable after the fact without deleting and recreating it (which would itself be the same kind of invisible mutation the field exists to prevent, so in practice this limitation pushes teams toward deciding on immutability as a policy for all of their ConfigMaps up front, rather than bolting it onto specific ones reactively). `graphql-gateway`'s Deployment references it the ordinary way, with `envFrom`:

```yaml
envFrom:
  - configMapRef:
      name: gateway-config-v1
```

Nothing about consuming an immutable ConfigMap differs from consuming a mutable one: `envFrom`, `configMapKeyRef`, and volume mounts all work identically either way. The difference only shows up the moment something tries to write to it.

## The rejected patch

```bash
kubectl patch configmap gateway-config-v1 -n patterns \
  --type merge -p '{"data":{"order_rest_url":"http://order-service-v2"}}'
```

The API server rejects this outright, naming the `data` field and the ConfigMap's immutability as the reason. There's no `--force` flag or admission-controller override that makes this succeed short of deleting the ConfigMap first, and deleting a ConfigMap still referenced by a running Deployment is its own hazard, since any Pod that restarts while the ConfigMap is gone fails to resolve its env vars, exactly the `CreateContainerConfigError` the Predictable Demands chapter covers for a ConfigMap that's missing rather than merely immutable.

![ConfigMap v1 and v2, both immutable, with a Deployment's reference moving from one to the other and a rollout following it]({{ "/assets/diagrams/appendix-21-immutable-configuration.svg" | relative_url }})
*The old ConfigMap is never edited; a new one is created, and the Deployment's reference moves to it, triggering an ordinary rolling update.*

## Rolling a change forward

The only path to a new value is a new ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gateway-config-v2
  namespace: patterns
immutable: true
data:
  service_name: graphql-gateway
  order_rest_url: "http://order-service-v2"
  inventory_grpc_addr: "inventory-service:50051"
```

Creating `gateway-config-v2` changes nothing about the running Pod by itself: it's just a new resource, unreferenced, inert. The actual change happens when the Deployment's Pod template is updated to name it instead:

```yaml
envFrom:
  - configMapRef:
      name: gateway-config-v2
```

This is a Pod template change like any other, which means it's an ordinary rolling update: a new ReplicaSet, new Pods created against the new ConfigMap name, old Pods terminated once the new ones pass their readiness probes. `kubectl rollout status deployment/graphql-gateway` reports it exactly the way it would report a container image change, and `kubectl rollout history` and `kubectl rollout undo` both work against it the same way too: a config change made this way is a first-class entry in the Deployment's revision history, not an edit that leaves no trace of what the previous value was or when it changed.

```bash
kubectl exec -n patterns "$NEWPOD" -- env | grep ORDER_REST_URL
# http://order-service-v2
```

Once nothing references `gateway-config-v1` anymore, it's safe to delete, but not before: checking what a Deployment currently references before deleting the ConfigMap it used to point at is the one step worth building a habit around, since deleting a ConfigMap a running Pod still needs produces the same `CreateContainerConfigError` on that Pod's next restart as deleting it was never immutable in the first place.

## Weighing the cost

A versioned ConfigMap name for every change is real overhead that a mutable ConfigMap doesn't have: naming convention to agree on (`-v1`, `-v2`, a content hash, a timestamp; Kubernetes doesn't prescribe one), old versions to track down and clean up once nothing references them, and a Deployment update required for even a one-line config tweak that a quick `kubectl patch` would otherwise have handled in seconds. None of that is free, and a ConfigMap used only by a single developer against a throwaway local Pod rarely needs this guarantee at all.

The guarantee matters most at the other end of the spectrum: a ConfigMap backing a production Deployment with many replicas, where "what changed and when" needs to be answerable from `kubectl rollout history` months later, and where an operator fat-fingering a `kubectl edit configmap` shouldn't be able to silently reconfigure every replica in the Deployment at once. The Kubernetes project's own documentation recommends treating ConfigMaps this way broadly, favoring content-addressed or versioned names even without setting `immutable: true` explicitly, specifically because `immutable: true` also measurably reduces load on the API server's watch machinery at scale: a ConfigMap the API server knows can never change again needs no ongoing watch for mutations, which matters more as a cluster's ConfigMap count grows into the hundreds or thousands. A smaller, single-service deployment is unlikely to notice that difference; a platform team running many Deployments against a shared cluster usually does.

Everything in this chapter applies to `Secret` the same way it applies to `ConfigMap`: `immutable: true` is a field on both resource kinds, with identical semantics: an immutable Secret rejects a `data` or `stringData` patch exactly as an immutable ConfigMap rejects one, and a credential rotation becomes a new Secret name plus a Deployment update, not an in-place edit of the old one. That's a meaningfully stronger guarantee for a credential than for an ordinary config value: an immutable Secret makes it structurally impossible for an operator (or an automated tool with write access) to silently replace a password or token that every Pod referencing it is relying on, which removes an entire class of "who changed the database password and when" incidents at the source. The versioned-name cost is the same one this chapter already covers for ConfigMaps, and a credential-rotation pipeline built around immutable Secrets typically automates exactly that: generate a new Secret under a new name, update the Deployments that reference it, confirm the rollout, then revoke the old credential only once nothing points at its Secret anymore.

An alternative worth knowing exists, even where this chapter doesn't build it out: rather than an immutable ConfigMap holding config values directly, an init container can copy a complete, pre-baked configuration (built into its own image, versioned the same way any container image is) into a shared volume for the main container to read: the same shared-volume mechanism the Configuration Template pattern uses, but copying a finished file instead of rendering one from a template. That version lives and moves with an image tag instead of a ConfigMap name, which suits configuration large or complex enough that a ConfigMap's size limit or key-value shape doesn't fit it well, at the cost of needing a container build and push for every config change instead of just a new Kubernetes resource.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Environment, Configuration & Security (25%)
> **Competency:** Create an immutable ConfigMap, explain why an in-place edit is rejected, and roll a configuration change through a Deployment update
> **Drill:** `kubectl get deployment graphql-gateway -n patterns -o jsonpath='{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}'` (confirms which version a Deployment currently references)

> **🤖 Explore with your agent**
>
> "Create a gateway-config-v3 with one more value changed, roll graphql-gateway onto it, then run `kubectl rollout undo` and show me which ConfigMap name the Deployment reverts to referencing."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f immutable-configuration/04-deployment-v2.yaml
kubectl --context mof-patterns delete configmap gateway-config-v2 -n patterns --ignore-not-found
kubectl --context mof-patterns delete configmap gateway-config-v1 -n patterns --ignore-not-found
```

## Verification: examples/appendix-patterns/immutable-configuration/

The runnable example deploys `graphql-gateway` against an immutable ConfigMap, confirms the API server rejects an in-place patch, creates a second immutable ConfigMap with a changed value, then rolls the Deployment onto it and confirms the new value only reaches the Pod through that rollout. Full walkthrough in `examples/appendix-patterns/immutable-configuration/README.md`.
