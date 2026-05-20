# Product Requirements Document — Minikube Tutorial on Fedora

> This PRD is the source of truth for what we're building. When scope
> creep tempts ("should we also cover X?"), the answer is whatever this
> PRD says. Updates to this file are commit-worthy events with their own
> message — they're how the project records what changed and why.

---

## 1. Summary

**One sentence:** A hands-on tutorial that walks a Fedora-using
Podman-comfortable developer from `dnf install` through running real
applications on minikube with `kubectl` and `helm`, plus reference
material for Istio and (optionally) KEDA.

**One paragraph:** This tutorial teaches a working developer on
Fedora 44 how to stand up a local Kubernetes cluster with minikube,
deploy applications imperatively with `kubectl` and declaratively
with `helm`, and extend the cluster with the Istio service mesh and
KEDA event-driven autoscaling. Readers arrive knowing Podman and
their package manager; they leave with a workflow they can use to
prototype Kubernetes-bound applications without provisioning a
remote cluster. It exists because most existing minikube tutorials
are Docker-first and Ubuntu-or-macOS-first, because helm and istio
integration on minikube lives scattered across vendor docs that
don't share a coherent example, and because the prior personal
version of this tutorial (2023) targeted Kubernetes 1.22 against
`containerd` — both stale enough in 2026 to mislead.

---

## 2. Problem statement

### Who is the reader?

A working developer on Fedora 44 who uses Podman, podman-compose,
and Podman Desktop daily and has the Docker CLI installed as a
familiarity safety net. They've used containers for years, know
what a Pod, Deployment, and Service are at a paragraph-level, but
haven't operated more than a hobby cluster. Their motivation is
usually a new project that targets Kubernetes in production and
needs local-equivalent prototyping, or a need to explore Istio or
KEDA outside their main workplace cluster.

### What's their pain today?

The official minikube docs treat installation as a one-liner, then
redirect into the broader Kubernetes documentation that assumes
more cluster-ops literacy than most application developers have.
Existing third-party tutorials are largely Docker-first or
Ubuntu-first; on Fedora 44 with Podman, much of their command-line
prose reads as out of date. Helm, kubectl idioms, Istio, and KEDA
each live in their own ecosystems with their own getting-started
pages, and stitching them together against minikube is a half-day
of reading-while-debugging. Readers end up copying YAML from Stack
Overflow without understanding why it works.

### Why now?

Fedora 44 is current as of 2026; the podman / podman-compose
tooling has stabilized to where the docker driver is no longer the
default-best choice on Fedora; helm 3.x is universal; KEDA's HTTP
add-on (the piece that makes HTTP-driven autoscaling actually
demonstrable rather than only CPU-based) reached usable maturity
in 2024–2025; and the 2023 version of this tutorial targeted
Kubernetes 1.22 with `containerd`, both of which are now misleading
defaults.

---

## 3. Goals and non-goals

### Goals

- A reader who finishes the tutorial can install minikube on
  Fedora 44, start a cluster with the podman driver, deploy an
  app two ways (kubectl and helm), expose it via NodePort, watch
  logs and basic metrics, and tear it all down — without
  consulting other docs
- A reader understands the difference between minikube's drivers,
  cluster runtimes, and addons well enough to pick the right combo
  for a next project
- All hands-on examples run on Fedora 44 with the podman driver
  and pass an end-to-end `demo.sh` script with no manual fixups
- The tutorial covers helm chart **authoring** for at least one
  small app — not just `helm install` of someone else's chart
- The Istio section delivers a working install + smoke test
  (Gateway + VirtualService) the reader can use as a reference
  when applying Istio elsewhere
- The KEDA section (optional) demonstrates HTTP-driven scaling
  via the KEDA HTTP add-on with `hey` as the load generator —
  not only CPU-based scaling

### Non-goals

- This tutorial does NOT teach Kubernetes concepts from scratch —
  readers are assumed to know what a Pod, Deployment, and Service
  are at a paragraph-level
- This tutorial does NOT cover production cluster operations
  (RBAC at depth, network policies, secrets management beyond
  `kubectl create secret`, multi-tenancy, hardening)
- This tutorial does NOT cover building container images — the
  examples pull pre-built UBI-based images
- This tutorial does NOT compare minikube with managed Kubernetes
  offerings as a recommendation; the "alternatives" section names
  the obvious local-cluster options for navigation only
- This tutorial does NOT include Knative (intentionally dropped
  from the 2023 outline to keep scope tractable; may live as a
  follow-on)
- This tutorial does NOT cover Windows / WSL — not tested

---

## 4. Audience details

### Primary audience

A developer running Fedora 44 with Podman, podman-compose, and
Podman Desktop installed; comfortable with `dnf`, `systemctl`, and
their shell. Has the Docker CLI installed for familiarity. Knows
that a Deployment hosts Pods which match a Service's selector but
hasn't operated production Kubernetes.

### Secondary audience

- Developers on Fedora derivatives (RHEL, Rocky, Alma) — most of
  the `dnf`-based instructions apply unchanged
- Developers on macOS who occasionally need local Kubernetes —
  served through brief "macOS notes" callouts in §1 and §2 only,
  not as a tested platform
- Developers learning Helm, Istio, or KEDA who want a low-friction
  local environment for hands-on practice and don't need to start
  from "what is minikube"

### Audience NOT served

- Complete Kubernetes newcomers — they should read the upstream
  "Learn Kubernetes Basics" walkthrough first
- Production cluster operators — minikube is for local dev;
  readers seeking production guidance should look at OpenShift,
  GKE, or EKS docs
- Windows users without WSL — and even WSL is not tested here

---

## 5. Scope and section outline

Sections numbered 0–15. Filenames mirror these numbers in `_docs/`
(`00-outline.md`, `01-prerequisites.md`, …).

### Sections

| §  | Title                                            | Purpose                                                                                  | Est. duration |
|----|--------------------------------------------------|------------------------------------------------------------------------------------------|---------------|
| 0  | Outline                                          | Reader's map of what's ahead; quick-reference TOC                                        | 2 min         |
| 1  | Prerequisites                                    | Hardware, OS, Podman/Docker checks, `dnf`-installable basics                             | 10 min        |
| 2  | Installation                                     | Install minikube + kubectl + helm + supporting tools                                     | 20 min        |
| 3  | Starting minikube                                | Drivers (podman, docker), runtimes (containerd, cri-o), status, pause/stop, upgrade      | 15 min        |
| 4  | Custom resources, profiles, multi-node           | CPU/memory tuning, profiles for parallel clusters, multi-node config                     | 15 min        |
| 5  | Addons and the dashboard                         | Listing/enabling addons; metrics-server, ingress, registry, dashboard                    | 10 min        |
| 6  | Deploying with kubectl                           | Imperative + declarative deploys, dry-run manifest generation, idiomatic kubectl         | 20 min        |
| 7  | Services, NodePort, and minikube IP              | Service types, exposing apps, getting URLs back via `minikube service`                   | 10 min        |
| 8  | Persistent volumes                               | Static `hostPath` PV; dynamic PVC via the default storage class                          | 15 min        |
| 9  | Deploying with Helm                              | `helm install/upgrade/rollback`; using public charts; authoring a tiny chart             | 25 min        |
| 10 | Editor, shell, and terminal integration          | CLion k8s plugin; Podman Desktop's k8s view; zsh + kubectx/kubens; warp.dev workflows    | 15 min        |
| 11 | Istio on minikube                                | Install via `istioctl`, sidecar-enabled demo app, Gateway + VirtualService, mTLS basics  | 30 min        |
| 12 | KEDA on minikube (optional)                      | Helm install of KEDA + HTTP add-on; HTTP-driven `ScaledObject`; load test with `hey`     | 25 min        |
| 13 | Alternatives to minikube                         | Brief: kind, k3s, microk8s, microshift — when to pick what                               | 5 min         |
| 14 | FAQ                                              | Common pain points; cleanup recipes; "I broke my cluster, now what"                      | 5 min         |
| 15 | Where to go next                                 | Pointers to deeper resources and possible follow-on tutorials                            | 5 min         |

**Total estimated duration for a reader:** ~3h 30min of
read-along + hands-on. §11 and §12 are skippable for readers who
only want the core minikube workflow.

### Optional appendices or follow-ons

- A separate Knative-on-minikube tutorial (carryover from the 2023
  outline, deliberately deferred)
- A "minikube to production" follow-on covering network policies,
  RBAC at depth, secrets management at scale
- Deeper Helm chart authoring (templating, dependencies, hooks,
  values inheritance)

---

## 6. Runnable examples

### Will this tutorial have runnable code examples?

- [x] Yes (every hands-on section has a corresponding example)
- [ ] No
- [ ] Partial

### If yes, what languages or tools?

Each example is shell-driven against minikube. Tools per example:

- **kubectl** — for §6, §7, §8 demos (imperative + declarative
  manifests)
- **helm 3.x** — for §9 demos (public chart + authored chart)
- **istioctl** — for §11 (install + verify)
- **KEDA helm charts** (`kedacore/keda` and
  `kedacore/keda-add-ons-http`) — for §12
- **`hey`** — load generator in §12 KEDA demo
- **`curl`** + **`httpie`** — quick smoke tests in multiple sections

No GPU required. No FIPS-validated host required. No paid services
or accounts behind paywalls anywhere.

Container images used by examples are UBI-based and pullable
without `subscription-manager` registration:
`registry.access.redhat.com/ubi9/nginx-124`,
`registry.access.redhat.com/ubi9/ubi-minimal`, and similar public
UBI images.

Runtime versions get pinned at write-time in §2 and tracked in the
reconciliation plan; the open-questions list below tracks the
ones still to verify.

### Example directory layout (decision: merge)

Each example lives in its own directory under `examples/`:

```
examples/06-deploy-nginx-kubectl/
├── README.md       — narrated walkthrough, expected output
├── demo.sh         — strict end-to-end script (also serves as test)
└── *.yaml          — any manifests, helm values, etc.
```

`demo.sh` is the **merge pattern**: it serves as both the
reader-facing "run this to see it work" and the maintainer's
verification test. Every `demo.sh`:

- Starts with `set -euo pipefail`
- Uses `127.0.0.1` not `localhost` (per LESSONS-LEARNED.md)
- Waits for HTTP readiness in a loop, never `sleep N && curl`
- Installs a `trap cleanup EXIT` to tear down even on failure
- Uses distinct ports per example to avoid collisions
- Exits non-zero on failure so the aggregator can tally

### Anticipated example directories

- `examples/06-deploy-nginx-kubectl/` — UBI nginx via `kubectl apply`
- `examples/07-nodeport-service/` — exposing the deploy with NodePort
- `examples/08-persistent-volume/` — `hostPath` PV + dynamic PVC
- `examples/09-deploy-nginx-helm/` — same UBI nginx via a tiny
  authored chart
- `examples/11-istio-bookinfo/` — Istio sample app with sidecar +
  Gateway + VirtualService
- `examples/12-keda-http-scale/` — KEDA HTTP add-on demo with
  `hey` load generation

### Test strategy for examples

- [x] Per-example `demo.sh` (merged demo + test)
- [x] Aggregator script `scripts/test-all-examples.sh` invoking
  each example's `demo.sh`
- [ ] CI via GitHub Actions — deferred. minikube needs a host
  with virtualization that GitHub's default ubuntu runners don't
  cleanly offer. Revisit if this becomes a pain point
- [ ] Manual verification — fallback, recorded in the
  reconciliation plan

The reconciliation plan tracks every example's verification state
— `unverified` by default until a real test confirms it works on
Fedora 44.

---

## 7. Diagrams

### Will this tutorial use diagrams?

- [x] Yes, paired SVG + Excalidraw source as the skeleton supports
- [ ] Yes, but a different format
- [ ] No

Filenames follow `NN-topic-thing.svg` where `NN` is the section
number, matching the skeleton's convention. Each `.svg` ships
alongside its `.excalidraw` source in `assets/diagrams/`, with
both rendered and linked via the `excalidraw.html` include so
readers can re-edit by opening the source in excalidraw.com.

### Anticipated diagrams

These will adjust as prose drives the actual need — not all are
guaranteed to make the cut:

- `03-minikube-driver-runtime-layers.svg` — how the driver
  (podman/docker), the in-cluster runtime (containerd/cri-o), and
  the Fedora host stack layer together
- `06-deployment-pod-service-mapping.svg` — selectors connecting
  Service → Pod via Deployment's labels
- `08-static-vs-dynamic-pv.svg` — hand-authored hostPath PV vs.
  PVC driving dynamic provisioning
- `09-helm-release-lifecycle.svg` — install → upgrade → rollback
  → uninstall with revision history
- `11-istio-sidecar-mesh.svg` — how the Envoy sidecar intercepts
  traffic in/out of a pod
- `12-keda-http-addon-flow.svg` — HTTP request → keda-http
  interceptor → ScaledObject → deployment scale-up

---

## 8. Success metrics

### Verification metrics (we control these)

- All examples' `demo.sh` pass under `scripts/test-all-examples.sh`
  on Fedora 44 with the podman driver
- Reconciliation plan shows all Section C (testing matrix) rows
  as `verified (Fedora 44)`
- §1 prerequisites tested on a fresh Fedora 44 install or VM
- Each section reads end-to-end without forcing a reader to
  context-switch into vendor docs for basic steps

### Adoption metrics (external factors)

- Primary use is personal + team reference, so adoption is not the
  primary success bar
- Secondary goal: this becomes the canonical "set up local k8s"
  reference linked from other patterncatalyst projects

---

## 9. Constraints and dependencies

### Technical constraints

- Primary platform: Fedora 44 with podman as the minikube driver
- macOS appears only as advisory callouts in §1 and §2; not tested
- Examples must run rootless where minikube permits
- All container images pulled by examples must be UBI-based and
  pullable without `subscription-manager` registration —
  `registry.access.redhat.com/ubi9/...` family
- Standard Fedora repositories preferred for tool installs (`dnf
  install`); fall back to upstream installers only when the
  package isn't carried in Fedora repos
- `minikube --driver=podman` is the primary tested driver; the
  `docker` driver is covered as a documented alternate (the user
  has both available)
- No paid services, no accounts behind paywalls

### Editorial constraints

- Vendor-neutral language; the alternatives section names options
  for navigation, not as endorsements
- Use "you" for the reader; avoid "we" voice (per
  LESSONS-LEARNED.md)
- All inline commands written as single-line (use `&&` rather than
  newline blocks) for safe paste into zsh
- Multi-line scripts ship inside `examples/<name>/demo.sh` not as
  inline blocks
- Diagrams use SVG, never PNG; sized via `viewBox`
- Where Fedora and macOS differ, the macOS guidance lives in a
  clearly marked callout, not woven into the primary prose
- Idiomatic `kubectl` is preferred where it fits naturally; `helm`
  is preferred for deploying applications when both kubectl and
  helm would work

### Dependencies

- minikube binary (Fedora package if/when available, else upstream
  install from `https://storage.googleapis.com/minikube/releases/latest/`)
- UBI image availability at `registry.access.redhat.com`
- Helm chart sources: `kedacore/keda`, `kedacore/keda-add-ons-http`
  for §12; `istio-base` / `istiod` charts or `istioctl install` for §11
- `gh` CLI is assumed installed on the **author's** machine for
  repo bootstrap; not assumed on readers' machines

If any of these become unavailable: the minikube binary URL is
the most exposed dependency — pin the tested version and note it
in the reconciliation plan; UBI registry has been stable for
years; helm charts are semver-pinned and won't disappear silently.

---

## 10. Risks and mitigations

| Risk                                                                    | Impact  | Likelihood | Mitigation                                                                                                  |
|-------------------------------------------------------------------------|---------|------------|-------------------------------------------------------------------------------------------------------------|
| Pinned minikube version goes stale within months                        | Medium  | High       | Pin to a tested version; record "tested against X.Y.Z" in reconciliation plan; refresh quarterly            |
| Istio on minikube hits resource limits on default 2-CPU / 2 GB           | High    | Medium     | §1 prereqs bump to 6 CPU / 16 GB; §3 walks through `minikube config set` for these defaults                 |
| KEDA HTTP add-on API changes (it's still evolving)                       | Medium  | Medium     | Pin add-on version; section opens with version disclosure; mark `unverified` until tested                   |
| podman driver behavior differs from docker driver in subtle ways         | Medium  | Medium     | Note differences inline; test both drivers for the core nginx demos before marking those rows verified      |
| Tutorial reads as too long; readers skim and miss prerequisites          | High    | Medium     | §0 outline sets expectations; §1 front-loaded; sections written so partial reads work                       |
| Manifests embed image tags that get retagged upstream                    | Low     | Low        | Use immutable digests inside `demo.sh` tests; human-readable tags in the tutorial prose                     |
| GitHub Pages CDN serves stale diagram SVGs after deploy                  | Low     | Medium     | Per LESSONS-LEARNED.md: hard-reload during verification; expect ~10 min CDN catch-up                        |
| Stripping the prior 2023 tutorial's content too aggressively loses value | Medium  | Low        | Walk the 2023 sections during drafting; lift specific working YAML snippets where still accurate            |

---

## 11. Timeline and milestones

Open-ended; no hard deadline. Estimates are best-effort, will
adjust as real-hardware testing reveals friction.

| Milestone                                                       | Est. effort  | Done? |
|-----------------------------------------------------------------|--------------|-------|
| PRD reviewed and approved (this `_r01`)                         | 1–2 hours    | [ ]   |
| Skeleton scaffolded with branding (`_r02`)                      | 30 min       | [ ]   |
| §0 outline + §1 prerequisites drafted                           | 2–3 hours    | [ ]   |
| §2 installation drafted + tested                                | 3–4 hours    | [ ]   |
| §3 – §5 drafted (start / profiles / addons)                     | 4–6 hours    | [ ]   |
| First runnable example (`examples/06-deploy-nginx-kubectl`) E2E | 2–3 hours    | [ ]   |
| §6 – §8 drafted with examples                                   | 4–6 hours    | [ ]   |
| §9 helm + authored chart example                                | 3–4 hours    | [ ]   |
| §10 editor / shell / terminal section                           | 2–3 hours    | [ ]   |
| §11 Istio drafted + tested                                      | 4–6 hours    | [ ]   |
| §12 KEDA drafted + tested (optional section)                    | 4–6 hours    | [ ]   |
| §13 – §15 (alternatives, FAQ, where-next)                       | 2 hours      | [ ]   |
| All diagrams drafted                                            | 4–6 hours    | [ ]   |
| Cross-section editorial pass                                    | 4–8 hours    | [ ]   |
| All `demo.sh` passing via aggregator                            | 2–3 hours    | [ ]   |
| Reconciliation plan reflects reality                            | 1 hour       | [ ]   |
| Public publish on GitHub Pages                                  | —            | [ ]   |

**Hard deadline (if any):** none

**Realistic launch target:** open; depends on iteration cadence
and how much real-hardware testing reveals

---

## 12. Open questions

To resolve as drafting progresses; tracked here so they don't
leak into prose as unverified claims:

- Is `minikube` packaged in Fedora 44's standard repos, or is the
  upstream Google Cloud Storage binary still the path? (Resolve
  while drafting §2)
- Is `helm` in Fedora 44's standard repos, or do we use the
  official install script? (Resolve in §2)
- Is `kubectl` cleanly installable via `dnf install
  kubernetes-client` without pulling the full server stack, or
  is the upstream binary cleaner? (Resolve in §2)
- Does Podman Desktop's bundled minikube on macOS conflict with a
  standalone minikube install? (For the macOS callouts in §1, §2)
- For the §12 KEDA HTTP add-on demo, what's the smallest UBI-based
  workload that's still illustrative — UBI httpd with a static
  page, or a small Go binary copied into `ubi9-minimal`?
- Should `.excalidraw` sources be committed alongside their `.svg`
  from the start (per skeleton convention) or only once a diagram
  is finalized? (Default: yes, from the start)
- Does the `minikube` podman driver work cleanly with rootless
  podman on Fedora 44, or are there permission gotchas worth a
  callout? (Resolve in §3)

---

## 13. Decision log

Major decisions, with rationale. New decisions get appended here
during the project so future-you can recover the "why" without
re-litigating.

| Date       | Decision                                                                              | Rationale                                                                                                                            |
|------------|---------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| 2026-05-16 | Project name: `patterncatalyst/minikube-on-fedora`, title "Minikube Tutorial on Fedora" | User-specified; distinguishes from the 2023 `patterncatalyst/minikube` repo which remains as historical reference                  |
| 2026-05-16 | Brand emoji: ☸️ (kubernetes wheel)                                                    | Tutorial spans more than helm so the helm wheel ⎈ would be misleading; ☸️ covers the whole scope                                     |
| 2026-05-16 | Knative dropped from scope                                                            | Out of scope for the Fedora-focused personal tutorial; possible standalone follow-on later                                            |
| 2026-05-16 | Istio added; KEDA added with optional flag                                            | User uses Istio extensively elsewhere and wants a minikube reference. KEDA + HTTP add-on demonstrates HTTP-driven scaling, not only CPU |
| 2026-05-16 | macOS coverage is advisory notes only, not a tested platform                          | Author's primary workstation is Fedora 44; testing macOS would add overhead without proportional benefit                              |
| 2026-05-16 | `examples/<name>/demo.sh` serves both reader demo and maintainer test (merge pattern) | Linear demos (manifest → deploy → hit endpoint → cleanup) fit a single strict script cleanly; splitting would duplicate logic         |
| 2026-05-16 | Tool list: kubectl, helm, stern, kubectx/kubens, yq, krew, httpie, hey                | Dropped kapp and ytt (Carvel — useful but tangential); kept hey because the author runs it for load tests across multiple projects   |
| 2026-05-16 | "IDE plugins" section reframed as "Editor, shell, and terminal integration"           | Better captures what's actually in scope: CLion plugin + Podman Desktop GUI + zsh integration + warp.dev workflows                    |
| 2026-05-16 | Container images: UBI-based, pullable without subscription-manager                    | User constraint; `registry.access.redhat.com/ubi9/...` is public and dnf-free at pull time                                            |
| 2026-05-16 | minikube `--driver=podman` is the primary tested driver                               | Matches author's daily workflow; docker driver remains a documented alternate                                                         |
| 2026-05-16 | Standard Fedora repos preferred for tool installs                                     | User preference; falls back to upstream installers only when a package isn't carried by Fedora                                        |
| 2026-05-16 | Iteration delivery: `<repo>_rNN.tar.gz` with explicit single-line git instructions    | User-specified workflow; respects the zsh-paste caveat in LESSONS-LEARNED.md                                                          |

---

## 14. Stakeholders

| Name             | Role                        | What they need                                                                                  |
|------------------|-----------------------------|--------------------------------------------------------------------------------------------------|
| patterncatalyst  | Author + primary reader     | Working tutorial against Fedora 44; honest reconciliation status; canonical reference link target |

---

## How to use this PRD

Once approved, this document is meant to be:

- The first thing you read at the start of each work session — a
  3-minute scan to recenter on what's being built and why
- The reference when scope creep tempts ("is this in §5? no? then
  it's not in this project")
- The handoff document when a fresh Claude conversation joins
  partway through (paired with `_plans/reconciliation-plan.md`)

When something significant changes (new section added, scope
reduced, a goal dropped), update the relevant section here and
commit the change with a clear message — the audit trail is its
own payoff.

When the project ships, this PRD becomes the record of "what we
intended" against the reconciliation plan's "what we shipped."
The gap between them is usually instructive.

# PRD addition — §17 Capstone: a data mesh on minikube

> Merge instructions: this is a substantial new section to be
> appended to `PRD.md` as the §17 entry, following §16. Treat
> this as a mini-PRD nested inside the main PRD — it has its
> own goals, non-goals, audience, scope, deliverables, risks,
> and iteration plan because the capstone is large enough to
> warrant that structure.
>
> Once merged, delete this file. The reconciliation plan
> entry for r19 covers the planning iteration itself.

---

## §17 Capstone: a data mesh on minikube

### One-sentence summary

A working data-mesh implementation on minikube that demonstrates
*when, how, and why* to use each Kubernetes pattern the tutorial
introduced (in §3–§12), through a five-service domain
(order/inventory/payment/shipping/notification) exposing REST,
gRPC, GraphQL, and Kafka interfaces with full observability,
metadata cataloging, and orchestration.

### What this section teaches

By the end of §17, the reader has seen — and run — a coherent
end-to-end system that integrates everything from earlier
sections plus several capstone-only additions:

- The concept of a **data mesh** (per Zhamak Dehghani's *Data
  Mesh: Delivering Data-Driven Value at Scale*, O'Reilly 2022)
  and why it maps naturally onto Kubernetes
- **Domain-oriented service design**: each of the five services
  owns its data, its API surface, and its operational lifecycle
  — i.e. each is a "data product" in the data-mesh sense
- **Multi-protocol communication**: REST (external clients),
  gRPC (synchronous internal), GraphQL (federated query),
  Kafka (asynchronous events) — and the reasoning for choosing
  each protocol in each context
- **Self-serve data infrastructure**: shared platform pieces
  (Kafka, observability stack, metadata catalog) that data
  products consume but don't own
- **Federated computational governance**: API registry
  (Apicurio), schema registry, metadata catalog
  (OpenMetadata), Istio policy enforcement — all serving as
  the "control plane" for the mesh
- **Patterns from *Kubernetes Patterns* by Ibryam & Huss**
  (O'Reilly, 2nd ed. 2023) applied in context — referenced
  explicitly each time one shows up in the implementation

The reader doesn't read about data mesh — they deploy one.

### Why this is the capstone

§17 is intentionally where everything converges. It uses:

| Earlier section | What it contributes to §17 |
|---|---|
| §1 Prerequisites | Same Fedora 44 baseline + inotify limits |
| §2 Tooling install | kubectl, helm, hey, yq + new: `buf`, `grpcurl`, `ghz` |
| §3 Starting minikube | Dedicated `capstone` profile, sized for the workload |
| §4 Profiles | Profile isolation — §17 doesn't touch §6–§12 profile state |
| §5 Addons | metrics-server (required for autoscaling) |
| §6 Deploy via kubectl | Imperative deploys for ad-hoc troubleshooting |
| §7 NodePort | Same slirp4netns tunnel pattern for external access |
| §8 Persistent Volumes | Each service's Postgres uses PVs (per-domain ownership) |
| §9 helm | Every deployable is a helm chart (or umbrella chart) |
| §10 Editor/shell | k9s, kubectx for navigating the larger cluster state |
| §11 Istio | mTLS between services, traffic shifting, fault injection |
| §12 KEDA + Strimzi | Kafka consumer-lag scaling, HTTP add-on for API tiers |

Capstone-only additions: Apicurio (API + schema registry),
OpenMetadata (metadata catalog), Prometheus + Grafana + Tempo
+ OTEL Collector (observability), Prefect (orchestration),
PostgreSQL (per-service data stores), application code in
Python/FastAPI.

### Audience details

**Primary**: a reader who has worked through §1–§16 and wants
to see the patterns applied in a coherent system. They're
comfortable with the individual sections in isolation and want
to know how the pieces fit together at scale.

**Secondary**: an architect or tech lead evaluating "would
this approach work for my team?" The capstone is the answer
to "show me, don't tell me."

**Not for**: anyone trying to learn Kubernetes basics from
the capstone alone. §17 assumes everything in §1–§12 was
read and at least skimmed. The capstone explains *how* the
pieces combine; it doesn't re-explain what the pieces are.

### Goals

- Build a working multi-service application that demonstrates
  REST + gRPC + GraphQL + Kafka communication patterns in
  one coherent system
- Show each communication choice's *reasoning* — not just
  "we used gRPC here" but "gRPC because (a) internal-only,
  (b) low-latency required, (c) typed contracts useful, (d) no
  browser clients"
- Deploy the full stack to a single dedicated `capstone`
  minikube profile, with the entire stack manageable via
  helm umbrella chart
- Demonstrate observability that's *actually useful* — golden
  signals visible per-service in Grafana, distributed traces
  in Tempo, mesh-level observability in Kiali
- Demonstrate KEDA scale-to-zero and scale-up behavior for
  both HTTP traffic and Kafka consumer lag, in the same
  cluster as the rest of the system
- Provide test artifacts (curl + hey + ghz + Postman
  collections) that a presenter can run live to demonstrate
  the system to an audience
- Reference *Kubernetes Patterns* (Ibryam & Huss) by name
  whenever a relevant pattern is applied (Health Probe,
  Sidecar, Stateful Service, Service Discovery, etc.)

### Non-goals

- **Production readiness.** The capstone runs on one
  workstation. Multi-region, HA, certificate rotation,
  disaster recovery, secrets management at scale — all
  explicitly out of scope
- **Authentication / authorization beyond mTLS.** Istio's
  mTLS-between-pods is the entire security model. No OAuth,
  no JWT, no per-user authorization. Demonstrating a real
  auth flow is a separate project
- **Performance benchmarking.** We'll use hey/ghz to
  generate load for demos, but the goal is *visible behavior*
  (KEDA scaling, traces appearing in Tempo) not benchmarking
- **Comprehensive test coverage.** We're showing test
  *patterns* (one Postman collection per service, one ghz
  script per gRPC endpoint, one curl-based REST smoke test)
  — not 95% line coverage
- **Real metadata-mesh governance.** OpenMetadata runs, holds
  the five services' schemas, and is browsable. We don't
  implement data-quality rules, lineage tracking beyond what
  OpenMetadata infers automatically, or governance workflows
- **Frontend / UI.** Postman and a browser pointed at
  Apicurio / OpenMetadata / Kiali / Grafana are the entire
  "UI." No custom dashboards built for this project
- **Cross-platform support.** Fedora 44 only, same as the
  rest of the tutorial

### Architecture overview

Five domain services, each a "data product":

| Service | Owns | REST | gRPC | GraphQL | Kafka (produces) | Kafka (consumes) |
|---|---|:-:|:-:|:-:|:-:|:-:|
| order-service | Orders | ✓ (clients) | ✓ (called by frontend gw) | ✓ (federated) | `orders.placed` | — |
| inventory-service | Stock levels | ✓ (admin) | ✓ (called by order) | ✓ (federated) | `inventory.updated` | `orders.placed` |
| payment-service | Payments | — | ✓ (called by order) | ✓ (federated) | `payments.processed` | `orders.placed` |
| shipping-service | Shipments | — | ✓ (called by order) | ✓ (federated) | `shipments.dispatched` | `payments.processed` |
| notification-service | Notifications | — | — | — | — | `orders.placed`, `payments.processed`, `shipments.dispatched` |

Each service has its own Postgres schema (or its own database
within a shared cluster — TBD per resource budget).

**Communication patterns demonstrated:**

- **REST (external)**: order-service exposes `/orders` for
  external clients. Goes through Istio ingress gateway
- **gRPC (internal)**: order-service calls
  inventory-service / payment-service / shipping-service via
  gRPC for synchronous coordination. Demonstrates protobuf-first
  contracts and `buf` codegen
- **GraphQL (federated query)**: a small federated gateway
  (Strawberry-based, Python) stitches subgraphs from
  order/inventory/payment/shipping. Demonstrates GraphQL as a
  query layer over polyglot backends
- **Kafka (events)**: notification-service consumes the entire
  event stream. inventory-service, payment-service,
  shipping-service consume their relevant upstream events.
  Demonstrates event-driven coordination + KEDA scaling on
  consumer lag

**Platform components:**

| Component | Why |
|---|---|
| Strimzi + Kafka | Async event backbone; KEDA consumer-lag scaling target |
| Apicurio Registry | OpenAPI specs (REST), proto descriptors (gRPC), Avro/JSON schemas (Kafka) |
| OpenMetadata | Catalog of all services' APIs, schemas, lineage |
| Istio + Kiali | mTLS, traffic shifting, fault injection, mesh visualization |
| KEDA + HTTP add-on | Scale order-service on HTTP request rate; scale Kafka consumers on lag |
| Prometheus + Grafana + Tempo + OTEL Collector | Metrics + traces; per-service golden signals; distributed-trace correlation |
| Prefect | Orchestration of cross-service flows (nightly inventory reconciliation, scheduled metadata sync to OpenMetadata) |
| PostgreSQL | Per-service data stores; backing store for Apicurio and OpenMetadata |
| helm umbrella chart | Single `helm install capstone` deploys everything |

### Architecture diagram (to be drafted)

A new diagram pair `assets/diagrams/17-capstone-data-mesh.svg`
+ `.excalidraw` in the established style (920×500 viewBox,
#fdfbf7 background, blue/tan/neutral palette, sans for prose,
mono for CRDs). The diagram will show:

- Three horizontal layers: **clients** (top), **mesh** (middle,
  the five services + Istio sidecars), **platform** (bottom:
  Kafka, observability, registries, Postgres)
- Lines indicating protocol: solid blue for REST, dashed green
  for gRPC, dotted orange for GraphQL, double red for Kafka
- Istio sidecars rendered as small adjacent boxes on each
  service (consistent with §11's mesh diagram)
- Observability arrows going *out of* each service to the OTEL
  Collector, then fanning out to Prometheus / Grafana / Tempo
- Kafka topic arrows showing publish/consume relationships
  between services

Diagram lands in r20a (after architectural decisions are
confirmed); we draft in prose now to avoid premature
commitment.

### Implementation constraints

- **UBI base images preferred.** Where a UBI variant of a
  required image doesn't exist or is significantly behind
  (e.g. Strimzi, KEDA, Apicurio, OpenMetadata operator
  images), use the upstream image and **explicitly note it
  in the chart values and in the §17 prose**. Maintain a
  "UBI vs upstream" table in the §17 narrative
- **Single `capstone` minikube profile.** Sized at 24GB RAM /
  16 CPU. Reader stops the `minikube` / `istio` profiles
  before running the capstone (documented in §17's
  Prerequisites subsection)
- **helm umbrella chart** structure: one top-level chart
  (`charts/capstone/`) with subcharts for each service +
  platform component. Single `helm install` brings up the
  whole stack
- **Python 3.12 + FastAPI** for all services. Pinned versions
  in `pyproject.toml` per service, no pip-on-the-fly
- **`buf` for protobuf** management; generated Python code
  checked into the service repo (not generated at build time)
- **Postman collection per service**; presenter-friendly
  with environment variables for hostnames

### Testing approach

Each service ships with three layers of tests:

1. **Service-local unit + integration** (Python pytest) — runs
   in CI on every PR
2. **Demo scripts** — `examples/17-capstone/demos/*.sh`,
   one per scenario:
   - `demo-rest.sh` — curl the REST surface, watch KEDA scale
     order-service up under hey load
   - `demo-grpc.sh` — ghz against the inventory gRPC service,
     watch Istio mTLS in Kiali
   - `demo-graphql.sh` — federated query showing data from
     multiple services in one response
   - `demo-kafka.sh` — produce orders, watch notifications
     fire via the consumer chain, watch KEDA scale Kafka
     consumers based on lag
   - `demo-orchestration.sh` — trigger a Prefect flow,
     watch it in Prefect UI
3. **Postman collection** (`postman/capstone.postman_collection.json`)
   — one collection with folders for REST, GraphQL, and
   Apicurio Registry endpoints. Each request has an example
   response and pre-request scripts where needed. Goal:
   presenter can demo live to an audience without typing curl

Performance testing tools mentioned but not the focus:
- `hey` for REST load generation
- `ghz` for gRPC load generation
- `jq` for response parsing in demo scripts
- `curl` for one-off REST calls
- GraphQL queries via curl or a small client tool

### Open decisions (resolve before r20)

| # | Decision | Options | Recommendation |
|---|---|---|---|
| 1 | Metadata catalog | DataHub or OpenMetadata | **OpenMetadata** (lighter, Postgres-backed, cleaner Apicurio integration) |
| 2 | Postgres topology | One per service or shared cluster | **One cluster, one schema per service** (resource budget) |
| 3 | Prefect deployment | OSS server self-hosted or Prefect Cloud | **OSS self-hosted** (consistency with rest of tutorial) |
| 4 | gRPC codegen | protobuf-first with `buf` or code-first | **protobuf-first with `buf`** (industry standard, gives us a clean Apicurio registration story) |
| 5 | GraphQL implementation | Federated gateway or schema stitching | **Federated gateway** with Strawberry (Python) — simpler than Apollo Federation, FastAPI-native |
| 6 | Multi-protocol per service | All services expose all 4 protocols, or per-service appropriate protocols | **Per-service appropriate** (table above) — realistic, demonstrates *choice* not *uniformity* |
| 7 | helm chart structure | Umbrella chart or `helmfile` | **Umbrella chart** (subcharts for each service + each platform component, no extra tooling) |
| 8 | UBI vs upstream operator images | Try UBI everywhere, or accept upstream for operators | **Accept upstream for Strimzi/KEDA/Istio/Apicurio/OpenMetadata operators; UBI for our 5 services + custom workloads** (documented per-image) |
| 9 | Capstone profile resource sizing | 24GB / 16 CPU, or smaller | **24GB / 16 CPU** with reader-stopped `minikube`/`istio` profiles (documented prerequisite) |
| 10 | OpenTelemetry collector | DaemonSet, Deployment, or sidecar | **Deployment** with OTLP receiver; services push via OTLP gRPC |

### References

- **Zhamak Dehghani, *Data Mesh: Delivering Data-Driven Value
  at Scale*** (O'Reilly, 2022) — the canonical text. Cited
  explicitly when introducing the four principles
  (domain ownership, data as product, self-serve data
  platform, federated computational governance)
- **Bilgin Ibryam & Roland Huss, *Kubernetes Patterns***
  (O'Reilly, 2nd ed. 2023) — referenced inline when each
  pattern shows up. Likely patterns in scope:
   - *Foundational*: Predictable Demands, Declarative
     Deployment, Health Probe, Automated Placement,
     Image Builder
   - *Behavioral*: Batch Job (Prefect flows),
     Periodic Job, Stateful Service (Kafka, Postgres),
     Service Discovery, Managed Lifecycle
   - *Structural*: Sidecar (Istio proxy, OTEL collector
     sidecar where applicable), Adapter (Prometheus
     exporter sidecars)
   - *Configuration*: EnvVar Configuration, Configuration
     Resource (ConfigMaps + Secrets), Immutable Configuration
  Examples repo: <https://github.com/k8spatterns/examples>
- **`patterncatalyst/cpp-container-optimization-tutorial`**
  and **`patterncatalyst/otel-observability-demos`** — your
  prior work on the Grafana stack running on podman. The
  capstone reuses the OTEL collector + Prometheus + Grafana
  + Tempo configuration patterns from these repos, adapted
  for Kubernetes deployment via helm

### Risks and mitigations

| Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|
| Resource exhaustion under full stack | High | Medium | Profile sized 24GB/16CPU; reader stops other profiles; helm subcharts can be disabled for partial-stack demos |
| OpenMetadata-Apicurio integration friction | Medium | Medium | Use OpenMetadata's REST API for ingestion rather than the official Apicurio connector if it's not mature; document workaround |
| OTEL Collector + Istio sidecar interaction | Medium | Low | Disable Istio injection in observability namespace; explicit non-mesh route for OTLP traffic |
| Helm umbrella chart complexity | Medium | High | Subchart per component; values.yaml organized by component; `helm template` smoke test in CI |
| `buf` codegen drift between services | Low | Medium | Single `proto/` directory at repo root; all services generate from same source |
| Kafka topic schema evolution | Medium | Medium | Use Apicurio's schema registry for Avro/JSON schemas; document the "old + new version" pattern |
| GraphQL federated gateway adds debug complexity | Medium | Medium | Show single-service GraphQL queries first (without gateway), then introduce gateway in a later subsection |
| Prefect server adds another control plane | Medium | Low | Keep Prefect flows minimal — one scheduled flow for metadata sync, one for nightly inventory reconciliation. Don't expand scope |
| Documentation outpaces implementation | High | High | Write each demo's prose *after* the demo runs; reconciliation plan tracks `verified` rows |

### Iteration plan (rough, ~8-12 iterations)

| r## | Phase | Deliverables |
|---|---|---|
| **r19** | Planning | This PRD addition (current iteration) |
| r20 | Skeleton | `examples/17-capstone/` dir structure; helm umbrella chart skeleton; capstone minikube profile recipe; architecture diagram (svg + excalidraw) |
| r21 | First service | order-service: FastAPI + REST + Postgres schema + helm subchart + smoke test |
| r22 | Remaining services | inventory, payment, shipping, notification — REST first, identical pattern to order |
| r23 | gRPC layer | proto definitions, `buf` codegen, gRPC clients/servers, ghz test scripts |
| r24 | GraphQL layer | Per-service GraphQL endpoints + federated gateway |
| r25 | Kafka integration | Topic definitions, schema registry via Apicurio, producers + consumers in services, demo flows |
| r26 | KEDA + Istio wiring | Apply Istio sidecars, KEDA ScaledObjects (HTTP + Kafka), traffic-shifting demo, Kiali walkthrough |
| r27 | Observability | OTEL collector deployment, Prometheus scrape config, Grafana dashboards (per-service golden signals), Tempo tracing setup, OpenMetadata install + auto-ingestion |
| r28 | Prefect orchestration | Prefect server install, flows for metadata sync + nightly reconciliation |
| r29 | Tests + Postman | Postman collection, demo scripts polished, walkthrough prose |
| r30 | Editorial pass + verification | §17 narrative complete, all examples promoted to `verified (Fedora 44)`, audit scripts pass, reconciliation plan close-out |

The numbers above are estimates. Some phases will likely take
two iterations (e.g. r23a / r23b) because integrating a new
protocol always surfaces unanticipated friction.

### Success criteria

§17 ships when:

1. `helm install capstone` brings up the entire stack on the
   `capstone` profile in under 10 minutes
2. All five demo scripts (`demo-rest.sh`, `demo-grpc.sh`,
   `demo-graphql.sh`, `demo-kafka.sh`,
   `demo-orchestration.sh`) pass on Fedora 44
3. Postman collection imports cleanly and every request returns
   a successful response on a freshly-deployed stack
4. Kiali shows the mesh with all five services and observable
   traffic between them
5. Grafana shows per-service request rate, error rate, and
   latency dashboards populated with real data
6. Tempo shows distributed traces spanning at least three
   services (an order placed → inventory checked → payment
   processed flow)
7. OpenMetadata browser shows the five services as data
   products with their schemas auto-ingested from Apicurio
8. KEDA visibly scales order-service from 0 to N when hey
   generates load, and back to 0 after the load stops; same
   for Kafka consumer scaling
9. Cross-references audit script and editorial audit script
   both pass
10. PRD reconciliation document updated with what shipped vs.
    what was planned for the capstone (some divergence is
    expected; record it)

### What "victory" looks like for the capstone

A presenter can sit down at a fresh Fedora 44 machine, run
the §17 setup script, get the stack up in ~10 minutes, and
walk an audience through:

> "Here's an order coming in via REST. Watch the order-service
> scale up under load. Here's it calling inventory and payment
> via gRPC — see them in Kiali. Here's the order-placed event
> firing on Kafka — watch the consumers light up. Here's
> Tempo showing the full distributed trace. Here's
> OpenMetadata showing the schemas. Here's Prefect running
> the nightly reconciliation. Every piece you saw earlier in
> the tutorial — it's all working here, together."

That demo, working start-to-finish, is the victory condition.

---

## Reconciliation-plan note

This r19 iteration ships PRD additions only — no code, no
diagrams yet. The architecture diagram lands in r20 after the
ten open decisions in the table above are resolved. Pre-committing
to architectural detail before those decisions are settled
would just produce work we'd throw away.
