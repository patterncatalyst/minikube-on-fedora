---
title: "CKAD Crosswalk"
order: 33
part: "CKAD"
description: "The closing reference: every chapter in this appendix mapped to its CKAD domain and competency, a per-domain coverage summary, and a timed self-test against the shipping services."
duration: "reference"
---

This is a reference chapter, not a pattern chapter: no new manifests, no
runnable example of its own. It closes the appendix by mapping every chapter
back to the exam it reconciles against, so the set doubles as a revision
tool once you've read the patterns themselves.

Some rows below point at chapters from families still in flight on their own
branches (Behavioral, Advanced, Security) rather than merged to `main` yet.
Their links resolve once those families land; their domain/competency
entries come from this appendix's own CKAD reconciliation plan and carry
**[verify]** wherever that plan's mapping hasn't been checked against a
published chapter's own exam-lens callout.

## The five domains, by weight

![The five CKAD exam domains sized by their share of the exam: Design & Build 20%, Deployment 20%, Observability & Maintenance 15%, Environment/Config & Security 25%, Services & Networking 20%]({{ "/assets/diagrams/appendix-33-ckad-crosswalk.svg" | relative_url }})
*Environment, Configuration & Security carries the single largest share of the exam, and as the table below shows, the largest share of this appendix's chapters too.*

| Domain | Weight |
|---|---|
| Application Design and Build | 20% |
| Application Deployment | 20% |
| Application Observability and Maintenance | 15% |
| Application Environment, Configuration and Security | 25% |
| Services and Networking | 20% |

## The full crosswalk

| # | Chapter | Family | CKAD domain | Competency |
|---|---|---|---|---|
| 01 | [Predictable Demands]({{ '/appendix/k8s-patterns/01-predictable-demands/' | relative_url }}) | Foundational | Environment, Configuration & Security (25%) | Define resource requirements (requests/limits) for a container, and understand how a Pod references a ConfigMap or PersistentVolumeClaim |
| 02 | [Declarative Deployment]({{ '/appendix/k8s-patterns/02-declarative-deployment/' | relative_url }}) | Foundational | Application Deployment (20%) | Apply rolling and non-rolling update strategies, and use kubectl to manage rollouts |
| 03 | [Health Probe]({{ '/appendix/k8s-patterns/03-health-probe/' | relative_url }}) | Foundational | Observability and Maintenance (15%) | Understand and configure liveness, readiness, and startup probes |
| 04 | [Managed Lifecycle]({{ '/appendix/k8s-patterns/04-managed-lifecycle/' | relative_url }}) | Foundational | Application Design & Build (20%) | Understand multi-container Pod design and the container lifecycle, including startup and shutdown hooks |
| 05 | [Automated Placement]({{ '/appendix/k8s-patterns/05-automated-placement/' | relative_url }}) | Foundational | Application Design & Build (20%) **[verify]** | Understand the Kubernetes scheduler, including node selectors, affinity/anti-affinity, and taints/tolerations |
| 06 | [Init Container]({{ '/appendix/k8s-patterns/06-init-container/' | relative_url }}) | Structural | Application Design and Build (20%) | Understand multi-container Pod design, including an init container that must complete before the main container starts |
| 07 | [Sidecar]({{ '/appendix/k8s-patterns/07-sidecar/' | relative_url }}) | Structural | Application Design and Build (20%) | Understand multi-container Pod design, including a sidecar container and its startup/shutdown ordering relative to the main container |
| 08 | [Adapter]({{ '/appendix/k8s-patterns/08-adapter/' | relative_url }}) | Structural | Application Observability and Maintenance (15%) | Understand multi-container Pod design applied to observability, including a sidecar that exposes metrics in a standard format |
| 09 | [Ambassador]({{ '/appendix/k8s-patterns/09-ambassador/' | relative_url }}) | Structural | Application Design and Build (20%) | Understand multi-container Pod design, including a proxy sidecar that brokers the main container's outbound connection |
| 10 | Batch Job | Behavioral | Application Design & Build (20%) | Understand Jobs and CronJobs, including `completions`, `parallelism`, and indexed completion mode |
| 11 | Periodic Job | Behavioral | Application Design & Build (20%) | Understand Jobs and CronJobs, including schedule, concurrencyPolicy, and manual Job creation from a CronJob template |
| 12 | Daemon Service | Behavioral | Application Design & Build (20%) **[verify]** | Understand DaemonSets, including node placement, tolerations, and update strategy |
| 13 | Singleton Service | Behavioral | Application Deployment (20%) **[verify]** | Understand PodDisruptionBudget and the distinction between voluntary and involuntary disruption |
| 14 | Stateless Service | Behavioral | Application Design & Build (20%) | Understand storage and volume concepts well enough to recognize when a workload has none, and what distinguishes it from one that does |
| 15 | Stateful Service | Behavioral | Application Design & Build (20%), storage | Understand StatefulSets, headless Services, and `volumeClaimTemplates` for stable per-Pod storage |
| 16 | Service Discovery | Behavioral | Services & Networking (20%) | Understand Services (ClusterIP, NodePort, LoadBalancer), DNS resolution, and Ingress path-based routing |
| 17 | Self Awareness | Behavioral | Environment, Configuration & Security (25%) | Understand the Downward API, including fieldRef, resourceFieldRef, and the volume form for values that can change at runtime |
| 18 | [Env Var Configuration]({{ '/appendix/k8s-patterns/18-env-var-configuration/' | relative_url }}) | Configuration | Environment, Configuration & Security (25%) | Configure a Pod's environment from literals, ConfigMap keys, and Secret keys, and understand env var resolution timing |
| 19 | [Configuration Resource]({{ '/appendix/k8s-patterns/19-configuration-resource/' | relative_url }}) | Configuration | Environment, Configuration & Security (25%) | Bulk-expose a ConfigMap or Secret with envFrom and mount the same resource as a volume; reason about which consumption mode updates live |
| 20 | [Configuration Template]({{ '/appendix/k8s-patterns/20-configuration-template/' | relative_url }}) | Configuration | Environment, Configuration & Security (25%) | Use an init container to prepare a shared volume for the main container, including config rendered from a ConfigMap-backed template |
| 21 | [Immutable Configuration]({{ '/appendix/k8s-patterns/21-immutable-configuration/' | relative_url }}) | Configuration | Environment, Configuration & Security (25%) | Create an immutable ConfigMap, explain why an in-place edit is rejected, and roll a configuration change through a Deployment update |
| 22 | Controller | Advanced | Environment, Configuration & Security (25%) **[verify]** | Understand a custom controller's watch-and-reconcile loop extending the Kubernetes control plane |
| 23 | Operator | Advanced | Environment, Configuration & Security (25%) **[verify]** | Understand a CRD-based Operator packaging an application's own operational knowledge as a Kubernetes API |
| 24 | Elastic Scale | Advanced | Application Deployment (20%) **[verify]** | Understand HorizontalPodAutoscaler and VerticalPodAutoscaler for elastic scaling, including event-driven scale-to-zero |
| 25 | Image Builder | Advanced | Application Design and Build (20%) | Build and reference a container image produced in-cluster |
| 26 | Access Control | Security | Environment, Configuration & Security (25%) | Create a ServiceAccount, Role, and RoleBinding scoping access to specific resources and verbs |
| 27 | Network Segmentation | Security | Services and Networking (20%) | Restrict pod-to-pod traffic with a NetworkPolicy |
| 28 | Process Containment | Security | Environment, Configuration & Security (25%) | Configure a SecurityContext and understand Pod Security Standards enforcement |
| 29 | Secure Configuration | Security | Environment, Configuration & Security (25%) | Manage Secrets securely, including least-privilege access via RBAC |
| 30 | [Observability and Debugging]({{ '/appendix/k8s-patterns/30-observability-and-debugging/' | relative_url }}) | CKAD gaps | Observability and Maintenance (15%) | Understand `kubectl logs`, `exec`, `port-forward`, `describe`, `get events`, and `kubectl debug` ephemeral containers |
| 31 | [Packaging: Helm and Kustomize]({{ '/appendix/k8s-patterns/31-packaging-helm-and-kustomize/' | relative_url }}) | CKAD gaps | Application Deployment (20%) | Use Helm (install/upgrade/rollback) and Kustomize (bases and overlays) to deploy and parameterize an application |
| 32 | [Namespace Governance]({{ '/appendix/k8s-patterns/32-namespace-governance/' | relative_url }}) | CKAD gaps | Environment, Configuration & Security (25%) | Create and use ResourceQuota and LimitRange to govern a namespace's resource consumption, and relate them to a Pod's own PriorityClass |

## Coverage by domain

Counting the table above by its `CKAD domain` column:

| Domain | Weight | Chapters |
|---|---|---|
| Application Design and Build | 20% | 11 (04, 05, 06, 07, 09, 10, 11, 12, 14, 15, 25) |
| Application Deployment | 20% | 4 (02, 13, 24, 31) |
| Application Observability and Maintenance | 15% | 3 (03, 08, 30) |
| Environment, Configuration and Security | 25% | 12 (01, 17, 18, 19, 20, 21, 22, 23, 26, 28, 29, 32) |
| Services and Networking | 20% | 2 (16, 27) |

Every domain has direct coverage; the distribution isn't even, and that's
expected rather than a gap. Environment, Configuration and Security carries
both the exam's heaviest weight and this appendix's largest cluster of
chapters, since nearly every Configuration-family pattern and both namespace-
governance gap chapters land there. Services and Networking has the fewest
dedicated chapters (Service Discovery and Network Segmentation) relative to
its 20% weight, though Ambassador (09) and Adapter (08) both touch networking
concerns as a side effect of the multi-container Pod design they're actually
teaching; they're tagged here by their primary competency, not every domain
they brush against.

## Self-test: a timed pass against the shipping services

Fifteen tasks, each naming the chapter that teaches it. Budget about five
minutes per task (CKAD's own pacing) and don't look at the answer chapter
until you've attempted the task cold. Everything below targets the `patterns`
namespace on the `mof-patterns` profile; bring up the profile and build
whichever service each task needs before starting the clock.

1. Without editing any YAML, set `shipping-service`'s CPU request to 150m and
   its memory limit to 768Mi using a single `kubectl` command. (chapter 01)
2. Roll out a new `shipping-service` image with zero unavailability during
   the rollout, then undo the rollout and confirm the previous image is back.
   (chapter 02)
3. Add a startup probe to `inventory-service` generous enough that a slow
   cold start is never mistaken for a liveness failure. (chapter 03)
4. Add an init container to `shipping-service` that blocks until
   `patterns-postgres` accepts connections, before the main container starts.
   (chapter 06)
5. Put an ambassador sidecar in front of `order-service`'s outbound call to
   `inventory-service`, so the main container always dials `localhost`. (chapter 09)
6. Run a one-shot Job (not a Deployment) with 3 completions and parallelism 1
   that backfills a column in the shipping schema. (chapter 10)
7. Set a PodDisruptionBudget on `payment-service` so a voluntary node drain
   can never take down its only replica. (chapter 13)
8. Expose `shipping-service` with a ClusterIP Service and reach it by its
   in-cluster DNS name from a pod running `inventory-service`. (chapter 16)
9. Inject a pod's own namespace into `notification-service` as an
   environment variable using the Downward API, with no hardcoded string. (chapter 17)
10. Source `review-service`'s database password from a Secret key rather than
    a ConfigMap key, and be ready to explain the RBAC difference that choice
    makes. (chapter 18)
11. Scope a ServiceAccount for `shipping-service` to read-only access on
    ConfigMaps in its own namespace, nothing else, and prove a Secret read
    from that identity is denied. (chapter 26)
12. Write a NetworkPolicy that lets only `order-service` reach
    `payment-service`, and confirm every other pod in the namespace is now
    blocked. (chapter 27)
13. Force `shipping-service` to crash, then recover its last words with
    `kubectl logs --previous` and inspect its live process table with a
    `kubectl debug` ephemeral container. (chapter 30)
14. Deploy `shipping-service` twice into the same namespace, once as a Helm
    release and once through a Kustomize overlay, with neither deployment's
    objects colliding with the other's. (chapter 31)
15. Cap the `patterns` namespace to 3 pods total and watch a fourth
    `shipping-service` replica get rejected before any Pod object for it
    exists. (chapter 32)

## 🤖 Explore with your agent

> "Generate five more CKAD-style practice tasks against the shipping services
> that this appendix hasn't covered yet in its self-test list, each naming
> the chapter in this crosswalk that teaches the skill it tests, and weight
> them toward whichever domain in the coverage table above has the fewest
> chapters."

## Verification

This chapter's self-test above *is* its verification: there's no separate
runnable example under `examples/appendix-patterns/`, since every task
reuses a prior chapter's own deployment. Work through all fifteen against a
live `mof-patterns` profile before treating the appendix as complete
revision.
