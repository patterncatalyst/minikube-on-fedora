---
title: Appendix live verification log
---

Live, headless verification of the Kubernetes-patterns appendix examples
(`examples/appendix-patterns/`) against a dedicated `mof-patterns` minikube
profile. Status values: PASS, PARTIAL, NEEDS-INFRA, FAIL-then-FIXED, FAIL.

Profile: `mof-patterns` (docker driver, containerd runtime, Calico CNI,
12g/6cpu, kubernetes v1.36.5). Namespace: `patterns`.

| example | status | evidence/notes | date |
|---|---|---|---|
| predictable-demands | PASS | Pod Pending (PVC missing) then CreateContainerConfigError (ConfigMap missing), confirmed via describe events; after applying PVC+ConfigMap+Postgres, pod Ready; `/health`→`{"status":"ok"...}`, `/healthz`→`{"status":"ready"...}`; priorityClassName=patterns-high-priority, resources match manifest. Clean teardown. | 2026-11-01 |
| declarative-deployment | PASS | RollingUpdate v1→v2 + `rollout undo`: 20 curl probes during image bump all returned 200 (zero downtime). Switched to Recreate strategy, re-bumped image: probes showed `200 000 000...` (connection refused during full pod teardown before new ones start) exactly as documented. Clean teardown. | 2026-11-01 |
