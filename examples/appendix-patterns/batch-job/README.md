# Batch Job

Runnable example for the [Batch Job chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/10-batch-job/).

Worked against **shipping-report**, a net-new `uv`-managed CLI (not a
capstone service) that reads rows from its own `shipping.shipment_events`
demo table and writes a CSV to a PVC. Covers both a plain Job
(`completions`/`parallelism`) and an Indexed Job (`completionMode:
Indexed`, `JOB_COMPLETION_INDEX`).

## Build the image

There's no registry: build with Docker Engine and load straight into the
`mof-patterns` profile's containerd store, the same `imagePullPolicy: Never`
approach the capstone build script uses.

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
docker build -t shipping-report:v1 -f batch-job/Containerfile batch-job/
minikube -p mof-patterns image load shipping-report:v1
```

## Run it

```bash
kubectl --context mof-patterns apply -n patterns -f batch-job/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f batch-job/01-pvc.yaml
kubectl --context mof-patterns apply -n patterns -f batch-job/02-seed-job.yaml
kubectl --context mof-patterns wait --for=condition=Complete job/shipping-report-seed -n patterns --timeout=60s
kubectl --context mof-patterns logs -n patterns job/shipping-report-seed
```

### Plain Job: completions and parallelism

```bash
kubectl --context mof-patterns create -f batch-job/03-job-plain.yaml
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=shipping-report-plain -w
```

Three Pods start together (`parallelism: 3`) and the Job isn't `Complete`
until all three succeed (`completions: 3`). Each one writes its own file,
tagged with its own Pod name:

```bash
JOB=$(kubectl --context mof-patterns get jobs -n patterns -l app.kubernetes.io/name=shipping-report-plain -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns wait --for=condition=Complete "job/$JOB" -n patterns --timeout=60s
POD=$(kubectl --context mof-patterns get pods -n patterns -l job-name="$JOB" -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns exec -n patterns "$POD" -- ls -la /var/lib/shipping-reports
```

Three `report-<pod-name>.csv` files, each the full 300-row report.

### Indexed Job: cooperative partitioning

```bash
kubectl --context mof-patterns create -f batch-job/04-job-indexed.yaml
IJOB=$(kubectl --context mof-patterns get jobs -n patterns -l app.kubernetes.io/name=shipping-report-indexed -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns wait --for=condition=Complete "job/$IJOB" -n patterns --timeout=60s
IPOD=$(kubectl --context mof-patterns get pods -n patterns -l job-name="$IJOB" -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns exec -n patterns "$IPOD" -- ls -la /var/lib/shipping-reports
```

`report-0.csv`, `report-1.csv`, `report-2.csv`: three disjoint partitions of
the same 300 rows, each written by the Pod matching that
`JOB_COMPLETION_INDEX`, never both the plain run's redundant copies and the
indexed run's partitions at once unless you've run both.

## Cleanup

```bash
kubectl --context mof-patterns delete jobs -n patterns -l app.kubernetes.io/name=shipping-report-plain
kubectl --context mof-patterns delete jobs -n patterns -l app.kubernetes.io/name=shipping-report-indexed
kubectl --context mof-patterns delete -n patterns -f batch-job/02-seed-job.yaml
kubectl --context mof-patterns delete -n patterns -f batch-job/01-pvc.yaml
kubectl --context mof-patterns delete -n patterns -f batch-job/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
