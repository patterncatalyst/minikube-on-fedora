# Daemon Service

Runnable example for the [Daemon Service chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/12-daemon-service/).

`node-collector`: a `DaemonSet` running one Pod per node, reading that
node's own `/var/log` through a read-only `hostPath` mount — node-local
infrastructure beside whatever shipping services happen to be scheduled
there.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
kubectl --context mof-patterns apply -f daemon-service/00-daemonset.yaml
kubectl --context mof-patterns get daemonset node-collector -n patterns
```

`DESIRED`, `CURRENT`, and `READY` all equal the node count — one Pod per
node, no `replicas` field to set because a DaemonSet doesn't take one.

### One Pod per node

```bash
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=node-collector -o wide
```

Every schedulable node has exactly one `node-collector` Pod, each logging
its own node's summary:

```bash
POD=$(kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=node-collector -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns logs -n patterns "$POD" --tail=5
```

### Add a node, lose a node

On a single-node `mof-patterns` profile there's only one Pod to see;
`automated-placement`'s second-node setup makes the "exactly one per node"
guarantee visible directly:

```bash
minikube node add -p mof-patterns
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=node-collector -o wide -w
```

A second `node-collector` Pod appears on the new node with no manifest
change at all — the DaemonSet controller reconciles "one Pod per node"
continuously, the same way a Deployment reconciles "N Pods total."

```bash
minikube node delete mof-patterns-m02 -p mof-patterns
```

The Pod that was running there is simply gone; nothing reschedules it
elsewhere, because "elsewhere" already has its own Pod.

## Cleanup

```bash
kubectl --context mof-patterns delete -f daemon-service/00-daemonset.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
