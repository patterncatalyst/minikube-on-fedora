---
title: "Adapter"
order: 8
part: "Structural"
description: "Normalize an application's own output into a standard interface with a sidecar, worked by translating shipping-service's JSON health body into Prometheus exposition text."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain what makes Adapter different from a generic Sidecar: a specific obligation to translate one interface into another, standard one
- Translate an application's own health output into Prometheus exposition format without changing the application
- Reason about where an adapter's failure mode should land (on itself, not on the application it's adapting)
- Judge when format translation belongs in a sidecar instead of in the application's own instrumentation

## Why this matters

Monitoring tooling only works at scale when every target speaks the same protocol. A fleet with one service exposing metrics as `key=value` pairs in a log file, another as a JSON blob, and a third as whatever its framework happened to default to is a fleet where every integration is a one-off, and every new service needs its own custom scraper written and maintained. Prometheus's text exposition format solved that for metrics specifically by giving every service the same wire format to emit; the problem Adapter solves is what to do with a service that doesn't (and, for good reasons, shouldn't have to) emit that format itself.

Adapter is a narrower pattern than Sidecar: every adapter is a sidecar, but not every sidecar is an adapter. The defining trait is a format obligation. An adapter container's whole job is reading something the main container already produces, in whatever shape the main container happens to produce it, and re-emitting the same underlying fact in the shape some external consumer requires. It adds no new information and changes no behavior; it only changes the wire format, which is exactly why it belongs in its own container rather than inside the application.

## shipping-service's own output

`shipping-service` already reports its own health as JSON, because that's the natural format for a FastAPI service to emit and the format every other piece of this appendix's tooling (`curl`, `jq`, the services calling each other) already expects:

```bash
curl -s http://127.0.0.1:8080/healthz
{"status":"ready","service":"shipping-service"}
```

That's a perfectly good interface for a human, for `kubectl`'s readiness probe, or for another service checking dependency health over HTTP. It's not something a Prometheus-compatible scraper can ingest, because Prometheus doesn't parse arbitrary JSON looking for a status field; it expects its own line-based exposition format, with `# HELP`, `# TYPE`, and a metric name followed by a numeric value. Teaching `shipping-service` itself to also emit that format would mean adding a metrics library, a new endpoint, and an ongoing maintenance surface to every service that needs the same translation, for a concern (how this cluster's monitoring stack happens to ingest numbers) that has nothing to do with shipping logic.

## The adapter sidecar

The example's `metrics-adapter` container does the translation instead, as a second container in `shipping-service`'s own Pod:

```python
import http.server
import urllib.request

APP_URL = "http://127.0.0.1:8080/healthz"

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            with urllib.request.urlopen(APP_URL, timeout=2) as resp:
                up = 1 if resp.status == 200 else 0
        except Exception:
            up = 0
        body = (
            "# HELP shipping_service_up Whether shipping-service's /healthz reported ready.\n"
            "# TYPE shipping_service_up gauge\n"
            f"shipping_service_up {up}\n"
        ).encode()
        # ...write the response
```

Every request to the adapter's own `:9100/metrics` triggers a fresh poll of `shipping-service`'s `/healthz` over `localhost`, and the result becomes a single Prometheus gauge, `shipping_service_up`, either `1` or `0`. The adapter invents nothing: the underlying fact (is this instance ready) is exactly what `/healthz` already reports, and the only thing that changed between the two endpoints is the syntax it's expressed in.

```bash
curl -s http://127.0.0.1:9100/metrics
# HELP shipping_service_up Whether shipping-service's /healthz reported ready.
# TYPE shipping_service_up gauge
shipping_service_up 1
```

A `prometheus.io/scrape: "true"` annotation on the Pod template, alongside `prometheus.io/port: "9100"` and `prometheus.io/path: "/metrics"`, is how a Prometheus instance configured to discover targets this way would find the adapter's port without anyone hand-maintaining a static target list. The three annotations are a convention, not a Kubernetes API field, but a widely enough adopted one that most Prometheus Operator and kube-prometheus-stack setups honor it out of the box.

![shipping-service's JSON output translated into Prometheus exposition text by an adapter sidecar, with an external scraper reading only the translated port]({{ "/assets/diagrams/appendix-08-adapter.svg" | relative_url }})
*The adapter never changes what's true about shipping-service, only the syntax a scraper needs to read it in.*

## Named ports instead of magic numbers

The example's Service exposes both container ports by name rather than by number: `http` mapped to `8080` for the application, `metrics` mapped to `9100` for the adapter. Every probe in this appendix's examples already references `port: http` instead of a literal `8080` for the same reason named ports exist generally: the number can move (a base image upgrade that changes a framework's default port, say) without touching every manifest that references it, as long as the name stays put. The adapter's own port doesn't need to be probed by `kubectl` the way the application's does, but naming it the same way keeps the Service and the Pod spec readable together: `kubectl describe service shipping-service` shows `http` and `metrics` side by side, not two bare numbers a reader has to cross-reference against the Deployment to understand.

The response the adapter writes also sets a real `Content-Type` header, `text/plain; version=0.0.4`, which is Prometheus's own versioned media type for its exposition format, not an arbitrary string. A scraper that's strict about content negotiation uses that header to decide whether it's looking at the format it expects; omitting it (or getting the version wrong) is a common, overlooked way a homemade adapter like this one stops being scraped even though `curl` against it looks completely fine.

## Whose failure is it

Scale Postgres to zero and `shipping-service`'s own `/healthz` starts returning `503`, because `check_db()` can no longer reach it. The adapter's `/metrics` follows a moment later, reporting `shipping_service_up 0`, without the adapter itself crashing or needing any awareness of what a `503` from `/healthz` actually means beyond "not a 200." That's the adapter working correctly: its failure surface is strictly the translation, not the thing being translated. An adapter that returned `500` from its own `/metrics` endpoint whenever the app it's adapting was unhealthy would be conflating the two failure domains, turning a normal, expected application state (not ready yet, or not ready right now) into an adapter-level incident that pages someone for the wrong reason.

The reverse matters too: if the adapter container itself crashes (a bug in the translation logic, an unhandled exception), `shipping-service` keeps serving traffic and keeps answering its own `/healthz` exactly as before. A readiness probe pointed at the adapter's `/metrics` instead of the app's own `/healthz` would get this backwards, making the Pod's readiness depend on a container whose only job is observability tooling. The probes in this example, like every other chapter's, target the app container directly; the adapter is additive, never required for the Pod's own readiness.

## A narrow adapter versus a general-purpose exporter

Widely used tools like Prometheus's own `blackbox_exporter`, or a generic JSON-to-Prometheus exporter, solve the same translation problem `metrics-adapter` solves here, but as a general-purpose, configuration-driven tool meant to adapt arbitrary endpoints it knows nothing about in advance. `metrics-adapter` goes the other direction by design: it hardcodes exactly one upstream URL and exactly one output metric, because it exists to adapt this one service's output, not to be a reusable platform component. That's the right shape for a sidecar that ships inside a single application's own Pod. A general-purpose exporter run as a cluster-wide Deployment, scraping many targets through a shared configuration file, is a different (and for a fleet of similar services, often better) architecture, but it's a separate piece of infrastructure to operate rather than a sidecar riding along with the Pod it describes. Adding a second metric to `metrics-adapter` (latency, say, or a count of recent failures) means adding a few more lines to the same small script; growing it into something that adapts more than one application's output is usually the signal that a general-purpose exporter has become the better tool for the job.

## When this is worth its own container

Format translation belongs in a sidecar specifically when the source format is something the application already produces for its own reasons (structured logs, a health check, an admin endpoint) and changing that format inside the application would mean serving two audiences from one interface: humans and other services reading the natural format, plus a monitoring pipeline reading a second, unrelated one. The moment an application is instrumented with a proper metrics library from day one (which is the common case for anything built with observability in mind from the start), there's no adapter to write, because the application already speaks Prometheus natively. Adapter is worth the extra container specifically at the boundary with something that wasn't designed with a particular scraper's format in mind, which is most legacy services, most third-party components, and, as here, any service whose own output format is driven by what's convenient for its actual job rather than by a monitoring stack's requirements.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Observability and Maintenance (15%)
> **Competency:** Understand multi-container Pod design applied to observability, including a sidecar that exposes metrics in a standard format
> **Drill:** `kubectl exec -n patterns deploy/shipping-service -c metrics-adapter -- python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:9100/metrics').read().decode())"`

> **🤖 Explore with your agent**
>
> "Extend metrics-adapter to also report a second gauge, shipping_service_probe_latency_seconds, measuring how long its own call to /healthz took, and show me the new line in curl http://127.0.0.1:9100/metrics output."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f adapter/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f adapter/00-postgres.yaml
```

## Verification: examples/appendix-patterns/adapter/

The runnable example deploys `shipping-service` with `metrics-adapter` as a second container, compares `/healthz`'s JSON against `/metrics`'s Prometheus text for the same underlying readiness fact, then scales Postgres to zero to confirm the translated metric follows the app's real state down without the adapter itself failing. Full walkthrough in `examples/appendix-patterns/adapter/README.md`.
