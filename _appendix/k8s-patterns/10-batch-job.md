---
title: "Batch Job"
order: 10
part: "Behavioral"
description: "Run work to completion instead of forever with a Job's completions and parallelism, then partition a shared dataset deterministically with an Indexed Job."
duration: "25 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain how a `Job` differs from a `Deployment`: running to completion instead of running indefinitely
- Tune `completions` and `parallelism` to control how many Pods must succeed and how many run at once
- Use `completionMode: Indexed` and `JOB_COMPLETION_INDEX` to partition a dataset across cooperating Pods with no coordination service
- Read `kubectl get jobs` and a Job's Pod statuses to tell a retry in progress from an outright failure

## Why this matters

Every workload this appendix has covered so far runs forever by design: a Deployment's whole contract is "keep this many Pods running," and a Pod that exits is a Pod that failed. A batch report, a data migration, a one-off cleanup script, none of those processes are supposed to run forever; they're supposed to finish, and a controller built around "keep this running" has no vocabulary for "run this until it's done, then stop." That's what a `Job` is for: a controller whose success condition is a count of completed Pods, not a count of currently-running ones.

The distinction matters for more than semantics. A Deployment that crash-loops is a production incident; a Job's Pod that exits non-zero is an expected outcome the controller is built to retry, up to a bound you set. Reach for a Deployment when the workload failing to be running is the problem; reach for a Job when the workload failing to finish is the problem. BatchJob is the first of that shape in this appendix, worked against `shipping-report`, a net-new, tiny `uv`-managed CLI that reads rows from its own `shipping.shipment_events` demo table and writes a CSV report to a PersistentVolumeClaim.

## completions and parallelism

A plain, non-indexed Job declares two independent numbers. The example's `03-job-plain.yaml` sets both:

```yaml
spec:
  completions: 3
  parallelism: 3
  backoffLimit: 2
```

`completions` is how many Pods must exit `0` before the Job itself is `Complete`; `parallelism` is how many Pods may be running at once while getting there. The two aren't the same knob wearing two names: set `completions: 5` with `parallelism: 2` and the controller runs two Pods at a time, starting a third the moment one of the first two finishes, until five total have succeeded. That's a bounded worker pool working through a fixed amount of work, with the pool size and the total work tracked as two separate numbers. Set them equal, as the plain Job here does, and all three start together.

`backoffLimit` caps how many times the controller retries a failed Pod before giving up on the whole Job, with an exponential backoff between attempts (10s, 20s, 40s, capped at six minutes) so a transient failure doesn't hammer whatever it's failing against. A Job that exhausts `backoffLimit` reports `BackoffLimitExceeded` and stops retrying; nothing retries it again without a human (or a CronJob, the next chapter) creating a new one.

This plain Job's three Pods each run the exact same command, `report`, with `PARTITION_COUNT=1` so every Pod sees every row, and each one would collide on the same output filename if they didn't distinguish themselves somehow. The manifest tags each Pod's report with its own Pod name, read through the Downward API (full treatment in the Self Awareness chapter):

```yaml
env:
  - name: REPORT_TAG
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
```

Three Pods, three identical full reports, three different filenames: `completions`/`parallelism` on their own describe *how many* and *how concurrent*, not *how the work is divided*. For three independent, redundant runs of the same task, that's the whole story. For three Pods that are supposed to split one dataset into three disjoint pieces, it isn't enough, which is exactly the gap the next mechanism closes.

![A Job partitions shipment_events across three Pods by completion index, each writing its own CSV to a shared PVC]({{ "/assets/diagrams/appendix-10-batch-job.svg" | relative_url }})
*completions and parallelism control how many Pods run and how many succeed; completionMode: Indexed is what actually divides the data between them.*

## Indexed Jobs: cooperative partitioning

`completionMode: Indexed` changes what each Pod knows about itself. The example's `04-job-indexed.yaml`:

```yaml
spec:
  completionMode: Indexed
  completions: 3
  parallelism: 3
```

With `completionMode: Indexed` set, the kubelet injects a `JOB_COMPLETION_INDEX` environment variable into every Pod, a distinct integer from `0` to `completions - 1`, one per Pod, guaranteed unique for the life of the Job. `shipping-report`'s `report` command reads it directly (it's also the CLI's `--partition-index` default via `envvar="JOB_COMPLETION_INDEX"` in the Typer option), and partitions `shipment_events` by `id % partition_count`:

```python
cur.execute(
    """SELECT id, destination_zone, weight_kg, shipped_at
       FROM "shipping".shipment_events
       WHERE id %% %s = %s
       ORDER BY id""",
    (partition_count, partition_index),
)
```

Three Pods, three disjoint slices of the same table, three files (`report-0.csv`, `report-1.csv`, `report-2.csv`) that together cover every row exactly once. No Pod talks to another Pod to agree on who takes which slice; the index itself is the coordination mechanism, assigned by Kubernetes and guaranteed not to repeat within the Job. That's the entire value of an Indexed Job over a plain one for this kind of workload: partitioning a known-size dataset across a fixed number of workers needs no external queue, no leader election, and no locking, because the one piece of shared state that matters (which worker owns which slice) is a field Kubernetes already tracks for every Pod it creates.

The indexed Job's Pod template sets `restartPolicy: Never` rather than `OnFailure`, which matters for how a failure is handled. With `restartPolicy: OnFailure`, a failed container restarts in the same Pod, same index, same node; with `restartPolicy: Never`, a failed Pod is left in place (for inspection) and the Job controller creates an entirely new Pod carrying the same index to retry the work, still bounded by `backoffLimit`. Either policy preserves the one-index-per-Pod guarantee that makes the partitioning scheme correct; which one to pick comes down to whether you want the failed attempt's own logs and final state left behind for debugging (`Never`) or want the kubelet to handle the restart locally without the Job controller creating a fresh object each time (`OnFailure`).

## Why seed is its own Job

Both the plain Job and the indexed Job depend on `shipment_events` already having rows, so the example applies a third, much simpler Job first: `02-seed-job.yaml` runs `shipping-report seed`, `completions: 1`, no parallelism to speak of. `seed` is written to be idempotent: it checks the row count before inserting anything and is a no-op once the table is non-empty, so this Job stays safe to apply more than once, whether that's a retried Pod after a transient failure or a second, explicit re-run, without ever producing duplicate data. A one-completion Job for a one-time setup step and a multi-completion Job for the actual parallel work are two different shapes of the same primitive, not two different primitives, and splitting them keeps each one's `completions`/`parallelism` numbers meaning exactly one thing.

## ttlSecondsAfterFinished and cleanup

Left alone, a completed Job and its Pods stick around indefinitely, which is useful right up until a namespace accumulates hundreds of them from a recurring workload. `ttlSecondsAfterFinished: 300` on every Job in this example tells the TTL controller to delete the whole Job (and its Pods) 300 seconds after it reaches a terminal state, success or failure alike. This is distinct from `backoffLimit`, which governs retries *before* a terminal state; `ttlSecondsAfterFinished` only starts counting once the Job is already done, succeeded or not. A Job that needs its logs inspected after failure should set this generously (or not at all) specifically so there's time to run `kubectl logs` before the TTL controller removes the evidence; a Job that fires every few minutes from a CronJob (next chapter) wants it short, precisely so completed runs don't pile up.

## activeDeadlineSeconds: bounding total run time

`backoffLimit` bounds how many times a Job retries; it says nothing about how long the whole Job is allowed to take. A Pod that hangs instead of failing outright (stuck waiting on a connection that never times out, say) never trips `backoffLimit` at all, since it never exits non-zero in the first place. `activeDeadlineSeconds` closes that gap from the other direction:

```yaml
spec:
  activeDeadlineSeconds: 600
```

Once a Job has been active for this many seconds, measured from when the first Pod starts rather than from Job creation, the controller terminates every running Pod and marks the Job `Failed` with reason `DeadlineExceeded`, regardless of `backoffLimit` or how close to success any individual Pod might have been. It's a coarser, blunter instrument than `backoffLimit`: one governs retry count, the other governs wall-clock time, and a Job that needs both bounds at once (finish within ten minutes, and don't retry more than twice) sets both fields simultaneously, since neither one substitutes for the other. Neither example manifest in this chapter sets it, because `shipping-report`'s partitions are small enough that a hang is more likely to indicate an application bug than a workload that occasionally needs more time, but it's the right knob to reach for the moment a batch workload's duration becomes unpredictable enough that "it's still running" stops being reassuring on its own.

## imagePullPolicy and a retried Pod

One detail that trips up a first attempt at parallel Jobs on minikube specifically: every manifest in this example sets `imagePullPolicy: Never`, matching the `build-service.sh` workflow's `minikube image load` step rather than a registry pull. A Job's retried Pod (from `backoffLimit`, or from the Indexed Job's `restartPolicy: Never` creating a fresh Pod per retry) re-evaluates `imagePullPolicy` exactly the same way any new Pod does; if the image was only ever loaded into a different minikube profile, or loaded before a `--replace` recreated the profile, every retry fails identically with `ErrImageNeverPull`, which reads at first glance like an application bug rather than an image availability problem. Checking `minikube -p mof-patterns image ls | grep shipping-report` before chasing a Job failure into the application logs is the faster diagnostic step precisely because the symptom (a Job stuck retrying, never succeeding) looks identical regardless of which of the two causes is actually responsible.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Design & Build (20%)
> **Competency:** Understand Jobs and CronJobs, including `completions`, `parallelism`, and indexed completion mode
> **Drill:** `kubectl get job -n patterns -l app.kubernetes.io/name=shipping-report-indexed -o jsonpath='{.items[0].spec.completionMode}'`

> **🤖 Explore with your agent**
>
> "Change the indexed Job's completions and the shipping-report CLI's PARTITION_COUNT from 3 to 5, rerun it, and show me that the five output files still cover every row in shipment_events exactly once with no overlap."

## Cleanup

```bash
kubectl --context mof-patterns delete jobs -n patterns -l app.kubernetes.io/name=shipping-report-plain
kubectl --context mof-patterns delete jobs -n patterns -l app.kubernetes.io/name=shipping-report-indexed
kubectl --context mof-patterns delete -n patterns -f batch-job/02-seed-job.yaml
kubectl --context mof-patterns delete -n patterns -f batch-job/01-pvc.yaml
kubectl --context mof-patterns delete -n patterns -f batch-job/00-postgres.yaml
```

## Verification: examples/appendix-patterns/batch-job/

The runnable example builds the `shipping-report` image, seeds demo data, then runs both a plain Job (three redundant full reports, each tagged by Pod name) and an Indexed Job (three disjoint partitions, each tagged by completion index) against the same PVC, confirming the file sets differ exactly as the pattern predicts. Full walkthrough, including the exact `kubectl` sequence and cleanup, in `examples/appendix-patterns/batch-job/README.md`.
