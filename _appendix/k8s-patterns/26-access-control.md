---
title: "Access Control"
order: 26
part: "Security"
description: "Give a workload its own ServiceAccount, grant it exactly the ConfigMap and Secret reads it needs with a Role and RoleBinding, and prove the boundary with kubectl auth can-i."
duration: "25 min"
---

## Learning objectives

By the end of this chapter you can:

- Create a dedicated `ServiceAccount` for a workload instead of letting it run under its namespace's `default` account
- Write a `Role` scoped to exactly the resources a workload needs, using `resourceNames` to name individual objects rather than every object of a kind
- Bind a `Role` to a `ServiceAccount` with a `RoleBinding`, and explain when a `ClusterRole` belongs in a namespaced binding instead of a cluster-wide one
- Prove a permission boundary with `kubectl auth can-i --as`, including the one case where `resourceNames` quietly stops working

## Why this matters

Every Pod in a Kubernetes cluster authenticates to the API server as something: a user, or a `ServiceAccount`. Leave `serviceAccountName` off a Pod spec and Kubernetes doesn't leave the field empty, it fills in `default`, the one `ServiceAccount` every namespace already has. That account starts with no RBAC grants of its own, but it's shared by every Pod in the namespace that doesn't ask for something else, which means a Role accidentally bound to `default` grants its permissions to everything running there, not to the one workload it was written for. Access Control is the pattern for closing that gap: give a workload its own `ServiceAccount`, grant that one account exactly what it needs with a `Role`, and leave `default` with nothing bound to it at all.

The stakes are concrete for a workload like `payment-service`. It has no business listing every Secret in the `patterns` namespace, watching Pods, or reading another service's ConfigMap, and if its container is ever compromised (a dependency vulnerability, a deserialization bug, anything that gets an attacker a shell), the blast radius of that compromise is bounded by exactly what its `ServiceAccount` can do against the Kubernetes API. A `ServiceAccount` token mounted into a Pod by default is a credential like any other: scope it the way you'd scope a database role, to the minimum a legitimate workload could ever need, not to whatever happened to be convenient to grant.

`payment-service` is the worked example: a dedicated `ServiceAccount` that can read its own `payment-config` ConfigMap and its own Postgres credentials Secret, and nothing else in the namespace.

## ServiceAccount: an identity, not a permission

A `ServiceAccount` by itself grants nothing. Creating one is a single, almost content-free manifest:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: payment-service
  namespace: patterns
```

What this buys is an identity the API server can distinguish from every other workload's identity: `system:serviceaccount:patterns:payment-service`, the exact string RBAC rules and `kubectl auth can-i --as` both key on. A Pod that sets `serviceAccountName: payment-service` gets a token for this identity mounted at `/var/run/secrets/kubernetes.io/serviceaccount/token`, refreshed automatically by the kubelet (a projected, time-bound token since Kubernetes 1.22, not the long-lived static token older clusters used), and every request that container makes to the Kubernetes API carries that token, evaluated against whatever RBAC rules are bound to it. Until something binds a `Role` to this `ServiceAccount`, it can do nothing: creating the identity and granting it permissions are two separate steps, by design, because an identity with zero attached permissions is the safe default to fall back to while the permissions are being worked out.

## Role: naming exactly what's allowed

A `Role` is a namespaced list of rules, each one a group of API resources, verbs, and optionally the specific object names those verbs apply to:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: payment-service-reader
  namespace: patterns
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["payment-config"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["patterns-postgres-app"]
    verbs: ["get"]
```

`resourceNames` is what turns "can read ConfigMaps" into "can read this one ConfigMap." Without it, a rule granting `get` on `configmaps` would let the bound identity read every ConfigMap in the namespace by name, which is already broader than most workloads need; with it, the rule only matches a request for `payment-config` specifically, and a request for any other ConfigMap in the same namespace is denied by this rule exactly as if the rule didn't exist. The same scoping applies to the Secret rule: `payment-service-reader` can fetch `patterns-postgres-app` and nothing else, not even another Secret sitting right next to it in the same namespace.

A `RoleBinding` is what connects this `Role` to the `ServiceAccount`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: payment-service-reader-binding
  namespace: patterns
subjects:
  - kind: ServiceAccount
    name: payment-service
    namespace: patterns
roleRef:
  kind: Role
  name: payment-service-reader
  apiGroup: rbac.authorization.k8s.io
```

Both the `Role` and the `RoleBinding` live in the `patterns` namespace, and that's not incidental: a `Role` only grants permissions within the namespace it's created in, regardless of which namespace the `ServiceAccount` it's bound to lives in (they usually match, as here, but RBAC doesn't require it). A `ServiceAccount` in `patterns` with this binding has exactly the permissions this `Role` lists, inside `patterns`, and no permissions anywhere else in the cluster at all.

![A ServiceAccount, bound by a RoleBinding to a Role naming two specific resources, with an unnamed Secret left outside the grant]({{ "/assets/diagrams/appendix-26-access-control.svg" | relative_url }})
*`payment-service`'s ServiceAccount reaches `payment-config` and `patterns-postgres-app` by name through its Role; `other-team-secret` is never named, so no rule matches a request for it.*

## The gotcha: resourceNames doesn't restrict list or watch

The scoping `resourceNames` provides has a sharp edge documented in the Kubernetes reference but easy to miss until it bites: `resourceNames` only restricts verbs that name a single object directly, `get`, `update`, `patch`, `delete`. It has no effect at all on `list` or `watch`, because those verbs don't take an object name as part of the request; they return a collection, and RBAC has no way to filter a collection response down to specific names after the fact. A rule written as:

```yaml
resources: ["configmaps"]
resourceNames: ["payment-config"]
verbs: ["get", "list", "watch"]
```

looks like it scopes `list` and `watch` to `payment-config` the same way it scopes `get`, but it doesn't: granting `list` here grants `list` on every ConfigMap in the namespace, with `resourceNames` ignored entirely for that verb. `payment-service-reader` above grants only `get`, for exactly this reason: a workload that only ever needs to fetch one named ConfigMap and one named Secret by `get` never needs `list` or `watch` on either resource kind, and adding those verbs "just in case" widens the grant to the entire namespace's ConfigMaps and Secrets the moment `resourceNames` stops doing anything.

## ClusterRole and ClusterRoleBinding: when the scope changes

A `Role` and a `RoleBinding` are both namespaced, which is the right shape for `payment-service`: everything it needs to read lives in `patterns`, and it never needs to touch another namespace or a cluster-scoped resource like a `Node` or a `PersistentVolume`. A `ClusterRole` is the cluster-scoped equivalent, used for two different reasons that are worth telling apart. The first is a rule that targets a resource with no namespace at all (`nodes`, `persistentvolumes`, `namespaces` themselves), which can't be expressed as a `Role` rule for exactly that reason. The second is reuse: a common set of rules (Kubernetes ships a built-in `view` `ClusterRole`, covering read-only access to most namespaced resources) that's useful to grant repeatedly across many namespaces without retyping the same rule list in a `Role` for each one.

That second case has a subtlety worth knowing before the exam asks about it: binding a `ClusterRole` with a `ClusterRoleBinding` grants it everywhere in the cluster, but binding the exact same `ClusterRole` with a namespaced `RoleBinding` instead scopes the grant to that one namespace only:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ops-readonly-binding
  namespace: patterns
subjects:
  - kind: ServiceAccount
    name: ops-readonly
    namespace: patterns
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
```

`roleRef` can name a `ClusterRole` from a `RoleBinding`, and when it does, the permissions that `ClusterRole` lists apply only within the `RoleBinding`'s own namespace. The `ops-readonly` `ServiceAccount` here gets the built-in `view` role's entire read-only rule set, but confined to `patterns`: it can list Pods and read ConfigMaps in `patterns`, and has nothing at all in `default` or any other namespace, even though `view` itself is a cluster-scoped object. This is the standard way to reuse a well-tested rule set across many namespaces without ever granting it cluster-wide, and it's a different outcome from a `ClusterRoleBinding` even though both reference the identical `ClusterRole`.

## Hardening the default ServiceAccount

Every namespace's `default` `ServiceAccount` exists whether anything uses it or not, and by default a Pod that doesn't set `serviceAccountName` gets its token mounted the same way a Pod that explicitly asked for API access would. Most workloads, `payment-service` included, never call the Kubernetes API from inside their own process: FastAPI serving HTTP and talking to Postgres has no reason to hold a live token to the API server at all, and a mounted token that's never read is still a credential sitting on disk, reachable by anything that gets a shell in that container. `automountServiceAccountToken: false`, set on the `ServiceAccount` itself or overridden per-Pod, stops the kubelet from projecting the token into the Pod in the first place:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: payment-service
  namespace: patterns
automountServiceAccountToken: false
```

There's a real tension here, not a contradiction: `kubectl auth can-i --as` evaluates RBAC rules directly against the identity string, with no dependency on whether any Pod has that identity's token mounted, so turning automounting off wouldn't change anything about this chapter's verification steps. The worked example below leaves automounting on anyway, matching every other Deployment in this appendix, to keep the one difference under test here to the Role's scoping rather than mixing in a second control at the same time. A production `payment-service` that never calls the Kubernetes API from inside its own container is better off with automounting off entirely, closing the question of what the token could do rather than relying on the Role being airtight. The two controls aren't alternatives, they're layers: a tightly scoped Role limits what a leaked token can reach, and `automountServiceAccountToken: false` removes the token from a container that never needed one to begin with.

## Reading a Forbidden error, and auditing with --list

A denied request doesn't fail silently: the API server's response names the identity, the verb, the resource, and the namespace involved, which is usually enough to tell whether a Role is missing a rule or whether the request is being made as the wrong identity entirely:

```
Error from server (Forbidden): configmaps "other-team-config" is forbidden:
User "system:serviceaccount:patterns:payment-service" cannot get resource "configmaps"
in API group "" in the namespace "patterns"
```

Every field in that sentence is worth reading literally before assuming the Role is wrong: the identity string confirms which `ServiceAccount` actually made the request (a Pod running under the wrong `serviceAccountName`, a stale token, or a typo in `--as` all produce a Forbidden error that looks like a missing permission but isn't one), and the resource and namespace confirm the request landed where expected. `kubectl auth can-i --as` tests one rule at a time, which is precise but slow for a broader audit; `kubectl auth can-i --list --as=system:serviceaccount:patterns:payment-service -n patterns` instead prints every resource and verb combination that identity is currently allowed, a single command that answers "what can this thing actually do" without guessing which specific check to run next. Running that audit after writing a new Role is a cheap habit that catches an over-broad grant (an unexpected verb, a resource nobody meant to include) before it ships, rather than after.

## ServiceAccount tokens since Kubernetes 1.24

Older Kubernetes material (and some still-circulating exam prep) describes a `ServiceAccount` as automatically owning a long-lived `Secret` holding its token, created the moment the `ServiceAccount` itself was created and valid indefinitely. That stopped being the default behavior in Kubernetes 1.24: a `ServiceAccount` no longer auto-provisions a token `Secret` at all, and the token a Pod receives today is a bound, time-limited JWT, requested on the Pod's behalf through the `TokenRequest` API and delivered via a projected volume rather than a static `Secret` mount. The practical difference is that a leaked token from a modern cluster expires (the kubelet refreshes it before that happens, for as long as the Pod is running, but a copy made by an attacker and used later does not get refreshed), where an old-style `Secret`-backed token was valid until the `ServiceAccount` or the `Secret` was deleted outright. `kubectl create token payment-service -n patterns --duration=10m` requests a short-lived token directly, the same mechanism the kubelet uses internally, and is the modern replacement for digging a token out of an auto-created `Secret` that, on a current cluster, no longer exists to dig out.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Environment, Configuration & Security (25%)
> **Competency:** Create a ServiceAccount, write a namespaced Role scoped by resourceNames, bind it with a RoleBinding, and verify the result with kubectl auth can-i
> **Drill:** `kubectl auth can-i get configmap/other-team-config --as=system:serviceaccount:patterns:payment-service -n patterns` (expect `no`, since the Role never names it)

> **🤖 Explore with your agent**
>
> "Add a third resourceNames entry to payment-service-reader's secrets rule for a new payment-tls Secret, apply it, and show me the kubectl auth can-i check that confirms payment-service can now read it while other-team-secret is still denied."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f access-control/06-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f access-control/05-ops-readonly.yaml
kubectl --context mof-patterns delete -n patterns -f access-control/04-rbac.yaml
kubectl --context mof-patterns delete -n patterns -f access-control/03-serviceaccount.yaml
kubectl --context mof-patterns delete -n patterns -f access-control/02-decoys.yaml
kubectl --context mof-patterns delete -n patterns -f access-control/01-configmap.yaml
kubectl --context mof-patterns delete -n patterns -f access-control/00-postgres.yaml
```

## Verification: examples/appendix-patterns/access-control/

The runnable example deploys `payment-service` under a dedicated `ServiceAccount` bound to a `Role` scoped by `resourceNames`, then runs a sequence of `kubectl auth can-i --as` checks: an allowed read of its own ConfigMap and Secret, a denied read of a decoy ConfigMap and Secret the Role never names, a denied `list` across the namespace, and a `ClusterRole`-via-`RoleBinding` check showing the built-in `view` role scoped to one namespace. Full walkthrough in `examples/appendix-patterns/access-control/README.md`.
