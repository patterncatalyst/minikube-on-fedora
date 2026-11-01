---
title: "Daemon Service"
order: 12
part: "Behavioral"
description: "Run exactly one infrastructure Pod per node with a DaemonSet, and see how its update strategy and tolerations differ from a Deployment's."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain why a `DaemonSet` has no `replicas` field and what guarantee it provides instead
- Mount a node's own filesystem into a Pod with `hostPath` and explain the trade-off against a PersistentVolumeClaim
- Compare a DaemonSet's `RollingUpdate` and `OnDelete` update strategies
- Reason about what happens to a DaemonSet's Pods when a node joins or leaves the cluster

## Why this matters

Every workload this appendix has deployed so far answers the question "how many Pods" with a number: a Deployment's `replicas`, a Job's `completions`. DaemonService answers a different question entirely: not how many, but *where*. It places exactly one Pod per node, automatically, regardless of how many nodes exist or how often that number changes. That shape fits a narrow but common category of workload: infrastructure that has to see what's happening on a specific node rather than what's happening in the cluster as a whole, like a log collector, a metrics exporter, or a node-level security agent.

A Deployment could, in principle, be scaled to match the node count by hand, but that number changes every time a node joins or leaves, and a Deployment's scheduler has no concept of "one per node" as a placement rule (`podAntiAffinity` with `topologyKey: kubernetes.io/hostname`, from the Automated Placement chapter, gets close, but still requires manually tracking the node count as the `replicas` value). A DaemonSet encodes "one per node" as the controller's own reconciliation target instead of a number a human has to keep current, which is why it has no `replicas` field at all: there's nothing to set, because the answer is always "however many schedulable nodes currently qualify."

## No replicas, just a template

The example's `node-collector` DaemonSet shows the shape directly:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-collector
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: node-collector
  template:
    spec:
      containers:
        - name: node-collector
          image: registry.access.redhat.com/ubi10/ubi-minimal:10.2-1792742351
```

`kubectl get daemonset node-collector -n patterns` reports `DESIRED`, `CURRENT`, and `READY` columns that all track the schedulable node count automatically. Add a node to the cluster and a new `node-collector` Pod appears on it without touching this manifest at all; remove a node and its Pod goes with it, because there's no "elsewhere" for a DaemonSet Pod to reschedule to. The entire point is that each Pod belongs to exactly the node it's already on. `automated-placement`'s `minikube node add -p mof-patterns` makes this concrete: the moment the second node reports `Ready`, a second `node-collector` Pod appears there within one reconciliation pass, with zero manifest changes and zero `kubectl scale` commands, because there was never a count to scale in the first place.

## hostPath: reading the node, not a volume

`node-collector` mounts the node's own `/var/log` directory read-only, which is what lets it read every container's logs on that node regardless of which namespace or Deployment those containers belong to:

```yaml
volumeMounts:
  - name: varlog
    mountPath: /host-var-log
    readOnly: true
volumes:
  - name: varlog
    hostPath:
      path: /var/log
      type: Directory
```

A `hostPath` volume is fundamentally different from every PersistentVolumeClaim this appendix has used so far. A PVC is an abstraction over storage the cluster provisions and tracks independently of any one node; a `hostPath` volume is a direct bind-mount of a path that already exists on whichever node the Pod lands on, with no portability and no cluster-level tracking at all. That's a liability for an ordinary application (a Pod rescheduled to a different node would see an empty or different directory at the same path) and exactly the right tool for a DaemonSet, whose entire job is to see *this node's* state specifically, not some cluster-wide abstraction of it. `type: Directory` tells the kubelet to fail Pod creation if the path doesn't already exist on the node, instead of creating an empty one in its place: an empty `hostPath` directory would leave a collector reading nothing while believing it has real log data to work with.

![Two nodes, each running its own shipping service Pods beside a node-collector DaemonSet Pod reading that node's hostPath logs]({{ "/assets/diagrams/appendix-12-daemon-service.svg" | relative_url }})
*A DaemonSet places one Pod per node automatically; hostPath lets each one read only the node it is running on.*

## Tolerating a tainted control-plane node

By default, a control-plane node carries a `NoSchedule` taint (`node-role.kubernetes.io/control-plane`) that repels ordinary Pods the same way the Automated Placement chapter's custom `dedicated=fulfillment` taint did. A DaemonSet is not automatically exempt from that: without a matching toleration, `node-collector` would run on every worker node but skip the control plane entirely, leaving that node's own logs uncollected. The example's manifest tolerates it explicitly:

```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

`operator: Exists` with no `value` tolerates the taint regardless of what value it carries (control-plane taints don't set one), which is the right form here: the toleration cares only that the key is present, not what it's set to. This is exactly the pattern infrastructure daemons need and most application workloads don't: a log or metrics collector has a real, ongoing reason to run on control-plane nodes too, while `shipping-service` or `order-service` have no reason to run there at all. The distinction is a property of what the workload is, not a default either direction should assume.

## RollingUpdate versus OnDelete

A DaemonSet's `updateStrategy` governs how a changed Pod template (a new image tag, a changed command) rolls out across every node, and it uses the same two-option vocabulary in spirit as a Deployment's strategy field, applied to a fundamentally different unit of work:

```yaml
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
```

`RollingUpdate` (the default, and what the example sets explicitly) updates nodes one at a time (or `maxUnavailable` at a time): the controller deletes the old Pod on a node, waits for its replacement to become `Ready`, then moves to the next node. `OnDelete` is the alternative: changing the template does nothing by itself, and each node's Pod only picks up the new template when something (an operator, a maintenance script) deletes that specific Pod manually. `OnDelete` trades automation for control, useful when a DaemonSet's update needs to be sequenced against something else happening on that node (a planned maintenance window, a coordinated agent upgrade) rather than rolling out purely on the controller's own schedule. There's no `maxSurge` equivalent for a DaemonSet the way there is for a Deployment's `RollingUpdate`: a DaemonSet can never run more than one Pod per node by definition, so there's no "extra" capacity to surge into. The old Pod has to go before the new one can exist in its place.

## Restricting a DaemonSet to a subset of nodes

"One per node" is the default, but it's a default, not a hard rule: a DaemonSet's Pod template accepts the exact same `nodeSelector` and node affinity rules Automated Placement introduced for ordinary Pods, and they restrict a DaemonSet's reach the same way they would any other workload's:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        node-role.example.com/storage: "true"
```

Added to `node-collector`'s template, this would run the collector only on nodes carrying that label, skipping every other node in the cluster entirely: the right shape for infrastructure that applies to one specific subset of nodes (a GPU driver daemon with no business running on a CPU-only node, a specialized storage agent relevant only to nodes with local SSDs attached) rather than something every node needs regardless of its role. `kubectl get daemonset -n patterns node-collector -o wide` reports `NODE SELECTOR` directly, which is the fastest way to confirm whether a DaemonSet that looks like it's missing a node is missing it by design rather than by mistake.

## Resource requests on a DaemonSet still matter

It's tempting to under-resource a DaemonSet's containers on the assumption that "it's just a collector" means it's cheap, but a DaemonSet's resource requests compete for the exact same node capacity every other Pod on that node is drawing from, on every single node the DaemonSet runs on. There's no way to give it a smaller footprint "because it's infrastructure" without declaring that explicitly, the same `resources.requests`/`limits` mechanism Predictable Demands covered for any other container:

```yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    memory: 128Mi
```

An under-provisioned collector that gets OOMKilled on every node at the same time is a worse operational surprise than an ordinary Deployment's single Pod failing, precisely because it's happening everywhere at once rather than in one isolated place a Deployment's own replica count would otherwise contain.

## DaemonSet versus a static Pod

A less common but still exam-relevant alternative for "something on every node" is a static Pod: a Pod manifest placed directly in a kubelet's configured manifest directory (`/etc/kubernetes/manifests` by default) on a specific node, which that node's own kubelet manages directly without going through the API server's scheduler at all. A kubeadm-based cluster's own control-plane components (`kube-apiserver`, `etcd`) typically run exactly this way. A static Pod is tied to exactly the one node whose kubelet was configured with that manifest, placed there once and requiring direct file access to that node to change; a DaemonSet is a single cluster-wide object the API server reconciles against every qualifying node automatically, visible and manageable through `kubectl` like any other resource. For infrastructure that needs to run everywhere and be managed centrally, as `node-collector` does here, a DaemonSet is almost always the right choice; a static Pod's niche is specifically bootstrapping the pieces that have to run before there's a functioning API server to schedule anything through in the first place.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Design & Build (20%) [verify]
> **Competency:** Understand DaemonSets, including node placement, tolerations, and update strategy
> **Drill:** `kubectl get daemonset node-collector -n patterns -o jsonpath='{.status.desiredNumberScheduled}{" "}{.status.numberReady}'`

> **🤖 Explore with your agent**
>
> "Switch node-collector's updateStrategy to OnDelete, change its image tag, and show me that nothing happens on any node until I manually delete that node's Pod."

## Cleanup

```bash
kubectl --context mof-patterns delete -f daemon-service/00-daemonset.yaml
```

## Verification: examples/appendix-patterns/daemon-service/

The runnable example deploys `node-collector`, confirms one Pod per node, then adds and removes a second node with `minikube node add`/`node delete` to show the DaemonSet controller reconciling the Pod count automatically with no manifest change. Full walkthrough in `examples/appendix-patterns/daemon-service/README.md`.
