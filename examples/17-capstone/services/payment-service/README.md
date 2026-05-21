# payment-service

A §17 capstone data product. Owns the `payments` Postgres schema
(per-service ownership, CAP-003).

**r22 scope (skeleton):** the service starts, ensures its schema exists, and
serves health probes:

- `GET /health` — liveness (process up)
- `GET /healthz` — readiness (Postgres reachable)

Its domain surface is added in later iterations (REST/gRPC/GraphQL/Kafka as
appropriate to the service).

## Build + deploy

```bash
# from examples/17-capstone/
./scripts/build-image.sh services/payment-service payment-service v1
helm upgrade --install payment-service charts/capstone/charts/payment-service -n capstone
kubectl rollout status deployment/payment-service -n capstone --timeout=120s
```

Or run the health smoke test, which does all of the above and asserts the
probes: `./demos/smoke-service.sh payment`
