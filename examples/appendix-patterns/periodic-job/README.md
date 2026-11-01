# Periodic Job

Runnable example for the [Periodic Job chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/11-periodic-job/).

The same **shipping-report** runner from the Batch Job chapter, now wrapped
in a `CronJob` instead of created by hand.

## Build the image

Reuses the image built for the Batch Job chapter; build it if you haven't
already:

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
docker build -t shipping-report:v1 -f batch-job/Containerfile batch-job/
minikube -p mof-patterns image load shipping-report:v1
```

## Run it

```bash
kubectl --context mof-patterns apply -n patterns -f periodic-job/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f periodic-job/01-pvc.yaml
kubectl --context mof-patterns apply -n patterns -f periodic-job/02-seed-job.yaml
kubectl --context mof-patterns wait --for=condition=Complete job/shipping-report-seed -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f periodic-job/03-cronjob.yaml
```

### Watch the schedule

```bash
kubectl --context mof-patterns get cronjob shipping-report -n patterns -w
```

`LAST SCHEDULE` fills in at the next five-minute boundary. Rather than wait,
trigger an on-demand run with the exact same template the schedule would use:

```bash
kubectl --context mof-patterns create job --from=cronjob/shipping-report shipping-report-manual-1 -n patterns
kubectl --context mof-patterns wait --for=condition=Complete job/shipping-report-manual-1 -n patterns --timeout=60s
```

### Concurrency and history

```bash
kubectl --context mof-patterns create job --from=cronjob/shipping-report shipping-report-manual-2 -n patterns
kubectl --context mof-patterns get jobs -n patterns -l app.kubernetes.io/name=shipping-report
```

Jobs created directly with `kubectl create job --from=cronjob` ignore
`concurrencyPolicy: Forbid` (that field only governs the CronJob controller's
own scheduled firings), so both manual Jobs run; wait a few scheduled
firings and `successfulJobsHistoryLimit: 3` caps how many completed Jobs the
CronJob controller keeps before garbage-collecting the oldest.

Confirm each run wrote its own file:

```bash
POD=$(kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=shipping-report -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns exec -n patterns "$POD" -- ls -la /var/lib/shipping-reports
```

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f periodic-job/03-cronjob.yaml
kubectl --context mof-patterns delete jobs -n patterns -l app.kubernetes.io/name=shipping-report
kubectl --context mof-patterns delete -n patterns -f periodic-job/02-seed-job.yaml
kubectl --context mof-patterns delete -n patterns -f periodic-job/01-pvc.yaml
kubectl --context mof-patterns delete -n patterns -f periodic-job/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
