---
title: "Process Containment"
order: 28
part: "Security"
description: "Pin a container to a non-root UID, drop every Linux capability it doesn't name, make its root filesystem read-only, and enforce the floor with a namespace's Pod Security Standard."
duration: "25 min"
---

## Learning objectives

By the end of this chapter you can:

- Set `runAsNonRoot`, `runAsUser`, and `seccompProfile` on a Pod, and explain what each one prevents
- Drop every Linux capability from a container and add back only the one it needs, instead of starting from the full default set
- Make a container's root filesystem read-only and mount a writable volume for the one path that still needs to be writable
- Label a namespace with a Pod Security Standard and explain the difference between it rejecting a Pod outright and merely warning about one

## Why this matters

A container is not a virtual machine: it's a Linux process, running on the same kernel as every other container on the node, isolated by namespaces and cgroups rather than by a hypervisor boundary. That isolation is real, but it's also narrower than it looks, and every security control this chapter covers exists to narrow it further, for the specific case where an attacker already has code execution inside a container and is looking for a way out of it or further into the node. A container running as root, holding its default set of Linux capabilities, with a writable root filesystem, gives that attacker meaningfully more to work with than the same container hardened against exactly those three things, and Process Containment is the pattern for making that hardening a property of the Pod spec rather than a hope about what the container image happens to do.

`review-service`'s own container image already runs as a non-root user: its `Containerfile` sets `USER 1001:0` in the final stage, which is good practice and also not something a Pod's own manifest can verify or rely on continuing to be true. An image rebuild, a base-image bump, or a `docker run --user 0` override at deploy time can all silently put a container back on UID 0 with nothing in the Deployment to catch it. Process Containment moves the non-root requirement (and the capability drop, and the read-only root filesystem) into the Pod spec itself, where the kubelet enforces it independently of whatever the image's own `Dockerfile` says, and where `kubectl describe pod` reports a clear, specific failure if a workload no longer satisfies it.

`review-service` is the worked example: the same REST data product used nowhere else in this appendix, hardened with a full `securityContext`, verified from inside the running container, and backstopped by a namespace labeled to reject anything that falls short of the baseline standard.

## Pod-level securityContext: identity and the syscall filter

A `securityContext` set at the Pod level applies to every container in the Pod, and three fields do most of the work:

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1001
    runAsGroup: 0
    seccompProfile:
      type: RuntimeDefault
```

`runAsNonRoot: true` doesn't choose a UID by itself; it's a check the kubelet runs against whatever UID the container would otherwise run as, and it refuses to start the container at all if that UID resolves to 0. Pairing it with an explicit `runAsUser: 1001` does two things at once: it makes the Pod's required UID visible in the manifest instead of implicit in the image, and it means `runAsNonRoot`'s check has something concrete to verify even against an image that was never written with a non-root default in mind. `runAsGroup: 0` matches the GID `review-service`'s own image already runs as (UBI's `USER 1001:0` convention keeps the primary group as root's GID 0 while the UID itself is unprivileged, which is deliberate: it lets an image grant group-read/write to specific paths without granting a privileged UID). `seccompProfile.type: RuntimeDefault` turns on the container runtime's default seccomp filter, a kernel feature that blocks a long list of rarely-needed and historically exploit-prone syscalls (kernel module loading, raw socket creation, and dozens more) regardless of what the container's own user or capabilities allow; `Unconfined`, the older implicit default on many clusters, runs with no syscall filtering at all.

## Dropping capabilities instead of granting them

Linux capabilities split root's traditionally all-or-nothing power into about forty separate privileges, and a container's default capability set (fixed by the container runtime, not Kubernetes) grants a double-digit subset of them whether the process inside ever uses a single one. `review-service`'s FastAPI process binds to port 8080, reads and writes to Postgres over a normal TCP socket, and does nothing else that needs elevated Linux privilege, which makes it a clean case for dropping every capability and adding nothing back:

```yaml
containers:
  - name: review-service
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      readOnlyRootFilesystem: true
```

`capabilities.drop: ["ALL"]` removes the entire default set; a workload that still needs one back (binding to a port below 1024 needs `NET_BIND_SERVICE`, for instance, something `review-service` doesn't need since it listens on 8080) would list it under a sibling `add` field rather than skip the drop. `allowPrivilegeEscalation: false` closes a separate door: without it, a `setuid` binary or a process with the `no_new_privs` flag unset can still gain more privilege than it started with through `exec`, independent of what capabilities were dropped. Setting both together is the actual meaning of "least privilege" for a container's Linux-level permissions: not merely trimmed, but trimmed with no path back to more.

## Read-only root filesystem, and the one path that still needs to write

`readOnlyRootFilesystem: true` mounts the container's own filesystem (everything from its image layers) read-only at the kernel level, which means a process that's been handed arbitrary code execution inside the container still can't write a second-stage payload to disk, modify a binary already on the image, or persist anything at all past the container's own lifetime. It also means any part of `review-service` that needs to write somewhere at all (a scratch directory, a cache, a socket file) needs an explicit writable mount, because the read-only root filesystem doesn't carve out exceptions on its own:

```yaml
volumeMounts:
  - name: tmp
    mountPath: /tmp
```

```yaml
volumes:
  - name: tmp
    emptyDir: {}
```

`review-service`'s container sets `PYTHONDONTWRITEBYTECODE=1`, so it never needs to write `.pyc` files back into its own image layers, which leaves `/tmp` as the one path worth mounting: Python's standard library and several of FastAPI's dependencies assume a writable temp directory exists even when the application code itself never calls `tempfile` directly. An `emptyDir` volume is the right shape for this: it's ephemeral by design (gone the moment the Pod is, which is exactly the lifetime a scratch directory should have), and mounting it at `/tmp` specifically, rather than leaving the whole root filesystem writable "to be safe," keeps the writable surface to the one path that needs it.

![A Pod's securityContext (non-root UID, dropped capabilities, read-only root) alongside a namespace enforcing the baseline Pod Security Standard, rejecting a privileged Pod]({{ "/assets/diagrams/appendix-28-process-containment.svg" | relative_url }})
*review-service runs hardened in the patterns namespace; a separate, disposable namespace demonstrates the baseline standard admitting a compliant Pod and rejecting a privileged one outright.*

## Verifying the hardening from inside the container

Each of these controls has a direct, checkable effect once the Pod is running. The UID:

```bash
kubectl --context mof-patterns exec -n patterns "$POD" -- id
# uid=1001 gid=0(root) groups=0(root)
```

The capability set, read from the kernel's own accounting for the container's PID 1:

```bash
kubectl --context mof-patterns exec -n patterns "$POD" -- sh -c 'cat /proc/1/status | grep CapEff'
# CapEff: 0000000000000000
```

An all-zero effective capability mask confirms the drop took effect at the kernel level, not just in the manifest. And the read-only root filesystem, by attempting the one thing it exists to prevent:

```bash
kubectl --context mof-patterns exec -n patterns "$POD" -- sh -c 'touch /opt/app-root/src/test-file'
# touch: /opt/app-root/src/test-file: Read-only file system
```

while the same command against `/tmp` succeeds, confirming the `emptyDir` mount is the one writable exception this hardening leaves in place.

## fsGroup: ownership for a mounted volume

`runAsUser` and `runAsGroup` decide which UID and GID the container's process runs as; they say nothing about which UID and GID a mounted volume's files are owned by, and a writable volume a non-root process can't write to is a common, confusing way for this chapter's hardening to half-work. `fsGroup`, set alongside `runAsUser` in the Pod's `securityContext`, tells the kubelet to recursively change group ownership of every volume it mounts (not the container's own root filesystem, which `readOnlyRootFilesystem` already governs separately) to the named GID, and to set the setgid bit on directories so new files created inside them inherit that group automatically:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  runAsGroup: 0
  fsGroup: 0
  seccompProfile:
    type: RuntimeDefault
```

`review-service`'s `emptyDir` at `/tmp` happens to work without an explicit `fsGroup` here, because `emptyDir` volumes default to being owned by the group the kubelet creates them under, usually permissive enough for a UID-1001 process to write into without any extra ownership change. A `PersistentVolumeClaim` backed by a storage class that provisions a volume owned by UID 0 and GID 0 is the case where this stops being true: without `fsGroup`, a non-root container can mount that volume successfully and still get `Permission denied` on every write, a failure that looks like a bug in the application rather than a missing one-line `securityContext` field. Setting `fsGroup` explicitly, even when the default behavior happens to work for a given volume type, is the more predictable habit, and it's one of the fields CKAD expects alongside `runAsUser` rather than as a separate, optional topic.

## Pod Security Standards: enforcing the floor at the namespace level

A `securityContext` is something each Deployment's author has to remember to write; a Pod Security Standard is a namespace-level backstop that doesn't depend on anyone remembering anything. Kubernetes defines three standards, from least to most restrictive: `privileged` (no restrictions at all), `baseline` (blocks the most clearly dangerous settings: running privileged, mounting the host's filesystem or network namespace, and similar host-breakout paths), and `restricted` (baseline plus everything this chapter's `securityContext` demonstrates: non-root, dropped capabilities, no privilege escalation). A namespace opts into one with labels, and this example uses a dedicated namespace, separate from `patterns`, so the standard it enforces never affects any other chapter's examples still running in the shared namespace:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: patterns-pss-demo
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

Three separate labels, not one, because Kubernetes lets `enforce`, `audit`, and `warn` each name a different standard. `enforce: baseline` is a hard gate: the API server's admission controller rejects a Pod outright if it violates baseline, with no Pod ever created. `warn: restricted` is a soft one: a Pod that satisfies baseline but falls short of restricted is still created, with `kubectl apply` printing a warning to the client, and `audit: restricted` records the same gap in the API server's audit log without surfacing anything to the client at all. This combination is a common middle ground: hard-block the clearly dangerous settings namespace-wide, while surfacing (without blocking) anything that falls short of the fully restricted bar, which is useful for a namespace migrating toward `restricted` gradually rather than all at once.

A Pod built to this chapter's own `securityContext` passes both standards cleanly and is admitted with no warning at all. A Pod that sets `privileged: true` is rejected outright by the `enforce: baseline` label, with the rejection message naming the specific field that violated it, before the Pod object is ever created:

```bash
kubectl --context mof-patterns apply -n patterns-pss-demo -f process-containment/04-privileged-pod-rejected.yaml
# Error from server (Forbidden): error when creating "...": pods "privileged-demo" is forbidden:
# violates PodSecurity "baseline:latest": privileged (container "demo" must not set
# securityContext.privileged=true)
```

That rejection happening at admission time, before the scheduler or the kubelet ever sees the Pod, is the entire value of enforcing a standard at the namespace level: it doesn't depend on a reviewer catching a dangerous manifest in a pull request, and it doesn't depend on every Deployment's author independently reaching for the same `securityContext` fields this chapter walks through by hand.

Older material (and some still-circulating exam prep) refers to `PodSecurityPolicy` as the mechanism for this, a cluster-scoped resource that performed a similar admission check. `PodSecurityPolicy` was deprecated in Kubernetes 1.21 and removed outright in 1.25; the namespace-label mechanism this chapter covers, Pod Security Admission, is what replaced it, and it's a much simpler design: three fixed standards to choose from, applied with plain namespace labels, rather than a cluster-scoped custom resource with its own RBAC-gated binding story. A cluster running any currently supported Kubernetes version uses Pod Security Admission exclusively; `PodSecurityPolicy` no longer exists to configure at all.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Environment, Configuration & Security (25%)
> **Competency:** Configure a Pod and container securityContext (non-root, dropped capabilities, read-only root filesystem) and label a namespace with a Pod Security Standard
> **Drill:** `kubectl label namespace patterns-pss-demo pod-security.kubernetes.io/enforce=restricted --overwrite` then reapply the compliant Pod and confirm it's still admitted

> **🤖 Explore with your agent**
>
> "Change review-service's container securityContext to add back NET_BIND_SERVICE instead of dropping all capabilities, apply it, and show me whether /proc/1/status still reports an all-zero CapEff or a nonzero one that includes it."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns-pss-demo -f process-containment/04-privileged-pod-rejected.yaml --ignore-not-found
kubectl --context mof-patterns delete -n patterns-pss-demo -f process-containment/03-compliant-pod.yaml
kubectl --context mof-patterns delete namespace patterns-pss-demo
kubectl --context mof-patterns delete -n patterns -f process-containment/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f process-containment/00-postgres.yaml
```

## Verification: examples/appendix-patterns/process-containment/

The runnable example deploys a hardened `review-service`, confirms its UID, effective capability mask, and read-only root filesystem from inside the running container, then creates a disposable namespace labeled with the baseline Pod Security Standard and shows it admitting a compliant Pod while rejecting a privileged one outright. Full walkthrough in `examples/appendix-patterns/process-containment/README.md`.
