# Plan: Docker Engine + published NodePorts (r29)

Started 2026-10-09 on branch `feat/docker-engine-nodeports` from main `c1baef6`.

## Decisions (user, 2026-10-09)

- minikube runs `--driver=docker --container-runtime=containerd` (runc) on
  **Docker Engine** (`docker-ce`, `/var/run/docker.sock`, context `default`).
  Docker Desktop is never a requirement. Podman leaves the minikube path.
  Don't mix runtimes (podman→crun, containerd→runc).
- Podman problems are kept as lessons (LESSONS-LEARNED Part 4, one FAQ entry,
  one §13 note), not scattered through chapters.
- No `kubectl port-forward`, `minikube tunnel`, `minikube service`,
  `kubectl proxy`, `istioctl dashboard` or SSH tunnels. Every host-facing
  Service is a NodePort published at profile creation as
  `--ports=127.0.0.1:<host>:<nodePort>`. Existing host ports are kept.
- Fedora, Fedora VMs, RHEL, RHEL VMs only; no other OS is named.
- Pinned stable versions only.
- **D1: shared slot.** §6, §8, §9 and §12-http each hold nodePort 30080 →
  127.0.0.1:18080 only while they run; a preflight fails with "delete X first"
  if another Service holds 30080.
- **Hygiene in scope:** stale copies (`examples/17-capstone/examples/`, root
  `17-capstone.md`, `examples/17-capstone/_plans/`), untrack `__pycache__`,
  stop printing default credentials, pin `:latest` tags / unpinned charts /
  `stable.txt` / `@latest`. `onboarding/CLAUDE-PROJECT-CHAT-CHANGE.md` stays.

## Approach

- Every profile: `--driver=docker --container-runtime=containerd
  --kubernetes-version=v1.35.1 --ports=…`. No `--rootless`,
  `MINIKUBE_ROOTLESS`, `minikube config set`, podman volume/port calls.
- Images: `docker build -f Containerfile -t X .` then
  `minikube -p P image load X`; one `build_and_load` helper. Capstone drops
  the registry addon and `localhost:5000`; bare names, `pullPolicy: Never`,
  `rollout restart` after load (supersedes CAP-007/009/010/015).
- Services this repo owns get NodePort natively. Third-party/addon Services
  (dashboard, istio-ingressgateway, Kiali, Grafana, Prometheus, Tempo,
  tracing, OpenMetadata, KEDA interceptor, Postgres) get a **companion
  NodePort Service** this repo owns, selecting the same pods, so
  `helm upgrade` / `istioctl install` / addon re-apply never revert it.
  Verify each selector live with `get svc -o jsonpath='{.spec.selector}'`.
- Demos assert the port is published (`docker port <profile> <nodePort>/tcp`)
  and fail with the delete-and-recreate command otherwise.
- Every script pins its context (`--context`, `--kube-context`, `-p`).
- Port maps live in `scripts/lib/_helpers.sh` (core, istio, driver-check) and
  `examples/17-capstone/scripts/lib/env.sh` (capstone);
  `scripts/check-port-map.sh` cross-checks them against YAML and docs.
- `scripts/editorial-audit.sh --strict` fails on reintroduced
  tunnel/podman-driver/other-OS strings. Exemptions:
  `<!-- policy-exempt:start -->`…`<!-- policy-exempt:end -->` in Markdown,
  trailing `# policy-exempt` in shell/YAML.
- `_plans/*` history gets dated superseded banners and appended entries; old
  text is not rewritten, nothing is promoted to verified.

Rejected: `kubectl patch` on third-party Services (reverted by upgrades);
keeping the registry addon (images lost on stop/start); `minikube image
build` only (per-profile, was unreliable); one profile per example (slow,
breaks the §6–§9 narrative); `$(minikube ip):nodePort` (URL changes on
recreate); `0.0.0.0` publishing (exposes dashboard/Kiali to the LAN).

## Blocking findings

1. Profile `capstone` collides with datamesh-reference-arch-python's profile:
   `setup-capstone-profile.sh --replace` / `teardown.sh --remove-profile`
   would delete it. Rename to **`mof-capstone`** (namespace stays `capstone`).
2. The host's docker context is `desktop-linux`; minikube follows it.
   `require_docker_engine` fails unless context is `default` on
   `unix:///var/run/docker.sock`.
3. Demos 06–09 and most capstone demos don't pin a context.
4. `setup-capstone-profile.sh:163` runs `minikube config set rootless true`
   (global). Remove; never run `minikube config set`.

## Port maps

### `minikube` (default; §5–§9, §12) — `CORE_PORTS`

`127.0.0.1:18080:30080,127.0.0.1:18081:30808,127.0.0.1:18090:30900`

| Example | Service (ns) | port→target | nodePort | host |
|---|---|---|---|---|
| §6 | `nginx` (default) | 80→8080 | 30080 | 18080 |
| §7 | `nginx-np` | 80→8080 | 30808 | 18081 |
| §8 | `nginx-pv` | 80→8080 | 30080 (shared) | 18080 |
| §9 | release Service | 80→http | 30080 (shared) | 18080 |
| §12-http | companion `keda-interceptor-host` (keda) | 8080→8080 | 30080 (shared) | 18080 |
| §5 | companion `dashboard-host` (kubernetes-dashboard) | 80→9090 | 30900 | 18090 |

### `driver-check` (§3) — `127.0.0.1:18079:30079`

### `istio` (§11) — `ISTIO_PORTS`

`127.0.0.1:8080:30880,127.0.0.1:20001:30201,127.0.0.1:3000:30300,127.0.0.1:9090:30990,127.0.0.1:16686:31686`

| Companion (istio-system) | target | nodePort | host |
|---|---|---|---|
| `ingressgateway-host` | 80→8080 | 30880 | 8080 |
| `kiali-host` | 20001 | 30201 | 20001 |
| `grafana-host` | 3000 | 30300 | 3000 |
| `prometheus-host` | 9090 | 30990 | 9090 |
| `tracing-host` | 80→16686 | 31686 | 16686 |

### `mof-capstone` (§17) — `CAPSTONE_PORTS` in `env.sh`

| Service (ns) | nodePort | host |
|---|---|---|
| order-service (capstone) | 30180 | 18080 |
| inventory-service (http) | 30182 | 18082 |
| payment-service | 30183 | 18083 |
| shipping-service | 30184 | 18084 |
| apicurio | 30185 | 18085 |
| review-service | 30186 | 18086 |
| notification-service | 30197 | 18097 |
| graphql-gateway | 30199 | 18099 (walkthrough's 8080 moves here) |
| openmetadata (companion) | 30585 | 8585 (`L_OM` 18585 → 8585) |
| postgres primary (companion `capstone-postgres-host`) | 30432 | 5432 |
| istio-ingressgateway (companion) | 30880 | 8080 |
| keda interceptor (companion) | 30881 | 8081 (trace-flow 8082 → 8081) |
| kiali (companion) | 30201 | 20001 |
| prometheus-server (observability) | 30090 | 9090 |
| grafana (observability) | 30300 | 3000 |
| tempo http | 30320 | 3200 (trace-flow 3201 → 3200) |
| tempo otlp-http | 30418 | 4318 |

## Steps

| # | Step | Depends on | Status |
|---|---|---|---|
| 0 | Hygiene: delete stale copies, untrack `__pycache__`, `.gitignore` | — | done |
| 1 | Shared tooling: `_helpers.sh` (`require_docker_engine`, port maps, `ensure_profile`, `require_published_port`, `build_and_load`, `pin_context`, `require_free_nodeport`, docker `cleanup_container`), `audit-fedora-prereqs.sh` Docker Engine section, `test-template.sh`, `scripts/README.md`, root `setup-{keda,strimzi,istio}.sh` context pins, new `check-port-map.sh`, `editorial-audit.sh` policy check + `--strict` (+ optional CI step) | 0 | done |
| 2 | Core examples 03, 06, 07, 08, 09 (manifests, chart, demo.sh, READMEs); pin 08 initContainer image | 1 | done (live pending) |
| 3 | Examples 11-istio (+ `host-access/`), 12-keda-http (+ interceptor companion), 12-keda-kafka | 1 | todo |
| 4a | Capstone platform: `scripts/lib/env.sh`, `mof-capstone`, setup/build/cluster/bootstrap/setup-* scripts, subchart values+service templates, `host-access/*.yaml`, pin observability charts, no credential printing | 1 | todo |
| 4b | Capstone demos: env.sh, no port-forward, host ports, no `localhost:5000` guard, no credentials | 4a | todo |
| 4c | Capstone prose: README, order-service README, `_capstone/data-mesh/*`, `capstone/data-mesh.html` | 4a | todo |
| 5a | Chapters §0–§5 (Docker Engine install in §1, pinned installs in §2, §3 rewrite, §4 profiles, §5 dashboard companion) | 2,3 | todo |
| 5b | Chapters §6–§10 (§7 rewrite around published ports) | 2,3 | todo |
| 5c | Chapters §11–§17, FAQ, LESSONS-LEARNED (Part 4: why we moved off rootless podman; remove stale merge banners / misplaced PRD block after checking PRD) | 2,3,4a | todo |
| 6 | README, PRD, CONTRIBUTING, onboarding, examples/README, index.html, Gemfile comment, `03-minikube-topology.svg` labels | — | done |
| 7 | Historical annotations: reconciliation-plan (banners, new unverified rows, section D entry), capstone-decisions CAP-048/049 + superseded lines, prd-reconciliation addendum, other plan banners | 2–6 | todo |
| 8 | `sync-example-pages.sh` (skip 17-capstone), run all acceptance checks | 2–7 | todo |
| 9 | Live verification (below) | 8 | todo |
| 10 | `:latest` pin sweep (12-keda-kafka consumer, `services/*/Containerfile`, scaffold template, §1) | — | todo |

## Acceptance criteria

1. `scripts/editorial-audit.sh --strict` exits 0.
2. `git grep -n -i -E 'port-forward|minikube tunnel|minikube service|kubectl proxy|istioctl dashboard|ssh -L' -- . ':(exclude)presentation' ':(exclude)_plans'` → only exempt lines.
3. `git grep -n -i -E -- '--driver=podman|driver podman|--rootless|rootless true|MINIKUBE_ROOTLESS|podman (build|run|push|port|volume|tag|info)' -- . ':(exclude)presentation' ':(exclude)_plans'` → only exempt lines.
4. `git grep -n -i -E 'macos|windows|wsl|ubuntu|debian|homebrew|brew install|colima|rancher desktop|apple silicon|\blima\b' -- . ':(exclude)presentation' ':(exclude)_plans' ':(exclude)*.lock'` → only exempt lines plus `runs-on: ubuntu-latest`.
5. `git grep -n 'localhost:5000' -- examples/17-capstone` and `git grep -nE 'PROFILE(_NAME)?="?capstone"?' -- examples` → 0.
6. `check-port-map.sh`, `check-cross-references.sh`, `check-liquid-collisions.sh` exit 0; `bash -n` on every `*.sh`.
7. `helm lint` on the 09 chart and every capstone subchart; `helm template` shows the table's nodePorts.
8. `sync-example-pages.sh && git status --porcelain _example_pages` → empty.
9. `git diff --stat c1baef6 -- '*.lock' presentation/` → empty.
10. `git ls-files | grep -cE '__pycache__|examples/17-capstone/(examples|_plans)/|^17-capstone.md'` → 0.
11. `git grep -nE 'admin@open-metadata.org / admin|admin / capstone'` → 0.
12. No `:latest`, `releases/latest`, `stable.txt` or `@latest` outside exempt lines.

## Live verification (one cluster at a time)

Before: user runs `sudo systemctl start docker`; `docker context use default`;
checksum `~/.minikube/profiles/{capstone,datamesh,helm4dev}/config.json`;
`minikube config view` empty; `audit-fedora-prereqs.sh`.

Forbidden: `minikube delete --all`, any delete/start of `capstone`,
`datamesh`, `helm4dev`, `minikube config set`, `docker system/volume prune`.

| # | Run | Profile | Check |
|---|---|---|---|
| 1 | `examples/03-driver-check/demo.sh` | driver-check (self-deletes) | docker driver, containerd, 127.0.0.1:18079 |
| 2 | core start (CORE_PORTS) | minikube | `docker port minikube` lists 18080/18081/18090 |
| 3 | §5 addons + `dashboard-host` | | `curl 127.0.0.1:18090/`, `kubectl top nodes` |
| 4 | 06, 07, 08, 09 demo.sh | | ✓ SUCCESS; 30080 free afterwards |
| 5 | setup-strimzi, setup-keda, 12-keda-kafka, 12-keda-http | | 0→N→0 |
| 6 | `minikube stop -p minikube` | | |
| 7 | 11-istio demo + addons + host-access | istio | 8080 productpage; 20001, 3000, 9090, 16686 |
| 8 | 17-capstone `bootstrap-capstone.sh` | mof-capstone | `cluster-status.sh` green |
| 9 | all smoke-*, demo-canary, demo-add-data-product, walkthrough | | all PASS; `pgrep -f port-forward` empty |
| 10 | stop + `cluster-up.sh` | | images survive stop/start |
| 11 | `teardown.sh` (stop) | | other profiles' checksums unchanged |

## Risks

- dockerd may set iptables FORWARD to DROP and affect libvirt VMs on the same
  host — verify, document in FAQ.
- Companion selectors may differ from upstream labels — verify live.
- kic driver likely refuses CPU/memory changes on an existing profile (§4) —
  verify.
- SELinux under docker-ce (`docker info`) — verify §1/§6 prose.
- Capstone node `PidsLimit` under docker — verify with `docker inspect`.
- `:v1` + `pullPolicy: Never`: pods keep old image until restart;
  `build-image.sh` restarts.
- Canary: NodePort to order-service balances v1/v2.
- First bootstrap loads ~7 images (~0.5 GB each).
- README's "107 verified" claim becomes partly historical until the live run.
