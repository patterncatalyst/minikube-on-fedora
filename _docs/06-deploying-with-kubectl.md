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

## A small detour: building our own image

The Red Hat UBI ecosystem ships application images like
`registry.access.redhat.com/ubi9/nginx-124` — but those are
**s2i (source-to-image) builder images** designed for the OpenShift
workflow. Their default CMD is `/usr/libexec/s2i/run`, which expects
content baked in at build time via `s2i assemble`. In plain
Kubernetes (rather than OpenShift) they crashloop because nginx
starts with nothing to serve.

The right answer isn't to coax the s2i image into running directly.
It's to **build our own image** from a standard UBI base.

### Why multi-stage

The Containerfile in
`examples/06-deploy-nginx-kubectl/Containerfile` is a two-stage
build:

- **Builder stage:** `registry.access.redhat.com/ubi9/ubi` — the full
  UBI 9 image. In a real project this is where you'd run a static-site
  generator, compile assets, run package managers — anything that
  needs a full toolchain
- **Runtime stage:** `registry.access.redhat.com/ubi9/ubi-minimal` —
  a stripped-down UBI 9 with `microdnf` (the slim package manager).
  Just what nginx needs to run, nothing extra

The runtime image inherits nothing from the builder except what we
explicitly `COPY --from=builder`. Build-time tooling — compilers,
build dependencies, transient files — never reach the deployable
image.

For our static-content nginx example the builder stage is
intentionally minimal (it just stages the index.html). For a
production workload where the builder runs Hugo or Webpack or a
Maven build, the pattern shows its real value: a tiny, focused
runtime image and a build environment with whatever tools you need.

### Why ubi-minimal specifically

Three Red Hat UBI variants are commonly chosen as runtime bases:

| Image                 | When                                                                                      |
|-----------------------|-------------------------------------------------------------------------------------------|
| `ubi9/ubi`            | Full UBI 9 — pick when you need many packages or rich shell tooling at runtime           |
| `ubi9/ubi-minimal`    | UBI 9 with `microdnf` instead of `dnf`. Smaller; great for single-app runtime images     |
| `ubi9/ubi-micro`      | Strictly distroless — no package manager. Build packages in another stage, then COPY in  |

We use `ubi9/ubi-minimal` for the runtime: small enough to be a
real "minimal runtime", but with `microdnf` available so the
Containerfile is simple. All three are **freely redistributable**;
none require `subscription-manager` registration. (That's the
hallmark of UBI vs full RHEL container images — the latter need
registration to install packages.)

### The Containerfile

```dockerfile
# ── Stage 1: Builder ─────────────────────────────────────────────────────
FROM registry.access.redhat.com/ubi9/ubi AS builder

WORKDIR /build

# In a real project, you'd RUN a static-site generator here. For
# this tutorial the builder just stages the hand-written index.html
# so the COPY --from=builder in stage 2 has something to take.
COPY index.html .

# ── Stage 2: Runtime ─────────────────────────────────────────────────────
FROM registry.access.redhat.com/ubi9/ubi-minimal

# Install nginx, clean caches in the same layer
RUN microdnf install -y nginx && \
    microdnf clean all && \
    rm -rf /var/cache/dnf /var/cache/yum

# Replace the package's default nginx.conf with our minimal one (see
# next subsection)
COPY nginx.conf /etc/nginx/nginx.conf

# Copy the staged content from the builder stage
COPY --from=builder /build/index.html /usr/share/nginx/html/index.html

# Document root readable by any UID (already world-readable at 755;
# belt-and-suspenders)
RUN chmod -R a+rX /usr/share/nginx/html

USER 1001:0
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
```

A few notes on the rationale:

- **`COPY --from=builder` instead of `RUN`-to-manipulate** — when a
  runtime image is more minimal than the builder (or fully distroless
  like UBI Micro), there may be no `/bin/sh` for `RUN` to invoke.
  Always-`COPY` is a robust habit
- **`COPY nginx.conf` overrides the package's default** — see the
  next subsection for why we ship our own. Briefly: the default
  RHEL nginx config logs to files under `/var/log/nginx` that
  `kubectl logs` can't see, uses `/run/nginx.pid` (root-only), and
  has a `user nginx;` directive that warns when running as non-root
- **`USER 1001:0`** — UID 1001 with explicit GID 0. The `:0` part
  matters: a bare `USER 1001` may result in GID 1001 (depending on
  the runtime's handling of UIDs absent from `/etc/passwd`), which
  breaks any group-0 permission scheme. OpenShift's pattern is "any
  UID, always GID 0", and `1001:0` is the plain-Kubernetes
  equivalent

### Why we ship our own nginx.conf

The default `/etc/nginx/nginx.conf` from the RHEL/UBI nginx package
needs three changes for a container running as non-root with Pods
that `kubectl logs` can introspect:

1. **Logs to stdout/stderr, not files.** Default RHEL nginx writes
   `access.log` and `error.log` under `/var/log/nginx/`. Those
   files exist inside the container's filesystem; `kubectl logs`
   only reads container stdout/stderr. When something goes wrong
   at runtime — a port-bind permission denied, a worker crash —
   the error message lands in a file you can't see, and the Pod
   crash-loops with no obvious cause
2. **PID file in `/tmp`, not `/run`.** Default is `/run/nginx.pid`
   which is only writable as root
3. **Drop the `user` directive.** The default has `user nginx;` to
   drop privileges from root to the `nginx` user after binding
   port 80. When we're already running as USER 1001, the directive
   does nothing useful and nginx warns about it on startup

`examples/06-deploy-nginx-kubectl/nginx.conf` makes those three
fixes and a fourth: it points all `*_temp_path` directives at
`/tmp/nginx-*`. nginx allocates these temp dirs on startup
regardless of whether your workload uses them — for buffering
large request bodies, proxy responses, FastCGI responses, etc. The
defaults reference `/var/lib/nginx/tmp/*` which our non-root user
can't write. Pointing them at `/tmp` removes the dependency on
`/var/lib/nginx` entirely.

```nginx
worker_processes  auto;
error_log         /dev/stderr  warn;
pid               /tmp/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include            /etc/nginx/mime.types;
    default_type       application/octet-stream;
    access_log         /dev/stdout;
    sendfile           on;
    keepalive_timeout  65;

    client_body_temp_path  /tmp/nginx-client-body;
    proxy_temp_path        /tmp/nginx-proxy;
    fastcgi_temp_path      /tmp/nginx-fastcgi;
    uwsgi_temp_path        /tmp/nginx-uwsgi;
    scgi_temp_path         /tmp/nginx-scgi;

    server {
        listen       8080  default_server;
        listen       [::]:8080  default_server;
        server_name  _;
        root         /usr/share/nginx/html;

        location / {
            index  index.html;
        }
    }
}
```

Same shape as the package default, just rewritten to be friendly to
non-root operation and to `kubectl logs`. Worth saving as a starting
point for your own containerized nginx deployments — the principles
generalize.

### Loading the image into minikube

The image lives only on the build host until you load it into the
cluster. `minikube image build` does both in one command:

```bash
cd examples/06-deploy-nginx-kubectl
minikube image build -t nginx-custom:v1 -f Containerfile .
```

This runs the build inside minikube's environment (using its
in-cluster builder, which speaks BuildKit/buildah). The result is
tagged `nginx-custom:v1` and available immediately to the cluster's
kubelet — no registry push, no `kubectl cp`, no `docker save`
shenanigans.

Confirm with:

```bash
minikube image ls | grep nginx-custom
```

To remove a stale build:

```bash
minikube image rm nginx-custom:v1
```

## A note on SELinux

If you're following along on Fedora (per §1), SELinux is enforcing
on your host. **`:Z` is the volume-mount flag** that relabels host
directories so containers can access them — `podman run -v
/host/path:/in/container:Z`. Without it, a SELinux-protected
directory bind-mounted into a container is unreadable. On macOS or
non-SELinux Linux, `:Z` is a harmless no-op.

This example doesn't need `:Z` because nothing bind-mounts from
the host — the index.html is baked into the image, not mounted in.
But this is the right time to mention the pattern, because **§8
persistent volumes will use it everywhere**. The `:Z` syntax also
appears as `-Z` on the `podman run` command line; both mean "Red
Hat, please relabel the host directory so my container can read
it."

## Writing a Deployment manifest

With the image built and tagged, the Deployment is straightforward
— just point at the image:

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
        image: nginx-custom:v1
        imagePullPolicy: IfNotPresent
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
- **`metadata.name: nginx`** — the object's name, unique within
  its namespace
- **`spec.replicas: 2`** — target replica count
- **`spec.selector.matchLabels`** — which Pods this Deployment
  manages. **Must match `template.metadata.labels` exactly** or
  the Deployment refuses to apply
- **`spec.template`** — the Pod template. Everything from here on
  describes the Pods this Deployment creates
- **`template.spec.containers[].image`** — `nginx-custom:v1`, the
  image we just built. Not in any registry; only in the cluster's
  local image cache
- **`imagePullPolicy: IfNotPresent`** — use the local image if
  present, don't try to pull. For images with the `:latest` tag
  the default is `Always`, which would fail for us; pinning to a
  non-`:latest` tag makes `IfNotPresent` the default, but being
  explicit is good practice for locally-built images
- **`containerPort: 8080`** — declares the port the container
  listens on (matching the nginx config we baked in)
- **`readinessProbe`** — when to consider the Pod ready for
  traffic. Failing readiness pulls the Pod out of Service
  endpoints but doesn't restart it
- **`livenessProbe`** — when to consider the Pod broken and
  restart it. Failing liveness triggers a container restart
- **`resources.requests` / `limits`** — minimum guaranteed
  resources for scheduling, and a cap on usage. CPU is throttled
  at the limit; memory above the limit triggers OOM-kill

The labels are how everything in Kubernetes finds everything else.

### Labels and selectors

`app: nginx` appears in three places in the Deployment manifest:

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
2. Builds the `nginx-custom:v1` image via `minikube image build`
   (cached on re-runs)
3. Applies both manifests
4. Waits for the Deployment to be `Available` (and dumps pod logs
   from current and previous containers on timeout, so failures
   self-diagnose)
5. Starts a `kubectl port-forward` in the background
6. Waits for the port to be listening, curls it, checks for the
   sentinel string from our baked-in index.html
7. Scales to 3 replicas; verifies all three become Ready
8. Cleans up the port-forward + manifests on exit (`trap`); leaves
   the built image in the cache for fast re-runs

Run it:

```bash
cd examples/06-deploy-nginx-kubectl
./demo.sh
```

Expected duration: 2-4 minutes first run (downloads two UBI base
images and runs `microdnf install nginx`); 25-40 seconds after
(image cached).

The demo uses your **default minikube cluster** (not a separate
profile, unlike `examples/03-driver-check/`). It cleans up its
own Deployment/Service but leaves the cluster running and the
built image cached for the next demo.

[On to §7: Services and NodePort →]({{ "/docs/07-services-nodeport/" | relative_url }})
