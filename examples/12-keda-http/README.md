# 12-keda-http

Demonstrates KEDA's **HTTP add-on** (BETA) — scale-from-zero
on HTTP request traffic. Same workload as §6 (nginx-custom:v1),
now autoscaled based on in-flight request concurrency.

## Pre-requisites

```bash
./scripts/setup-keda.sh    # installs both KEDA core + HTTP add-on
```

The HTTP add-on installs alongside KEDA core in the `keda`
namespace — `setup-keda.sh` does both. No Strimzi needed for
this demo (Kafka demo is independent — see
`examples/12-keda-kafka/`).

## What this tests

Six §12 HTTP claims:

1. KEDA HTTP add-on installs cleanly via helm at the pinned
   version (0.12.2) on the existing `minikube` profile
2. An `HTTPScaledObject` CR + a Deployment with `replicas: 0`
   results in **zero replicas at idle**
3. The HTTP add-on **interceptor buffers the first request**
   during cold-start instead of returning 5xx — the client
   waits a few seconds but ultimately gets a 200
4. Sustained HTTP load via `hey -n 500 -c 50` causes KEDA to
   scale the nginx Deployment up (typically to 5 replicas,
   capped by `replicas.max: 5`)
5. The load test completes successfully (no failed requests)
6. After `scaledownPeriod` (30s) of zero traffic, KEDA scales
   back to zero replicas

## Running

```bash
./demo.sh
```

Expected timing:

- **First run** (if nginx-custom:v1 needs to build): ~2-3 min
- **Subsequent runs**: ~90-150 seconds

## What you'll see

```
✓ KEDA + HTTP add-on present in 'keda' namespace
✓ nginx-custom:v1 available
✓ manifests applied
✓ nginx at 0 replicas                                ← scale-to-zero
✓ interceptor reachable
✓ cold-start succeeded (HTML response received after Ns)
✓ nginx scaled up — peak replicas: N                 ← scale up
✓ nginx back at 0 replicas                           ← scale down
✓ SUCCESS
```

The cold-start time is the interesting metric. The HTTP add-on
interceptor receives the first request, signals KEDA, waits for
the Pod to be Ready, then forwards the request. Typical
cold-start: **3-8 seconds** on this minikube setup (image cached,
Pod startup dominated by readinessProbe `initialDelaySeconds`).

## When this fails

1. **All hey requests return 404 (most common gotcha)** — caused
   by using `-H 'Host: nginx.local'` instead of `-host nginx.local`.
   hey is written in Go; Go's `net/http` silently strips Host
   headers set via the headers map (issue
   [golang/go#7682](https://github.com/golang/go/issues/7682),
   open since 2014). The dedicated `-host` flag works because hey
   sets Go's special `Request.Host` field directly. **Always use
   `-host` with hey when targeting virtual-host-based proxies.**
   curl handles `-H 'Host:'` correctly because curl treats Host as
   a special case
2. **`hey` not installed** — `go install
   github.com/rakyll/hey@latest` per §2
2. **HTTP add-on not installed** — symptom: pre-flight
   complains about `keda-add-ons-http-interceptor` not found.
   `./scripts/setup-keda.sh` installs both core + add-on
3. **Cold-start timeout** — if the interceptor's first request
   takes >60s, something's wrong with the Pod startup. Check
   `kubectl describe pod -l app=nginx-http` for events
4. **Scale-up doesn't happen** — the HTTPScaledObject CRD has
   a status block; `kubectl describe httpscaledobject` shows
   conditions. The demo dumps this on failure
5. **`Host: nginx.local` header missing** — the interceptor
   routes based on the Host header. The demo always sets it;
   if you're testing manually, `curl -H 'Host: nginx.local'
   http://127.0.0.1:18080/` is the recipe

## Cleanup

Cleanup trap removes the Deployment, Service, and
HTTPScaledObject. KEDA stays installed (re-install is slow).

For deeper cleanup, use `cleanup.sh`:

```bash
# Remove the nginx workload + HTTPScaledObject (keeps KEDA
# installed for next time)
./cleanup.sh

# Also remove KEDA + HTTP add-on
./cleanup.sh --remove-operators
```

Note: `--remove-operators` removes BOTH KEDA core and the HTTP
add-on, which also affects the §12 Kafka demo (since it depends
on KEDA too). To remove only the HTTP add-on while keeping KEDA
core for the Kafka demo:

```bash
helm uninstall keda-add-ons-http -n keda
```

## Going further on your own

- **Try `scalingMetric.rate`** instead of `concurrency`. Rate
  is requests-per-second over a window; concurrency is
  in-flight requests at a moment. Different shapes for
  different workloads
- **Bump `replicas.max`** and re-run `hey -c 200`. With more
  concurrent clients, you'll see more replicas spin up (until
  you hit your minikube resource limits)
- **Watch the interceptor logs** during a cold-start —
  `kubectl logs -n keda deployment/keda-add-ons-http-interceptor
  -f`. The interceptor logs its queue state and scaling
  decisions
- **Combine with the Kafka pattern** — production workloads
  often need both: HTTP request scaling for the front-end,
  Kafka lag scaling for the consumers. KEDA handles both
  models simultaneously on the same cluster
- **Production readiness**: the HTTP add-on is officially in
  BETA. For production HTTP autoscaling, look at knative,
  Kedify's commercial HTTP Scaler, or wait for the add-on's
  GA release. KEDA core is GA and production-grade
