---
title: Wrap-up
order: 13
description: A closing recap — what you've built, the patterns that kept coming up, and concrete pointers for the natural next steps.
duration: 10 minutes
---

You've reached the end of the tutorial proper. Twelve sections
and a fair number of running examples behind you, this is the
moment to step back and look at the whole thing.

## What you've built

The state on your laptop right now, assuming you've worked
through every section:

- A **minikube cluster** running rootless on top of Podman with
  the containerd runtime, configured per §3 — your main playground
  for §3–§10 and §12
- Optionally, a **second `istio` profile** from §11, holding an
  Istio control plane (istiod + ingress/egress gateways) with
  the Bookinfo sample app and the Kiali/Prometheus/Grafana/Jaeger
  observability stack
- A small **collection of UBI-based container images** cached in
  the minikube profile: `nginx-custom:v1` (§6, reused in §7, §9,
  §12 HTTP) and `order-processor:v1` (§12 Kafka)
- The **kubectl + helm CLIs** installed natively (no sudo, no
  package manager workarounds), with a sensible set of plugins
  and aliases from §10
- And — separate from the cluster itself — a **set of working
  example directories** under `examples/` that you can come back
  to as references whenever you need to remember how a pattern
  fits together

If you took the iterative approach the tutorial encourages — run
each demo, read the prose around what just happened, then move
on — by now you should also have:

- A working mental model of the **Deployment → Service →
  Pod** relationship and why each piece exists separately (§6, §7)
- An understanding of when **PersistentVolumes** are appropriate
  vs. ephemeral state, and the init-container pattern for seeding
  data (§8)
- Familiarity with **helm** as both a package manager and a
  templating engine, including the checksum-annotation trick for
  triggering rollouts on ConfigMap changes (§9)
- A feel for the **operator pattern** — what makes Istio's mesh
  installer (§11) and KEDA's scaler controller (§12) different
  from raw `kubectl apply`, and when the trade-off favors each
- Calibration on **scale-to-zero** as a primitive, with two
  separate triggers (Kafka consumer lag and HTTP request
  concurrency) that you've seen drive the same 0→N→0 lifecycle

That last point is worth lingering on. Kubernetes started as a
container orchestrator for steady-state long-running workloads.
HPA brought reactive scaling on CPU and memory. KEDA's
contribution — and the reason the §12 section is in this tutorial
at all — is to **drive scaling from any event source**, including
sources that have nothing to do with the workload's own resource
usage. That's a meaningful conceptual shift, and the pattern
shows up far beyond Kubernetes (serverless platforms, event-
driven microservices, batch processing pipelines).

## Patterns that kept coming up

A few recurring themes are worth naming explicitly, because
they're choices you'll keep making in any Kubernetes project of
your own.

**Rootless containerd via the podman driver.** Every minikube
profile in this tutorial uses the same set of flags:
`--container-runtime=containerd --rootless=true` with the podman
driver. On Fedora that's the path of least resistance — Podman
is the default container engine, the user-space namespace setup
is already in place, and there's no daemon to fight with.

**UBI as the runtime base.** Red Hat's Universal Base Image
showed up in §6, §11 (indirectly, via Istio's images), and §12.
The reason it kept appearing: UBI is **freely redistributable**,
has **predictable update cadences** tied to RHEL minor releases,
and the **ubi9-minimal** variant is small enough for runtime
images while ubi9 (the full image) has dnf for the builder stage
of a multi-stage build. The combination of legal clarity and
operational consistency is hard to beat for any organization
already comfortable with the RHEL ecosystem.

**Multi-stage builds.** Both `nginx-custom` and `order-processor`
use the same two-stage pattern: a full UBI image for the build
stage (where you have dnf, pip, compilers, and disk space to
burn), then a minimal UBI runtime stage that only copies forward
the artifacts the running container needs. The result is final
images in the 100–300 MB range with no build tooling exposed.

**The operator pattern for stateful workloads.** Strimzi for
Kafka, Istio's control plane, KEDA's scaler controller — each is
a Kubernetes-native operator that watches custom resources and
reconciles them into real cluster state. The operator pattern
was originally CoreOS's idea and has become the dominant model
for shipping complex software on Kubernetes. The recurring shape:
install the operator once via helm, then declare what you want
via custom resources, then leave the operator alone to do its
job.

**Defensive scripting around external dependencies.** Every
`setup-*.sh` and `demo.sh` in this tutorial has the same
defensive structure: pre-flight checks that fail fast with
useful messages, idempotent install operations that work whether
or not state already exists, and diagnostic dumps that fire when
something goes wrong rather than leaving you guessing. The
reason this came up early and stayed throughout is that **most
of the time wasted in a Kubernetes project is spent debugging
state**, not writing manifests. Scripts that proactively dump
the relevant state on failure are worth their weight in saved
hours.

**Honesty about what you actually verified.** Section 12 spent
six sub-iterations because the original HTTP demo's assertions
were too forgiving — it claimed success when all 500 requests
had actually returned 404. The lesson generalizes: **a test that
can't fail isn't a test**. When you write an assertion, ask
yourself how a real failure would actually look in the output,
and make sure your check would notice it. "Did I get any HTML
back" is not the same check as "did I get the HTML I expected
from the server I expected."

**Inotify limits matter at multi-cluster scale.** A finding
from §11 worth elevating: the default `fs.inotify.max_user_instances`
on Fedora is sized for one minikube cluster, not two. The moment
you bring up a second profile (§11's `istio` profile) the cluster
operator hits `Too many open files` errors and fails reconciliation
in opaque ways. The fix is a one-line sysctl change. The lesson:
**Linux kernel limits exist, and you'll hit them eventually**.
When you do, the symptom won't look like a kernel issue — it'll
look like a Kubernetes operator misbehaving.

## Where to go next

You've built a learning environment. The natural next steps
fall into two buckets: **going deeper on what you already have**,
and **moving toward something more production-like**.

### Going deeper on what you've built

- **Try the §12 Kafka demo with a real workload.** Replace the
  `order-processor` Python consumer with a service that does
  meaningful processing — image resize, JSON enrichment,
  database writes — and watch how KEDA's scaling behavior
  changes when each message takes 100ms vs. 5 seconds to
  process. The tutorial's `WORK_SLEEP_S` environment variable
  lets you experiment without rebuilding the image
- **Drive the §12 HTTP demo with sustained load.** Swap
  `-n 500` for `-z 30s` (run hey for 30 seconds continuously)
  and watch KEDA scale the workload to higher peaks. The §12
  prose notes that the default `-n 500` finishes too fast on
  minikube to actually exercise scaling past 1 replica
- **Inspect Istio with custom traffic.** Run a load generator
  against the Bookinfo `productpage` and watch the Kiali traffic
  graph update in real time. Then try modifying the
  `VirtualService` to do header-based routing (e.g., requests
  with `X-Test: canary` go to v2 of `reviews`) and verify the
  split in Kiali

### Moving toward something more production-like

- **Replace NodePort with proper Ingress.** §7's NodePort
  approach works for local development but isn't how you'd
  expose a service in production. The standard pattern is
  [ingress-nginx](https://kubernetes.github.io/ingress-nginx/)
  for the controller plus [cert-manager](https://cert-manager.io/)
  for automatic TLS certificate provisioning. Both are
  helm-installable and follow the same operator-pattern shape
  as Strimzi and KEDA. minikube has an `ingress` addon that
  installs ingress-nginx for you — `minikube addons enable
  ingress -p minikube`
- **Adopt GitOps with ArgoCD or Flux.** Manual `kubectl apply`
  is fine for tutorials but doesn't scale to a real team. Both
  [ArgoCD](https://argo-cd.readthedocs.io/) and
  [Flux](https://fluxcd.io/) treat a Git repository as the
  source of truth for cluster state, reconciling the cluster
  toward the repo automatically. You commit a manifest change;
  the cluster picks it up. ArgoCD has a nicer UI; Flux is more
  decomposable into separate controllers
- **Set up a real observability stack.** §11's Istio addons
  shipped Prometheus, Grafana, Loki, and Jaeger — but as a
  sample, not a production install. The standard stack for
  metrics is the [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
  helm chart, which packages Prometheus, Grafana, and
  alertmanager together with sensible defaults. For logs,
  Loki or Elasticsearch. For traces, Jaeger or Tempo. The
  CNCF [observability whitepaper](https://github.com/cncf/tag-observability/blob/main/whitepaper.md)
  is a solid overview if you're picking from scratch
- **Try a multi-node cluster on real hardware.** §4 showed how
  to bring up multi-node minikube profiles, but everything ran
  on a single machine. The next step is
  [k3s](https://k3s.io/) (lightweight, ARM-friendly, fits on a
  Raspberry Pi cluster) or [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/setup-ha-etcd-with-kubeadm/)
  on a few VMs. The mechanics are the same as minikube; the
  storage and networking concerns multiply
- **Build a CI pipeline that pushes to your cluster.** A
  natural workflow: a developer pushes code, GitHub Actions
  builds an image, pushes it to a registry, updates a
  Kubernetes manifest in a separate Git repo, and ArgoCD
  picks up the change and rolls it out. Lots of moving parts,
  but each piece is straightforward in isolation. The
  [GitHub Actions docs](https://docs.github.com/en/actions)
  + ArgoCD's [auto-sync documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)
  cover what you need

### Useful resources to bookmark

- **[kubernetes.io](https://kubernetes.io/docs/home/)** — the
  official documentation. The concepts section is excellent
  reference material once you've gotten your hands dirty.
  Search-friendly, kept current, no marketing fluff
- **[The CNCF landscape](https://landscape.cncf.io/)** — an
  interactive map of every CNCF project and adjacent tool.
  Overwhelming at first glance, but useful when you have a
  specific problem ("I need a workflow engine") and want to
  see your options
- **[Istio docs](https://istio.io/latest/docs/)** — if §11
  was interesting, the official docs go much deeper into
  traffic management, security policies, and observability
  patterns
- **[KEDA scalers catalog](https://keda.sh/docs/scalers/)** —
  the full list of 70+ event sources KEDA can scale on. You've
  seen Kafka and HTTP; there's also Prometheus queries, AWS
  SQS, GCP Pub/Sub, cron schedules, NATS, RabbitMQ, and
  many more
- **[Strimzi docs](https://strimzi.io/docs/operators/latest/)** —
  for going beyond the single-broker development setup §12 used.
  Production Kafka involves rack-aware replication, KafkaConnect
  for moving data in and out, MirrorMaker 2 for cross-cluster
  replication, and ACL management via `KafkaUser` resources

## A closing thought

Kubernetes is large. The CNCF landscape page has over a thousand
projects on it; the official Kubernetes documentation alone runs
to tens of thousands of words. It's tempting to look at the
scope and feel like you have to learn it all before you can do
anything useful.

You don't. You learned what's in this tutorial by getting your
hands on it — running each demo, watching it succeed or fail,
reading the prose around what just happened. The same approach
scales to the next thing. Pick a problem you actually have,
find the smallest tool in the landscape that addresses it, and
work through getting it running end-to-end. Then write down
what you learned in your own words — even if it's just a README
in a repo of your own.

The hard part of getting good at Kubernetes is the same as the
hard part of getting good at any technology: it's the patience
to debug something concrete instead of consuming abstract
overviews. That's what this tutorial tried to encourage — not
because it's the only way, but because for most people it's the
way that actually sticks.

Good luck with whatever you build next.

---

[← Back to outline]({{ "/" | relative_url }})
