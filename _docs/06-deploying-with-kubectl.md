---
title: Deploying with kubectl
order: 6
description: Deploy a workload with kubectl — Pods, Deployments, Services, scaling, rolling updates — using a UBI nginx image.
duration: 25 minutes
---

This is the first section that actually deploys a workload. §1-§5
got you a cluster you can talk to; §6 puts something useful inside
it. The example is deliberately small — one UBI nginx Deployment
and a Service — so the moving parts each get attention rather than
getting lost in a more realistic application.

By the end you'll have written a Deployment manifest, applied it,
watched the Pods come up, exposed them through a Service, reached
the Service from your host, scaled the Deployment up and down, and
rolled out a new image version. Same vocabulary you'll use for
every real workload after this.

## The mental model: Pods, ReplicaSets, Deployments

Three Kubernetes objects work together to run your workload. Each
abstracts over the next.

A **Pod** is the smallest deployable unit — one or more containers
that share a network namespace and lifecycle. Pods are
near-disposable; if one dies, it stays dead unless something else
recreates it.

A **ReplicaSet** is the thing that recreates Pods. It holds a
target replica count and a Pod template; if there are fewer Pods
than the count, it creates more. You'll rarely write ReplicaSets
directly — they exist mostly as the implementation underneath
Deployments.

A **Deployment** wraps a ReplicaSet with lifecycle management.
Deployments handle rolling updates, rollbacks, history. **You
write Deployments and almost never write Pods or ReplicaSets
directly.** Deployments are the natural unit of "a running thing
in my cluster".

Visually:

```
Deployment
  └─ controls → ReplicaSet
                  └─ controls → Pod, Pod, Pod (replicas)
```

When you change the Deployment (new image, new env var), it
creates a *new* ReplicaSet with the new template, scales the new
one up, scales the old one down. The old ReplicaSet sticks around
at zero replicas so you can roll back to it.

## Writing a Deployment manifest

Here's the Deployment for our UBI nginx example
(`examples/06-deploy-nginx-kubectl/manifests/deployment.yaml`):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: registry.access.redhat.com/ubi9/nginx-124
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 2
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
```

Reading it top to bottom:

- **`apiVersion: apps/v1`** — Deployments live in the `apps` API
  group at version `v1`. (Pods are in `v1` core; the API group
  matters when you reference these objects via the API server)
- **`kind: Deployment`** — the resource type
- **`metadata.name: nginx`** — the object's name. Unique within
  its namespace
- **`metadata.labels`** — labels on the Deployment itself.
  Independent of pod labels (see below)
- **`spec.replicas: 2`** — target replica count
- **`spec.selector.matchLabels`** — which Pods this Deployment
  manages. **Must match `template.metadata.labels` exactly** or
  the Deployment refuses to apply
- **`spec.template`** — the Pod template. Everything from here on
  describes the Pods this Deployment creates
- **`template.metadata.labels.app: nginx`** — Pod labels. The
  selector above looks for these
- **`template.spec.containers[].image`** —
  `registry.access.redhat.com/ubi9/nginx-124`, Red Hat's UBI 9
  nginx 1.24 build. Runs as user 1001 (non-root) and listens on
  port 8080 (rootless-friendly)
- **`containerPort: 8080`** — declares the port the container
  listens on. Not a port mapping; just metadata for Kubernetes
- **`readinessProbe`** — when to consider the Pod ready for
  traffic. Failing readiness pulls the Pod out of Service
  endpoints but doesn't restart it
- **`livenessProbe`** — when to consider the Pod broken and
  restart it. Failing liveness triggers a container restart
- **`resources.requests`** — minimum cluster resources the
  scheduler guarantees. Used for scheduling decisions
- **`resources.limits`** — cap on resources the container can
  use. CPU is throttled at the limit; memory above the limit
  triggers OOM-kill

The labels deserve a closer look since they're how everything in
Kubernetes finds everything else.

### Labels and selectors

`app: nginx` appears in three places in the manifest:

1. `metadata.labels` on the Deployment (so other resources can
   find *this* Deployment)
2. `spec.selector.matchLabels` (which Pods this Deployment
   controls)
3. `spec.template.metadata.labels` (the label on each Pod the
   Deployment creates)

(2) and (3) must match. (1) is independent but conventional to
keep the same. The Service we'll create in a moment will also use
`app: nginx` in its selector to find these Pods.

## Applying the manifest

```bash
kubectl apply -f examples/06-deploy-nginx-kubectl/manifests/deployment.yaml
```

`apply` is idempotent — running it twice with the same file makes
no changes the second time. It's the standard way to ship
manifests in tutorials and CI.

You'll see:

```
deployment.apps/nginx created
```

The Deployment is created; Kubernetes now races to make reality
match the spec.

## Inspecting

```bash
kubectl get deployment nginx
```

```
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
nginx   2/2     2            2           30s
```

`2/2` means 2 ready out of 2 desired. `kubectl get pods`:

```bash
kubectl get pods -l app=nginx
```

You should see two Pods named `nginx-<replicaset-hash>-<pod-hash>`,
both `Running` and `1/1` (one container ready per Pod).

For deeper inspection:

```bash
kubectl describe deployment nginx     # events, conditions, history
kubectl describe pod <pod-name>       # the same for a specific Pod
kubectl logs <pod-name>               # container stdout/stderr
kubectl logs -l app=nginx --tail=20   # logs from all Pods with that label
```

To get a shell inside a Pod:

```bash
kubectl exec -it <pod-name> -- /bin/bash
```

(UBI nginx ships `/bin/bash`; some smaller base images only have
`/bin/sh`. `--` separates kubectl's flags from the command to
run in the container.)

## Exposing it with a Service

Pods are ephemeral — restarts mean new IPs. A **Service** gives
the Deployment a stable address inside the cluster. Here's
`examples/06-deploy-nginx-kubectl/manifests/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
```

The Service:

- Has its own name (`nginx`) and IP, both stable for the Service's
  lifetime
- Has a selector that matches all Pods with `app: nginx` —
  exactly the Pods our Deployment manages
- Receives traffic on `port: 80` and forwards to `targetPort: 8080`
  on the matching Pods
- Type `ClusterIP` — reachable from *inside* the cluster only.
  §7 covers `NodePort` and other external-access types

Apply:

```bash
kubectl apply -f examples/06-deploy-nginx-kubectl/manifests/service.yaml
```

```bash
kubectl get service nginx
```

```
NAME    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
nginx   ClusterIP   10.96.123.234   <none>        80/TCP    5s
```

The `<none>` for EXTERNAL-IP is expected for ClusterIP — there's
no external address by design.

## Reaching the Service from your host

Since the Service is ClusterIP, there's no host-routable IP for
it directly. The simplest way to reach it from your host is
`kubectl port-forward`:

```bash
kubectl port-forward service/nginx 18080:80
```

This opens a tunnel: traffic to `127.0.0.1:18080` on your host
goes through the kubectl process to the Service inside the
cluster, which load-balances to one of the nginx Pods. Open a
second terminal and:

```bash
curl http://127.0.0.1:18080/
```

You should see UBI nginx's default landing page — HTML with
"Test Page for the Nginx HTTP Server" near the top.

Ctrl-C the port-forward when done. **Use port-forward for ad-hoc
access; §7 covers NodePort for an always-on host-reachable
endpoint.**

## Scaling

The Deployment's replica count is just a number. Bump it:

```bash
kubectl scale deployment nginx --replicas=5
kubectl get pods -l app=nginx
```

You should see five Pods now. The Service automatically picks up
the new endpoints — `kubectl get endpoints nginx` would show five
IPs.

Scale back down:

```bash
kubectl scale deployment nginx --replicas=2
```

The two oldest Pods stay; the three new ones are terminated.

To make a replica count change permanent, edit the manifest's
`spec.replicas` and `kubectl apply` again — that way the next
person to deploy from your manifest gets the same count.

## Rolling updates

Change the image:

```bash
kubectl set image deployment/nginx nginx=registry.access.redhat.com/ubi9/nginx-122
```

(Pinning to 1.22 instead of 1.24 — different image, same shape.)

Watch the rollout:

```bash
kubectl rollout status deployment/nginx
```

You'll see lines like:

```
Waiting for deployment "nginx" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "nginx" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "nginx" rollout to finish: 1 old replicas are pending termination...
deployment "nginx" successfully rolled out
```

While it's rolling, `kubectl get pods -l app=nginx` shows a mix
of old (still pulling the new image) and new (already running).
The Deployment manages this by creating a new ReplicaSet,
scaling it up while scaling the old one down — slowly enough
that traffic is never dropped.

To see the rollout history:

```bash
kubectl rollout history deployment/nginx
```

```
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

To roll back:

```bash
kubectl rollout undo deployment/nginx
```

This restores the previous ReplicaSet's image and scales it back
up — the rollback is itself a rolling update.

## Cleanup

```bash
kubectl delete -f examples/06-deploy-nginx-kubectl/manifests/
```

This deletes the Deployment (which deletes its ReplicaSets, which
delete their Pods) and the Service. Idempotent.

To delete everything in a namespace by label without needing the
manifests:

```bash
kubectl delete all -l app=nginx
```

`kubectl delete all` doesn't actually delete *all* resource kinds
— it covers the workload-shaped ones (Deployment, Service, Pod,
ReplicaSet, StatefulSet, DaemonSet, Job, CronJob). ConfigMaps,
Secrets, PVCs, and others need explicit `delete <kind>`.

## Verification: examples/06-deploy-nginx-kubectl/

`examples/06-deploy-nginx-kubectl/demo.sh` runs the prose above
as one end-to-end test:

1. Pre-flight: ensures the cluster is up; clears any prior nginx
   Deployment/Service
2. Applies both manifests
3. Waits for the Deployment to be `Available`
4. Starts a `kubectl port-forward` in the background
5. Waits for the port to be listening, curls it, checks for the
   nginx welcome page in the response
6. Scales to 3 replicas; verifies all three become Ready
7. Cleans up the port-forward + manifests on exit (`trap`)

Run it:

```bash
cd examples/06-deploy-nginx-kubectl
./demo.sh
```

Expected duration: 60-120 seconds first run (pulls the nginx-124
image; ~150 MB); 20-30 seconds after.

The demo uses your **default minikube cluster** (not a separate
profile, unlike `examples/03-driver-check/`). It cleans up its
own resources but leaves the cluster running for the next demo.

[On to §7: Services and NodePort →]({{ "/docs/07-services-nodeport/" | relative_url }})
