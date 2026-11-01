---
title: "Periodic Job"
order: 11
part: "Behavioral"
description: "Wrap a Job in a CronJob to run it on a schedule, and reason about concurrencyPolicy, startingDeadlineSeconds, and history limits instead of a crontab on a server somewhere."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain precisely what a `CronJob` manages: a template for Jobs, not a Job itself
- Set a `schedule` and reason about which time zone it runs in
- Choose a `concurrencyPolicy` and explain what happens when a firing overlaps a still-running previous one
- Trigger an on-demand run with `kubectl create job --from=cronjob` and distinguish it from a scheduled firing

## Why this matters

A recurring batch task used to mean a crontab entry on a server somewhere: a line in `/etc/cron.d`, a script with its own logging, its own retry logic, and its own assumption that the server running it stays up. None of that travels well into a cluster where any given node can disappear and workloads move around it. `CronJob` is the Kubernetes-native answer: the same scheduling syntax crontab popularized, but producing an ordinary `Job` object each time it fires, with every Job guarantee (`completions`, `parallelism`, retries, the whole previous chapter) intact.

The relationship between the two patterns in this family is direct. PeriodicJob isn't a different mechanism from BatchJob; it's BatchJob with a scheduler in front of it, generating a fresh `shipping-report` Job on a timer instead of a human running `kubectl create -f` by hand. Everything the previous chapter said about `completions`, `backoffLimit`, and `ttlSecondsAfterFinished` applies unchanged to the Job template a CronJob wraps; this chapter is about the layer of control specific to doing it repeatedly, unattended, without a human watching each firing.

## The schedule and the CronJob controller

The example's `03-cronjob.yaml` wraps the same `shipping-report` runner from the Batch Job chapter:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: shipping-report
spec:
  schedule: "*/5 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: shipping-report
              image: shipping-report:v1
              args: ["report"]
```

`schedule` uses the standard five-field crontab syntax (minute, hour, day-of-month, month, day-of-week), evaluated in the kube-controller-manager's configured time zone by default, UTC on most clusters unless a cluster administrator has changed it. A per-CronJob `timeZone` field (stable since Kubernetes 1.27) overrides that default for a single CronJob without touching the whole cluster's configuration, worth knowing about the moment a schedule needs to track a specific business time zone rather than whatever the control plane happens to run in.

The CronJob controller's own job is narrow: at each scheduled tick, create a new Job object from `jobTemplate`, and otherwise stay out of the way. It doesn't run anything itself, doesn't track application-level success beyond what the Job object already reports, and doesn't retry a missed firing beyond what `startingDeadlineSeconds` (below) allows. Everything about *how* the work runs belongs to the Job spec nested inside; everything about *when* belongs to the CronJob wrapping it. That separation is also why `kubectl get cronjob` and `kubectl get jobs` show two distinct layers of information: the CronJob shows the schedule and the last firing time, while each Job it created shows up separately, with its own Pods, its own `completions`, and its own independent lifecycle.

![A CronJob firing on schedule to create successive Jobs, each writing its own report, with history limited to the most recent few]({{ "/assets/diagrams/appendix-11-periodic-job.svg" | relative_url }})
*The CronJob controller creates one Job per scheduled tick; successfulJobsHistoryLimit bounds how many completed ones stick around afterward.*

## concurrencyPolicy: what happens on overlap

A report that normally finishes in seconds can, under load or against a slow dependency, still be running when the next scheduled tick arrives. `concurrencyPolicy` decides what the controller does about that:

```yaml
spec:
  concurrencyPolicy: Forbid
```

`Forbid` (what the example sets) skips the new firing entirely if the previous Job hasn't finished, logging the skip as a cluster event rather than queuing it. `Allow` (the default if the field is omitted) lets them run side by side, which is only safe if concurrent runs don't conflict. For `shipping-report`'s plain-Job path, where every run writes to the same shared PVC tagged by its own Pod name, concurrent firings wouldn't collide on a filename but would duplicate work against the same data, which is why `Forbid` is the deliberate choice here rather than an oversight. `Replace` is the third option: it cancels the still-running previous Job and starts the new one immediately, appropriate only when the newer run's data should supersede whatever a stale, still-running job was going to produce, not merely duplicate it.

`kubectl create job --from=cronjob/shipping-report <name>` bypasses `concurrencyPolicy` entirely: it talks to the Job API directly, not through the CronJob controller's scheduling loop, so an on-demand Job created this way can run alongside a scheduled one even under `Forbid`. That's a deliberate asymmetry, not a gap: `concurrencyPolicy` governs the controller's own scheduling decisions, and a manually created Job was never one of those decisions in the first place. Useful for testing a change against the production schedule without waiting for (or disturbing) the next real tick, but worth knowing before assuming `Forbid` is an absolute guarantee against overlap, which it only ever is for the scheduler's own firings.

## startingDeadlineSeconds and missed firings

```yaml
spec:
  startingDeadlineSeconds: 60
```

If the CronJob controller itself is down, or the cluster is otherwise unable to create new Jobs, a scheduled tick can be missed entirely. `startingDeadlineSeconds` bounds how late a missed firing is still allowed to start: within 60 seconds of its scheduled time here, the controller creates the Job as soon as it's able; past that window, the controller gives up on that specific tick and waits for the next one, recording the miss as a `MissedSchedule` event rather than trying to catch up (and definitely never trying to run every tick that was missed back-to-back, which would be the worse failure mode for anything time-sensitive). Leaving the field unset means there's no deadline at all: a controller that comes back online after an extended outage would attempt to start every missed firing it can still account for, which is rarely what a report-generation schedule actually wants.

## History limits and manual triggers

```yaml
spec:
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
```

Every firing's Job object sticks around after completion (subject to its own `ttlSecondsAfterFinished`, inherited unchanged from the Batch Job chapter) purely as a record: `kubectl get jobs -l app.kubernetes.io/name=shipping-report` after a few scheduled ticks shows the most recent few, not just the latest one, because `successfulJobsHistoryLimit` keeps the last three successful runs and garbage-collects anything older. `failedJobsHistoryLimit: 1` keeps even less of the failure history by default, on the (reasonable) assumption that a single recent failure is usually enough evidence to start debugging, and that keeping a long tail of old failures mostly just clutters `kubectl get jobs` output without adding diagnostic value beyond what logs and events already captured.

Triggering a run outside the schedule doesn't require inventing a one-off manifest:

```bash
kubectl create job --from=cronjob/shipping-report shipping-report-manual-1 -n patterns
```

This clones the CronJob's current `jobTemplate` into a brand-new, independently named Job, exactly as if the schedule had fired at that instant. It's useful for testing a change to the image or the schedule's Job spec without waiting for (or editing) the schedule itself, and it's the mechanism this appendix's own README walkthroughs reach for rather than waiting out a five-minute interval in a demo.

## suspend: pausing without deleting

A CronJob is often the first thing an operator wants to pause during an incident: a report that's querying a database already under load from whatever's being debugged is one more load source worth removing temporarily. Deleting the CronJob is the wrong tool for that, because it also deletes the schedule and the history of past runs; `suspend` is the right one:

```bash
kubectl patch cronjob shipping-report -n patterns -p '{"spec":{"suspend":true}}'
```

A suspended CronJob stops creating new Jobs at its scheduled ticks entirely, but the object itself, its `jobTemplate`, and every already-completed Job it created (subject to the history limits) all remain exactly as they were. Flipping `suspend` back to `false` resumes the schedule from whatever the next tick naturally is; it does not retroactively run whatever ticks were missed while suspended, following the same logic `startingDeadlineSeconds` applies to any other missed firing: a CronJob's job is to fire on schedule going forward, never to reconcile a backlog of ticks it didn't get to create.

## Why the Job name carries a timestamp

Every Job a CronJob creates gets an auto-generated name derived from the CronJob's own name plus an encoded representation of its scheduled time, which is worth understanding before it causes confusion reading `kubectl get jobs` output: `shipping-report-28545360` is not an arbitrary suffix, it's close to the scheduled Unix timestamp divided down to the minute, which is also what guarantees two different scheduled ticks never produce colliding Job names even if the controller is momentarily behind. A Job created manually with `kubectl create job --from=cronjob` sidesteps this scheme entirely, since it needs an explicit name supplied on the command line rather than one derived from a schedule. That's one more small but real distinction between a scheduled firing and a manually triggered one, beyond the `concurrencyPolicy` difference already covered above.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Design & Build (20%)
> **Competency:** Understand Jobs and CronJobs, including schedule, concurrencyPolicy, and manual Job creation from a CronJob template
> **Drill:** `kubectl create job --from=cronjob/shipping-report -n patterns shipping-report-drill-1`

> **🤖 Explore with your agent**
>
> "Change concurrencyPolicy from Forbid to Replace, trigger two manual Jobs from the CronJob template back to back, and show me what happens to the first one once the second one starts."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f periodic-job/03-cronjob.yaml
kubectl --context mof-patterns delete jobs -n patterns -l app.kubernetes.io/name=shipping-report
kubectl --context mof-patterns delete -n patterns -f periodic-job/02-seed-job.yaml
kubectl --context mof-patterns delete -n patterns -f periodic-job/01-pvc.yaml
kubectl --context mof-patterns delete -n patterns -f periodic-job/00-postgres.yaml
```

## Verification: examples/appendix-patterns/periodic-job/

The runnable example wraps the Batch Job chapter's own runner in a CronJob, triggers two on-demand runs with `kubectl create job --from=cronjob`, and confirms `concurrencyPolicy: Forbid` and the history limits behave as described against the live schedule. Full walkthrough in `examples/appendix-patterns/periodic-job/README.md`.
