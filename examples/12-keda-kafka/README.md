# 12-keda-kafka

Demonstrates KEDA's canonical pattern: a Kafka consumer that
scales **from zero based on consumer lag**, then back to zero
when the topic drains.

## Pre-requisites

```bash
# One-time setup (idempotent)
./scripts/setup-keda.sh         # KEDA core + HTTP add-on
./scripts/setup-strimzi.sh      # Strimzi Cluster Operator
```

Both scripts go to `~/.local/share/...` and `helm` repositories;
your `minikube` profile from §3 needs to be running. Confirm:

```bash
kubectl config use-context minikube
kubectl get nodes        # → minikube  Ready  control-plane
```

## What this tests

Eight §12 Kafka claims:

1. `setup-strimzi.sh` installs Strimzi Cluster Operator
   cleanly on Fedora 44
2. A single-node KRaft `Kafka` CR with Kafka **3.9.0** reaches
   `condition=Ready` within 5 minutes
3. A `KafkaTopic` CR with 3 partitions reaches `condition=Ready`
4. The Python `order-processor` consumer image builds cleanly
   from `consumer/Containerfile` (multi-stage UBI)
5. A `Deployment` with `replicas: 0` plus a KEDA `ScaledObject`
   results in **zero replicas at idle** (proves scale-to-zero)
6. Producing N messages to the topic causes KEDA to scale the
   consumer up to ≥1 replica within 120 seconds
7. The consumer drains the topic (messages get processed)
8. After `cooldownPeriod` (30s) of zero lag, KEDA scales back
   to zero replicas — confirming the full 0→N→0 lifecycle

## Running

```bash
./demo.sh
```

Expected timing:

- **First run** (Kafka cluster bring-up + image build):
  ~5-8 minutes
- **Subsequent runs** (everything cached): ~2-4 minutes

The Kafka cluster bring-up is the slow part. KEDA's
ScaledObject reconciliation is fast (~5s polling).

## What to look for

Key log lines:

```
✓ Kafka cluster Ready                         ← Strimzi happy
✓ Topic 'orders' Ready                        ← Topic Operator happy
✓ order-processor:v1 available                ← Image cached
✓ consumer at 0 replicas (KEDA is in scale-to-zero state)
✓ 200 messages produced
[Ns] replicas climbed to N                    ← KEDA scaled up
✓ consumer scaled up — peak replicas: N
✓ consumer back at 0 replicas                 ← Scale-down complete
✓ SUCCESS
```

The peak replica count is bounded by:
- `maxReplicaCount: 3` in the ScaledObject
- The number of partitions in the topic (also 3)
- `(message_lag / lagThreshold)` — with 200 messages
  and `lagThreshold: 5`, KEDA would ask for 40 replicas,
  but is capped at 3

So expected peak: **3 replicas**.

## When this fails

Most likely failure modes, in rough order of frequency:

1. **Strimzi Cluster Operator stuck reconciling** — the Kafka
   CR never reaches Ready. Demo dumps the operator logs +
   Kafka status + events on failure. Common fixes:
   - `helm uninstall strimzi -n kafka` + `kubectl delete
     namespace kafka` + `./scripts/setup-strimzi.sh` (fresh
     start)
   - Check the operator logs for `KafkaUpgradeException` —
     this means you're using an unsupported Kafka version
     (do NOT use 3.9.2 with Strimzi 0.51)
2. **Image pull failures for Kafka itself** — Strimzi pulls
   `quay.io/strimzi/kafka:0.51.0-kafka-3.9.0` (~600 MB). On
   slow connections this can take 5+ minutes. Check
   `kubectl describe pod -n kafka <kafka-pod>` for image-pull
   progress
3. **KEDA doesn't scale up** — check `kubectl describe
   scaledobject order-processor-scaler` and KEDA operator
   logs. Common issue: KEDA can't reach Kafka at the configured
   bootstrap-servers address (typo or wrong DNS name)
4. **Consumer can't reach Kafka** — same root cause as #3,
   but from the consumer Pod's side. `kubectl logs
   deployment/order-processor` should show connection errors

If something else fails, paste the demo's diagnostic output —
it includes Strimzi logs, KEDA logs, ScaledObject status, and
recent events.

## Cleanup

The demo's cleanup trap removes the consumer Deployment + the
ScaledObject. The Kafka cluster + topic stay running for re-runs
(both are slow to recreate). To fully clean up:

```bash
kubectl delete kafka my-kafka -n kafka
kubectl delete kafkatopic --all -n kafka
helm uninstall strimzi -n kafka
kubectl delete namespace kafka

# If you also want to remove KEDA:
helm uninstall keda-add-ons-http -n keda
helm uninstall keda -n keda
kubectl delete namespace keda
```

## Going further on your own

- **Tune `lagThreshold`** in the ScaledObject. Lower values
  mean faster scale-up (more responsive) but more replicas.
  Higher values mean cheaper but slower scaling
- **Tune `cooldownPeriod`** for different shapes. Long
  cooldowns (5+ min) reduce flapping but keep workloads
  running longer
- **Try `offsetResetPolicy: latest`** instead of `earliest` —
  the consumer ignores backlog and only processes new messages
  (relevant when you want KEDA-based autoscaling but don't
  want a fresh consumer to chew through historical data)
- **Add multiple triggers** to the same ScaledObject — KEDA
  ORs them, scaling up if any single trigger fires. Useful
  for "scale up if EITHER Kafka lag OR CPU is high"
- **Replace Strimzi with Bitnami** — the KEDA ScaledObject
  manifest is Kafka-implementation-agnostic; it just needs a
  reachable bootstrap-servers address
