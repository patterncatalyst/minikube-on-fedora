---
title: "§3 driver check"
order: 3
example_dir: examples/03-driver-check
permalink: /examples/03-driver-check/
layout: tutorial
---

**Source:** [`examples/03-driver-check/`](https://github.com/patterncatalyst/minikube-on-fedora/tree/main/examples/03-driver-check) &middot; [← Back to examples index]({{ "/docs/16-examples/" | relative_url }})

The first runnable example in this tutorial. A smoke test that
exercises the §3 happy path end-to-end: start a minikube cluster
with the docker driver and containerd runtime on Docker Engine, verify it's healthy, list nodes and
system pods, tear down cleanly.

This isn't a workload-deployment example (those start in §6).
The goal here is narrower: **prove that the install from §2 and
the start sequence from §3 work together on this machine.**

## What it tests

Six claims from §1, §2, and §3:

1. `minikube` is installed and on `PATH`
2. `kubectl` is installed and on `PATH`
3. `minikube start --driver=docker --container-runtime=containerd`
   succeeds on Docker Engine without requiring KVM, qemu, or any
   virtualization layer
4. The profile reports driver `docker` and runtime `containerd`,
   the node reports `containerd://`, and `docker port driver-check
   30079/tcp` shows `127.0.0.1:18079` (the NodePort is published at
   profile creation with `--ports=127.0.0.1:18079:30079`)
5. `minikube status` reports all components `Running`
6. `kubectl` can talk to the new cluster and list nodes and
   system pods

On success, the corresponding reconciliation rows in Section B
(docker-driver-works-without-KVM, kubectl-1.36.x-against-1.36.x)
and Section C (this example) flip to `verified (Fedora 44)`.

## Running

```bash
./demo.sh
```

Expected duration:

- **First run:** 60–90 seconds (pulls the kicbase image once)
- **Subsequent runs:** 30–45 seconds (kicbase is cached)

## What you should see

A series of `==> step` lines for each phase, with progress
output from `minikube` and `kubectl` interleaved. The script
finishes with `✓ SUCCESS` if everything passed, or `✗ FAILED`
plus the failing step's name if anything went wrong.

The cluster runs under a dedicated profile named `driver-check`,
so it doesn't disturb any minikube cluster you have running
under the default profile.

## Cleanup

`demo.sh` installs a `trap cleanup EXIT` that deletes the
`driver-check` profile on script exit — success **or** failure.
If something pathological happens (Ctrl-C at the wrong moment,
script killed mid-cleanup), do the cleanup by hand:

```bash
minikube delete -p driver-check
```

Then `minikube profile list` should no longer show
`driver-check`.

## Re-running

The script is idempotent — re-running it from any state (fresh,
profile already exists, profile is half-dead) does the right
thing. It deletes any existing `driver-check` profile up front,
then starts fresh.

## When this fails

The most likely failure modes, in order:

1. **`minikube: command not found`** — §2 install of minikube
   didn't take. Fix: rerun `sudo dnf install -y
   https://github.com/kubernetes/minikube/releases/download/v1.39.0/minikube-1.39.0-0.x86_64.rpm`
2. **`require_docker_engine` fails** — the docker context is not
   `default` or the daemon is stopped. Follow the fix line the
   script prints (`docker context use default`,
   `sudo systemctl enable --now docker`)
3. **Docker can't pull the kicbase image** — usually a transient
   network issue. Rerun. Persistent failures point to
   `registry.k8s.io` reachability problems
4. **`minikube start` times out around "Verifying Kubernetes
   components"** — typically resource starvation on the host.
   Confirm `free -h` shows enough headroom; the demo asks for
   4 CPU / 8 GB which is well below the §1 floor
5. **`kubectl get nodes` errors with "connection refused"** —
   kubectl's context isn't pointing at the new profile. The
   script uses explicit `--context driver-check` to avoid this,
   so if it surfaces, paste the error in the iteration thread

For any of these, copy the script's failing output and share it
back so the iteration can produce a fix-up tarball if the prose
or script need an adjustment.
