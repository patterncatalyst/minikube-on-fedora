---
title: Where to go next
order: 15
description: Concrete next steps after this tutorial — production-like upgrades, deeper resources, and follow-on tutorial ideas worth pursuing.
duration: 5 minutes
---

You've worked through twelve sections of hands-on Kubernetes
on Fedora. This final section names the natural next steps
and the resources worth bookmarking.

The recommendations here are organized as two tracks, not a
single linear path. **Track A** stays on your current machine
and deepens what you've already built. **Track B** moves
toward something more production-like — a real cluster,
real CI, real observability.

## Track A — going deeper on what you've built

Each suggestion below extends a section you've already
finished, so you don't have to start from scratch.

### Run the §12 Kafka demo with a real workload

The `order-processor` consumer in §12 is deliberately trivial
— it sleeps `WORK_SLEEP_S` seconds per message to simulate
work. Replace that sleep with something real: an HTTP call to
an external API, a database insert, image resize via Pillow,
JSON enrichment. Watch how KEDA's scaling behavior changes
when each message takes 100 ms vs. 5 seconds to process. The
`WORK_SLEEP_S` env var on the Deployment lets you experiment
without rebuilding the image.

### Drive sustained load through the §12 HTTP demo

The default `hey -n 500 -c 50` finishes in ~115 ms on
minikube, which isn't long enough to push KEDA past 1 replica.
Swap `-n 500` for `-z 30s` to drive 30 seconds of sustained
load:

```bash
hey -z 30s -c 50 -host nginx.local http://127.0.0.1:18080/
```

You should see peak replicas climb to 3-5 (capped at the
HTTPScaledObject's `replicas.max`). Try also varying the
`scalingMetric.concurrency.targetValue` in the manifest to see
how lower targets make scaling more aggressive.

### Modify Istio's VirtualService for header-based routing

§11's demo split traffic 50/50 between two versions. A more
interesting pattern is **header-based routing**: requests with
`X-Test: canary` go to v2, everything else stays on v1. Edit
`samples/bookinfo/networking/virtual-service-reviews.yaml` to
add a `match` block on headers, re-apply, and verify in Kiali
that traffic only flows to v2 when you send the header. This
is the canary-deployment pattern in microcosm.

### Try multi-broker Kafka

The §12 Strimzi setup is a single-broker development cluster.
Production Kafka uses 3+ brokers with replication. Edit
`kafka-cluster.yaml` to split the dual-role node pool into two
node pools (one `roles: [controller]` with 3 replicas, one
`roles: [broker]` with 3 replicas), increase replication
factors to 3, and watch Strimzi roll out the bigger topology.
The KEDA ScaledObject doesn't need to change — same trigger,
bigger backing cluster.

## Track B — moving toward something production-like

### Replace NodePort with Ingress + TLS

§7's NodePort approach works for local development but isn't
how you'd expose a service in production. The standard
pattern is **ingress-nginx** for the controller plus
**cert-manager** for automatic TLS certificate provisioning.
Both are helm-installable and follow the same operator
pattern as Strimzi and KEDA.

```bash
# minikube has an addon for ingress-nginx
minikube addons enable ingress -p minikube

# cert-manager comes via helm
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --set installCRDs=true
```

Then define an `Ingress` resource pointing at your existing
nginx Service. cert-manager handles ACME / Let's Encrypt
certificate issuance automatically once you give it a
`ClusterIssuer`. Real public DNS is required for the ACME
HTTP-01 challenge to work — use a personal domain you control,
not localhost.

### Adopt GitOps with ArgoCD or Flux

Manual `kubectl apply` is fine for tutorials but doesn't scale
to a team. Both [ArgoCD](https://argo-cd.readthedocs.io/) and
[Flux](https://fluxcd.io/) treat a Git repository as the
source of truth for cluster state — you commit a manifest
change, the cluster picks it up.

ArgoCD has a richer UI (web console showing application sync
status); Flux is more decomposable into separate
single-purpose controllers and feels more Unix-y. Either
works on minikube via helm install — pick one, push the
manifests from this tutorial's `examples/` into a Git repo,
and watch the cluster reconcile to match.

### Build a real observability stack

§11's Istio addons (Kiali, Prometheus, Grafana, Jaeger, Loki)
were shipped as a sample, not a production install. The
standard production stack is the
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
helm chart — it packages Prometheus, Grafana, alertmanager,
and a sensible default set of dashboards and alerts.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
    --namespace monitoring --create-namespace
```

For traces, [Tempo](https://grafana.com/oss/tempo/) (Grafana's
trace store) integrates with kube-prometheus-stack out of the
box. The CNCF
[observability whitepaper](https://github.com/cncf/tag-observability/blob/main/whitepaper.md)
is a solid overview when you're picking from scratch.

### Move beyond minikube to real hardware

The patterns in this tutorial work unchanged on a real
multi-node cluster. The simplest options:

- **[k3s](https://k3s.io/)** on a handful of small VMs or a
  Raspberry Pi cluster. The §13 prose covers k3s in more
  detail; it's the lightest-weight path to a real cluster
- **[kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/setup-ha-etcd-with-kubeadm/)**
  on a few standard servers if you want stock upstream
  Kubernetes
- A **managed service** (GKE, EKS, AKS) if you want to skip
  the control-plane operations entirely

In all three cases, the manifests in `examples/` apply
without modification. That's the point of Kubernetes being a
standard interface.

### Build a CI pipeline that pushes to your cluster

A natural workflow: a developer pushes code, GitHub Actions
builds an image, pushes it to a registry, updates a
Kubernetes manifest in a separate Git repo, and ArgoCD
picks up the change and rolls it out. Lots of moving parts,
but each piece is straightforward in isolation.

- **[GitHub Actions docs](https://docs.github.com/en/actions)**
  for the build-and-push pipeline
- **[ko](https://ko.build/)** as an alternative to `podman
  build` for Go services — it handles the image-building step
  with no Containerfile
- **[ArgoCD auto-sync](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)**
  for the rollout step

## Useful resources to bookmark

- **[kubernetes.io](https://kubernetes.io/docs/home/)** — the
  official documentation. The concepts section is excellent
  reference material once you've gotten your hands dirty.
  Search-friendly, kept current, no marketing fluff
- **[CNCF landscape](https://landscape.cncf.io/)** — an
  interactive map of every CNCF project and adjacent tool.
  Overwhelming at first glance, useful when you have a
  specific problem ("I need a workflow engine") and want to
  see your options sorted by maturity and adoption
- **[Istio docs](https://istio.io/latest/docs/)** — if §11
  was interesting, the official docs go much deeper into
  traffic management, security policies, and observability
- **[KEDA scalers catalog](https://keda.sh/docs/scalers/)** —
  the full list of 70+ event sources KEDA can scale on. You've
  seen Kafka and HTTP; there's also Prometheus queries, AWS
  SQS, GCP Pub/Sub, cron schedules, NATS, RabbitMQ, Azure
  Service Bus, and many more
- **[Strimzi docs](https://strimzi.io/docs/operators/latest/)**
  — for going beyond the single-broker development setup.
  Production Kafka involves rack-aware replication,
  KafkaConnect for moving data in and out, MirrorMaker 2 for
  cross-cluster replication, and ACL management
- **[Programming Kubernetes](https://www.oreilly.com/library/view/programming-kubernetes/9781492047094/)**
  (Hausenblas & Schimanski, O'Reilly) — the go-to book if you
  want to write your own operators. Assumes you're already
  comfortable with the basics this tutorial covered
- **[Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)**
  (Kelsey Hightower) — bootstrap a cluster manually with no
  helpers. Tedious but illuminating; you'll understand what
  minikube/kind/k3s are abstracting once you've done this once

## Possible follow-on tutorials

If you're considering writing your own, here are gaps in the
Fedora-Kubernetes documentation landscape that would be
valuable to fill:

- **Production-grade single-node home cluster.** Take what's
  in this tutorial, move it from minikube to k3s on bare
  metal, add ingress-nginx + cert-manager + an ACME issuer
  pointing at a real domain, deploy a useful service (a
  Nextcloud, a Plex, a personal git host), and document the
  full setup including backups
- **Air-gapped Kubernetes on Fedora.** Many enterprise
  Fedora/RHEL users need this. Loading images from a local
  registry, dealing with no-internet operators, certificate
  generation for the cluster itself
- **GPU workloads on minikube with NVIDIA Container
  Toolkit.** ML inference / training on a workstation,
  scaling via KEDA based on queue depth
- **A "what changed?" tutorial for Kubernetes upgrades.**
  Picking a specific version pair (e.g., 1.34 → 1.36) and
  walking through what manifests need updating, what API
  versions deprecated, and how to test the upgrade safely

If you write any of these, the hands-on, prose-heavy, honest-
about-what-was-hard style this tutorial used translates well
— it's how people actually learn complex systems.

---

That's the tutorial. Kubernetes is large, but you don't have
to learn it all at once. You learned what's here by getting
your hands on it — the same approach scales to the next
thing.

[← Back to outline]({{ "/" | relative_url }})
