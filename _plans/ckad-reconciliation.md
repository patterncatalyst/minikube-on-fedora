---
title: "CKAD reconciliation — patterns appendix"
---

# CKAD reconciliation for the Kubernetes-patterns appendix

Internal planning artifact (not published; `plans` is `output: false`). Reconciles
the 29 Kubernetes patterns against the CKAD exam so the appendix covers the whole
curriculum, and records what the patterns leave out (the "gap chapters").

Reconciled against the official CNCF / Linux Foundation CKAD curriculum and the
table of contents of *Certified Kubernetes Application Developer (CKAD) Study
Guide, 2nd ed.* (Benjamin Muschko) from reference — no copy is on disk. Items that
could not be verified against a source are flagged **[verify]** for review.

## CKAD domains and weights

| Domain | Weight |
|---|---|
| Application Design and Build | 20% |
| Application Deployment | 20% |
| Application Observability and Maintenance | 15% |
| Application Environment, Configuration and Security | 25% |
| Services and Networking | 20% |

## Pattern → domain map

**Application Design and Build (20%)**
- BatchJob (Job), PeriodicJob (CronJob) — define/run jobs.
- Sidecar, InitContainer, Adapter, Ambassador — multi-container pod design.
- ImageBuilder — build and reference container images.
- StatefulService, StatelessService, PredictableDemands (PVC) — storage/volumes.

**Application Deployment (20%)**
- DeclarativeDeployment — Deployments, rolling vs recreate, rollback.
- (gap) Helm **and** Kustomize — CKAD tests both; the tutorial covers Helm only. → gap chapter.
- Istio canary (from §17) — blue/green & canary context.

**Application Observability and Maintenance (15%)**
- HealthProbe — liveness, readiness, startup probes.
- (gap) logs / exec / port-forward / events / `kubectl debug` ephemeral containers. → gap chapter.
- (gap) API deprecations awareness. **[verify]** fold into the observability gap chapter.

**Application Environment, Configuration and Security (25%)**
- ConfigurationResource, EnvVarConfiguration, ImmutableConfiguration, ConfigurationTemplate — ConfigMaps/Secrets.
- SecureConfiguration — Secrets management (authored from scratch; k8spatterns stub empty).
- AccessControl — ServiceAccount, Role/ClusterRole, RoleBinding (authored from scratch; stub empty).
- ProcessContainment — SecurityContext, Pod Security Standards.
- Operator / Controller — CRDs, extending the API.
- (gap) ResourceQuota, LimitRange — namespace governance. PredictableDemands covers pod-level requests/limits/PriorityClass but not namespace-level quota/limits. → gap chapter.

**Services and Networking (20%)**
- ServiceDiscovery — Service (ClusterIP/NodePort/LoadBalancer), Ingress, DNS.
- NetworkSegmentation — NetworkPolicy (+ Istio AuthorizationPolicy).

## Gap chapters to author

1. **Observability & debugging** — `kubectl logs/exec/port-forward`, events, `kubectl debug` ephemeral containers (capstone has `debug-ephemeral.sh`). Domain: Observability & Maintenance.
2. **Packaging & deploying: Helm & Kustomize** — both tools; Kustomize overlays for the shipping services. Domain: Application Deployment.
3. **Namespace governance** — ResourceQuota, LimitRange, PriorityClass recap. Domain: Environment, Configuration & Security.
4. **CKAD crosswalk (closing chapter)** — table mapping every pattern + gap chapter to its domain/competency, plus a timed self-test task list.

## Knative → KEDA substitutions (per request)

- `foundational/HealthProbe/knative-service.yaml` — dropped; probes shown on plain Deployments only.
- `advanced/ElasticScale` — HPA + VPA retained; **KEDA** (Kafka consumer-lag + HTTP add-on, reusing the capstone ScaledObjects) is the scale-to-zero story that replaces Knative serving.
- `advanced/ImageBuilder` — Knative build lane dropped; in-cluster build shown with Kaniko / `minikube image build`.

## Chapter numbering (within _appendix/k8s-patterns/)

00 index · 01–05 foundational · 06–09 structural · 10–17 behavioral ·
18–21 configuration · 22–25 advanced · 26–29 security · 30–32 CKAD gap ·
33 CKAD crosswalk. (Numbers are the `order:` field; adjust as chapters land.)
