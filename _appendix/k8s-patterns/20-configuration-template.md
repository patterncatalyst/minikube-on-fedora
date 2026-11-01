---
title: "Configuration Template"
order: 20
part: "Configuration"
description: "Render a structured config file from a template and an environment overlay with an init container, for configuration shapes a flat environment variable can't express."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain what Configuration Template solves that EnvVarConfiguration and ConfigurationResource can't
- Wire an init container to render a template against overlay values and write the result to a shared `emptyDir`
- Switch an environment overlay (dev versus prod) and explain why the change requires a new Pod, not just a new ConfigMap
- Reason about why this pattern trades startup-time complexity for a config format a flat key-value store can't hold

## Why this matters

Every pattern so far in this family assumes configuration is flat: a set of named values, one per environment variable or one per file. That assumption holds for most application settings, but it breaks down the moment a piece of configuration is structured in a way env vars were never meant to express: an XML document with nested elements, a YAML file with lists and maps, any format where the shape of the data matters as much as its values. A ConfigMap can still hold that file whole, as one key's value, but the values *inside* it still need to vary by environment, and stuffing a different complete file into the ConfigMap for every environment duplicates everything that doesn't change along with the one thing that does.

Configuration Template solves this by splitting the file into two pieces: a template that holds the structure and never changes, and a small set of overlay values that do change per environment. An init container renders the two together into a real file before the main container ever starts, so by the time the application reads its config, there's no template syntax left in it, just a plain file, in whatever format the application expects.

`inventory-service` is the worked example here, specifically because its own runtime settings (`SERVICE_SCHEMA`, the Postgres connection) are perfectly well served by flat env vars and stay that way. The template this chapter renders is a stand-in for a config shape the application doesn't actually read today, representing the XML and YAML configs that real services in this position do read, and demonstrating the mechanism without requiring a modification to the service's own code.

## The template and its overlays

The template is one ConfigMap key with two substitution tokens:

```yaml
data:
  app.conf.tmpl: |
    [inventory-service]
    environment=__ENV_LABEL__
    log_level=__LOG_LEVEL__
    rendered_by=init-container
```

Two more ConfigMaps hold the values that fill those tokens, one per environment:

```yaml
# inventory-dev-overlay
data:
  ENV_LABEL: development
  LOG_LEVEL: debug
---
# inventory-prod-overlay
data:
  ENV_LABEL: production
  LOG_LEVEL: warning
```

Separating template from overlay means the template is written once and never touched again for an environment change: only the small overlay ConfigMap changes, and it changes by substitution, not by editing a large structured file by hand and hoping nothing else in it shifted. The production literature on this pattern (Kubernetes Patterns, Ibryam & Huss) uses a real templating engine with proper Go-template syntax for exactly this reason: a config file complex enough to need this pattern in the first place usually needs more than a plain string substitution can offer. This example uses `sed` instead, which is enough for two tokens and keeps the init container to a stock `ubi-minimal` image with no custom build, but the same shared-volume mechanism applies whether the renderer is `sed`, `envsubst`, or a dedicated tool.

## Rendering in an init container

The rendering happens in an init container, which runs to completion before any regular container in the Pod starts:

```yaml
initContainers:
  - name: render-config
    image: registry.access.redhat.com/ubi10/ubi-minimal:latest
    command:
      - sh
      - -c
      - |
        sed -e "s/__ENV_LABEL__/${ENV_LABEL}/" -e "s/__LOG_LEVEL__/${LOG_LEVEL}/" \
          /templates/app.conf.tmpl > /rendered/app.conf
    envFrom:
      - configMapRef:
          name: inventory-dev-overlay
    volumeMounts:
      - name: template
        mountPath: /templates
        readOnly: true
      - name: rendered
        mountPath: /rendered
```

The overlay arrives in the init container the same way any ConfigMap arrives in any container: `envFrom`, bulk-exposing `ENV_LABEL` and `LOG_LEVEL` as environment variables the shell command reads directly. The template arrives as a read-only mount of the template ConfigMap. The rendered output goes to a second volume, `rendered`, which is an `emptyDir`: ephemeral, shared between every container in this Pod, and gone the moment the Pod is deleted. That's the right lifetime for it: the rendered file only needs to exist for as long as this one Pod does, and re-rendering it is exactly what happens on the next Pod start anyway.

![A template and an overlay feeding an init container, which writes one rendered file into a shared volume before the main container starts]({{ "/assets/diagrams/appendix-20-configuration-template.svg" | relative_url }})
*The init container runs once, renders the file once, and exits; the main container only ever sees the finished result.*

## The main container only sees the result

`inventory-service` mounts the same `rendered` volume read-only:

```yaml
volumeMounts:
  - name: rendered
    mountPath: /config/app
    readOnly: true
```

By the time this container starts, `/config/app/app.conf` already exists with every token substituted: there's no template syntax visible to it, no rendering step it has to perform itself, and no dependency on the rendering tool (`sed`, in this example) being present in its own image. This division of labor is the entire value of putting the rendering in an init container rather than, say, a startup script inside the main container: the main container's image stays focused on running the application, and the rendering logic (which might reasonably use a different language or tool than the application itself) lives in its own image, with its own lifecycle, started and torn down by Kubernetes rather than by application code.

```bash
kubectl exec -n patterns "$POD" -- cat /config/app/app.conf
```

```ini
[inventory-service]
environment=development
log_level=debug
rendered_by=init-container
```

## Switching overlays means a new Pod

The dev-to-prod switch in this example changes which ConfigMap the init container's `envFrom` names:

```bash
kubectl patch deployment inventory-service -n patterns --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/initContainers/0/envFrom/0/configMapRef/name","value":"inventory-prod-overlay"}]'
kubectl rollout restart deployment/inventory-service -n patterns
```

This is worth sitting with: unlike ConfigurationResource's mounted file, which the kubelet keeps in sync with a running Pod on its own, an init container runs exactly once per Pod lifetime, at creation, and never again. Changing the overlay ConfigMap's *contents* while a Pod is running (rather than changing which ConfigMap the Deployment names) would have no effect at all, for the same reason: there's no mechanism that re-triggers an already-finished init container. The only way to get a new rendered file is a new Pod, which is exactly what `rollout restart` produces. This is a meaningfully different operational model from both EnvVarConfiguration (resolved once, same as this) and ConfigurationResource's file mounts (synced continuously, unlike this), and knowing which one a given piece of config follows is what keeps an on-call engineer from waiting on a sync that was never going to happen.

## Why an init container, not a sidecar

A sidecar (a second container running alongside the main one for the Pod's whole life) could, in principle, also render this file, watch the overlay ConfigMap for changes, and re-render on the fly, closing the gap the previous paragraph just described. That's a real, more capable design, and it's exactly the Sidecar pattern (this family's structural counterpart, covering containers that run for a Pod's entire lifetime rather than finishing before it starts). It costs more: a long-running process to maintain, a file-watching loop to get right, and a main container that now has to tolerate its config file changing underneath it at an unpredictable moment, which an application built around reading its config once at startup generally isn't designed to handle gracefully. An init container is the right default specifically because most applications only ever read their config file once, at their own startup: rendering it once, before that read happens, and never touching it again matches what the application was already going to do. Reach for a sidecar instead only when the config needs to change without restarting the application, which is a meaningfully different requirement than this chapter's scope.

## Runtime templating versus deploy-time templating

It's worth distinguishing this chapter's approach from a question that comes up quickly once templating enters the picture: why not template the whole manifest with Helm or Kustomize instead, generating a different ConfigMap per environment before anything ever reaches the cluster? Both are legitimate and solve a related but different problem. Helm and Kustomize template at deploy time, on the machine or pipeline doing the `apply`: the cluster never sees a template, only the fully rendered manifest, and switching environments means running the tool again with different values and reapplying. Configuration Template renders at *runtime*, inside the cluster, from resources that are themselves already applied and unchanging; the template and the overlay both exist as ordinary ConfigMaps the whole time, and what changes between environments is which overlay a Pod spec references, not what gets submitted to the API server. The two aren't mutually exclusive (a Helm chart could easily template the overlay ConfigMap's own values while the rendering mechanism inside the Pod stays exactly as this chapter describes), but conflating them is a common point of confusion: Helm's `{{ }}` syntax templates the manifest before it reaches Kubernetes, while this chapter's `__ENV_LABEL__` tokens survive all the way into a running container and get resolved by a process running inside the cluster.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Environment, Configuration & Security (25%)
> **Competency:** Use an init container to prepare a shared volume for the main container, including config rendered from a ConfigMap-backed template
> **Drill:** `kubectl get pod -n patterns -l app.kubernetes.io/name=inventory-service -o jsonpath='{.items[0].status.initContainerStatuses[0].state.terminated.reason}'` (confirms the init container exited cleanly before the main container started)

> **🤖 Explore with your agent**
>
> "Add a third token to app.conf.tmpl for a numeric value (a connection pool size), add it to both overlay ConfigMaps with different numbers, and confirm the rendered file picks up the right one for each overlay."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f configuration-template/04-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f configuration-template/00-postgres.yaml
kubectl --context mof-patterns delete -n patterns -f configuration-template/03-configmap-prod-overlay.yaml
kubectl --context mof-patterns delete -n patterns -f configuration-template/02-configmap-dev-overlay.yaml
kubectl --context mof-patterns delete -n patterns -f configuration-template/01-configmap-template.yaml
```

## Verification: examples/appendix-patterns/configuration-template/

The runnable example deploys `inventory-service` with an init container rendering a template against the dev overlay, confirms the rendered file's content and the init container's clean exit, then switches to the production overlay and recreates the Pod to show the new values land only after a fresh start. Full walkthrough in `examples/appendix-patterns/configuration-template/README.md`.
