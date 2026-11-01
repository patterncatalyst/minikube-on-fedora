---
title: "Packaging: Helm and Kustomize"
order: 31
part: "CKAD gaps"
description: "Deploy the same shipping-service two ways: a Helm chart with install/upgrade/rollback, and a Kustomize base with dev and prod overlays, with no templating, just patches."
duration: "25 min"
---

## Learning objectives

By the end of this chapter you can:

- Exercise the CKAD-relevant Helm command surface: `install`, `upgrade`,
  `rollback`, `history`, and overriding values with `--set`
- Author a Kustomize base of plain manifests plus two overlays that patch it
  for different environments
- Render a Kustomize overlay without applying it (`kubectl kustomize`) and
  preview a change before it lands (`kubectl diff -k`)
- Explain what Kustomize can do that Helm can't (and vice versa), and why CKAD
  expects familiarity with both rather than a preference for one

## Why this matters

§9 of the main tutorial already builds a Helm chart from scratch and walks the
full install-upgrade-rollback-uninstall cycle in detail; that explanation
isn't repeated here. What that chapter doesn't cover is **Kustomize**, and the
exam doesn't let you skip it: CKAD's Application Deployment domain (20% of
the exam) expects comfort with both ways Kubernetes manifests get
parameterized for more than one environment, because production clusters use
both, often for different reasons on the same team.

The two tools solve overlapping problems with opposite philosophies. Helm
treats a set of manifests as a **template**: `values.yaml` supplies the inputs,
Go template syntax computes the output, and `helm install` tracks the result
as a numbered **release** you can upgrade and roll back as a unit. Kustomize
treats a set of manifests as **data**: there's no templating language at all,
just a base of ordinary YAML and a chain of overlays that patch specific
fields of specific objects, with no release object and no history beyond
whatever the cluster's own object revisions and your own version control
already track. Neither approach is strictly more powerful; they're suited to
different jobs, and this chapter works through both against the same
`shipping-service` deployment so the contrast is concrete rather than
abstract.

## Helm, from the CKAD angle

§9 covers chart anatomy, template syntax, and the full workflow end to end; see
[§9: Helm]({{ "/docs/09-helm/" | relative_url }}) for that walkthrough. The
CKAD exam doesn't test chart *authoring* so much as the *command surface* a
chart consumer uses day to day, so that's the focus here. This chapter's chart
(`chart/` in the runnable example) deploys `shipping-service` with a fixed
release name, `shipping-helm`, so every command below names an object you can
find with plain `kubectl` afterward:

```bash
helm install shipping-helm ./chart --namespace patterns
helm list -n patterns
```

`helm list` shows the release, its revision number (starting at 1), and its
status. An upgrade with a changed value moves the release to revision 2 and,
because the chart's Deployment template carries a
`checksum/configmap` annotation computed from the rendered ConfigMap, also
rolls the Pods even when nothing in the Deployment template itself literally
changed:

```bash
helm upgrade shipping-helm ./chart --namespace patterns --set replicaCount=2
helm history shipping-helm -n patterns
```

`helm history` is the exam-relevant command for "what changed and when": it
lists every revision with its status and a one-line description, independent
of whatever Deployment-level `kubectl rollout history` would show, because a
Helm release can touch more than a Deployment (this chart's release also
tracks a ConfigMap and a Service as part of the same unit). Rolling back
targets a **release revision**, not a Deployment revision, and reverts every
object the chart manages back to that revision's rendered state in one
command:

```bash
helm rollback shipping-helm 1 -n patterns
```

`--set` is the fast path for a one-off override; `helm template` (dry-run
rendering with no cluster interaction) and `helm lint` (chart sanity checks)
are both worth running before any `install` or `upgrade` that changes
something non-trivial, since both catch a malformed template before it
reaches the API server rather than after. All three commands, plus `helm
uninstall`, make up the realistic CKAD command surface for Helm: a candidate
is expected to install a chart with override values, confirm a running
release, upgrade it, and recover from a bad upgrade with a rollback, not to
write chart templates from scratch under exam time pressure.

## Kustomize: patches over plain manifests, no templating

Kustomize's base is nothing more than ordinary Kubernetes YAML plus one extra
file, `kustomization.yaml`, that lists which manifests belong together:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: patterns
resources:
  - configmap.yaml
  - deployment.yaml
  - service.yaml
```

There's no `{{ .Values.x }}` anywhere in `deployment.yaml`: it's a complete,
valid Deployment manifest you could `kubectl apply -f` directly, with the
replica count, resources, and schema name hardcoded to whatever the base
should default to. The `namespace: patterns` field is a Kustomize
**transformer**: it stamps every resource in the list with that namespace at
build time, so the manifests themselves don't have to repeat it.

An **overlay** is a second directory that references the base and layers
changes on top of it, without copying or forking any of the base's YAML:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: patterns
resources:
  - ../../base
patches:
  - path: deployment-patch.yaml
  - path: configmap-patch.yaml
```

Each patch file is itself a *partial* manifest: just enough of the object
(matched by `apiVersion`, `kind`, and `metadata.name`) to say what changes.
The dev overlay's deployment patch sets one replica and a lean resource
profile; the prod overlay's sets two replicas and more headroom. Both patch
the exact same base Deployment, by name, with nothing in the base itself
aware that an overlay exists:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shipping-kustomize
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: shipping-service
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              memory: 768Mi
```

This is a **strategic merge patch**: Kubernetes-aware merge rules decide how
to combine the patch with the base (a `containers` list entry matches by
`name`, not by array index, so a patch doesn't have to repeat every sibling
container just to change one field on one of them). Kustomize also supports
JSON 6902 patches for precise, path-addressed edits, and **generators**
(`configMapGenerator`, `secretGenerator`) that build a ConfigMap or Secret
from literal values or files and automatically append a content hash to its
name, so a changed value produces a new object name and forces a rollout the
same way Helm's checksum annotation does. Neither generators nor JSON 6902
patches are needed for this chapter's example, since a strategic merge patch
covers both overlays cleanly, but both are fair game on the exam.

`kubectl` has had Kustomize built in since 1.14, so no separate binary is
required to use any of this:

```bash
kubectl kustomize kustomize/overlays/dev
kubectl apply -n patterns -k kustomize/overlays/dev
```

`kubectl kustomize` renders the final, merged manifests to stdout without
touching the cluster: the Kustomize equivalent of `helm template`, and worth
running before every `apply -k` for the same reason. Moving from dev to
prod is `kubectl apply -k` against the other overlay; `kubectl diff -k` shows
exactly what would change first, which matters more for Kustomize than for
Helm, since there's no release object recording what the previous apply
looked like:

```bash
kubectl diff -n patterns -k kustomize/overlays/prod
kubectl apply -n patterns -k kustomize/overlays/prod
```

![Two ways to parameterize the same Deployment: a Helm chart rendering values.yaml into a tracked release, and a Kustomize base patched by dev and prod overlays with no release object at all]({{ "/assets/diagrams/appendix-31-packaging-helm-and-kustomize.svg" | relative_url }})
*Same shipping-service image, same namespace, two independent deployment mechanisms that never have to know about each other.*

## Choosing between them

Helm earns its templating language the moment a chart has to serve
consumers who don't know (and shouldn't need to know) the underlying
manifest structure: install a community chart for a database or a message
broker and the chart hides dozens of fields behind a `values.yaml` with
sensible defaults, with real conditional logic (`{{ if .Values.x }}`)
deciding which objects even get created. That flexibility costs something: a
Helm template is strictly harder to read than the manifest it eventually
produces, because the real manifest only exists after rendering.

Kustomize earns its simplicity the moment every consumer already owns and
understands the base manifests, and the only thing that varies between
environments is a bounded set of fields: replica counts, resource profiles,
an environment label, a schema name. There's nothing to learn beyond
Kubernetes YAML itself and the small patch vocabulary this chapter covers,
and `kubectl kustomize`'s rendered output is always a real, valid manifest
you could have written by hand. That's also its ceiling: Kustomize has no
concept of a release, no rollback command of its own (recovering from a bad
`apply -k` means applying a previous overlay state, tracked in git, not in
the cluster), and no conditional logic beyond what patches can express.

CKAD's answer to "which one" is "both, in their own lane": a chart
distributed to other teams or published publicly is a Helm problem; a
service your own team owns, deployed with small per-environment differences,
is very often a Kustomize problem, and a surprising number of real clusters
run both at once, pairing a vendor's Helm chart for a database with Kustomize
overlays for the services your own team writes.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Deployment (20%)
> **Competency:** Use Helm (install/upgrade/rollback) and Kustomize (bases and overlays) to deploy and parameterize an application
> **Drill:** `kubectl kustomize kustomize/overlays/prod | kubectl apply -n patterns -f -` (apply a rendered overlay without `-k`, the way a CI pipeline that pins a rendered manifest might)

> **🤖 Explore with your agent**
>
> "Add a third overlay, `staging`, that reuses the prod overlay's resource profile but the dev overlay's single replica and schema name, and show me how little new YAML that actually requires on top of the existing base and patches."

## Cleanup

```bash
helm --kube-context mof-patterns uninstall shipping-helm -n patterns
kubectl --context mof-patterns delete -n patterns -k packaging-helm-and-kustomize/kustomize/overlays/prod
kubectl --context mof-patterns delete -n patterns -f packaging-helm-and-kustomize/00-postgres.yaml
```

## Verification: examples/appendix-patterns/packaging-helm-and-kustomize/

The runnable example installs the Helm chart, upgrades and rolls it back,
then applies the Kustomize dev overlay, diffs and switches to prod, and
confirms both deployments' replica counts and resource profiles at each
step. Full walkthrough in
`examples/appendix-patterns/packaging-helm-and-kustomize/README.md`.
