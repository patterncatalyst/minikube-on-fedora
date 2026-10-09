---
title: Persistent volumes
order: 8
description: PersistentVolumes, PersistentVolumeClaims, and StorageClasses — giving stateful workloads storage that outlives any Pod.
duration: 25 minutes
---

Containers in Kubernetes are ephemeral. When a Pod dies — and
they do, for upgrades, node drains, OOM kills, your own `kubectl
delete pod` — everything written to the container's filesystem
disappears with it. For stateless workloads like the nginx
servers in §6 and §7 that's fine: spin up another Pod and you
get the same baked-in content.

Stateful workloads are different. A database, a CMS, an upload
endpoint, a build cache — anything that produces data that must
survive past one Pod's lifecycle. This section covers the three
Kubernetes resources that handle that case, and walks through an
example that *inverts* the §6 pattern: same image, content that
lives in storage, not the image.

## Three volume concepts

Worth getting clear up front because they're easy to conflate.

### Volume

A **Volume** is a directory mounted into a container. Its
lifetime is tied to the Pod that uses it: when the Pod is
deleted, the Volume goes with it (with one important exception —
see PVs below).

You define Volumes in the Pod spec under `spec.volumes` and
mount them into containers via `spec.containers[*].volumeMounts`.
This is the basic plumbing every Pod uses, even ones that don't
need persistence — `emptyDir` Volumes are how containers in a
single Pod share files, for example.

### PersistentVolume (PV)

A **PersistentVolume** is a cluster-scoped storage resource. The
actual disk, NFS export, cloud volume, or hostPath that bytes get
written to. PVs are typically created by cluster operators or
provisioned dynamically by a StorageClass (see below) —
application developers don't usually write PV manifests by hand.

The "Persistent" part means: PV lifetime is **independent of any
Pod's lifetime**. A Pod can be deleted, recreated, scheduled to a
different node, and the PV's data is still there for the next
Pod to mount.

### PersistentVolumeClaim (PVC)

A **PersistentVolumeClaim** is a Pod's request for storage. The
PVC says "I need 100Mi of storage that I can read and write" —
not *where* that storage comes from. Kubernetes binds the PVC to
a suitable PV, and the Pod mounts the PVC.

PVCs are what application developers write. The cluster handles
the rest.

The relationship:

```
Pod  ───mounts───►  PVC  ───bound to───►  PV  ───backed by───►  storage
```

## StorageClasses and dynamic provisioning

In old Kubernetes (1.5 era), PVs were pre-created by operators
and PVCs were matched to them statically. Out of PVs?
Application Pods stuck Pending forever.

Dynamic provisioning fixed that. A **StorageClass** defines a
*template* for creating PVs on demand. When a PVC is created
without an existing PV that fits, the StorageClass automatically
provisions a new PV.

minikube ships with a default StorageClass via the
`default-storageclass` and `storage-provisioner` addons (both
enabled by default — `minikube addons list` confirms):

```bash
kubectl get storageclass
```

Expected:

```
NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE   ...
standard (default)   k8s.io/minikube-hostpath   Delete          Immediate           ...
```

The default StorageClass is `standard`. It backs PVs with
directories on the minikube node's filesystem (under
`/tmp/hostpath-provisioner/`, inside the node container, not on your
host). Not production-grade, perfect for local development. The
directories are writable by the non-root seed container and nginx on
Docker Engine; the hostPath permission failures that rootless Podman
produced are recorded in [LESSONS-LEARNED, Part
4](https://github.com/patterncatalyst/minikube-on-fedora/blob/main/onboarding/LESSONS-LEARNED.md).

When a PVC has no `storageClassName`, the default StorageClass
handles it.

## The example: same image, different content

§6 and §7 baked content into the container image. §8 inverts
that: the image is generic; content lives in a PV that outlives
any Pod.

The mechanism is an **initContainer** that seeds the volume with
content the first time it's empty. On subsequent Pod restarts
the content is already there, so the initContainer leaves it
alone. The before/after timestamps in the seeded content make
persistence trivially observable.

### The PVC

`examples/08-persistent-volume/manifests/pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-content
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
```

Three fields worth understanding:

- **`accessModes: [ReadWriteOnce]`** — RWO. Volume can be mounted
  by Pods on **one node at a time** with read+write access. For
  nginx with one replica on one minikube node, that's fine; for
  multi-node clusters with multiple replicas you'd want
  `ReadWriteMany` and a backend that supports it (NFS, CephFS,
  EFS, etc.)
- **`resources.requests.storage: 100Mi`** — 100 mebibytes. The
  provisioner allocates at least this much; you may get more
- **No `storageClassName`** — falls through to the default
  StorageClass (`standard`)

### The Deployment

`examples/08-persistent-volume/manifests/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-pv
  labels:
    app: nginx-pv
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-pv
  template:
    metadata:
      labels:
        app: nginx-pv
    spec:
      initContainers:
      - name: seed-content
        image: registry.access.redhat.com/ubi10/ubi-minimal:10.2-1791444377
        command:
          - "/bin/sh"
          - "-c"
          - |
            set -e
            if [ -f /content/index.html ]; then
              echo "[seed-content] content already exists; persistence is working"
              cat /content/index.html
            else
              echo "[seed-content] seeding fresh content into PV"
              cat > /content/index.html <<EOF
            <h1>Test Page for nginx on UBI 9 Minimal (from PV)</h1>
            <p>This file was written into the PersistentVolume at:</p>
            <p>$(date -u +%Y-%m-%dT%H:%M:%SZ)</p>
            <p>If this timestamp is unchanged after a Pod restart, the PV is doing its job.</p>
            EOF
            fi
        volumeMounts:
        - name: content
          mountPath: /content
      containers:
      - name: nginx
        image: nginx-custom:v1
        # Same image as §6/§7 — generic nginx; content comes from
        # the volume mount below, not the image
        imagePullPolicy: Never
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
        volumeMounts:
        - name: content
          mountPath: /usr/share/nginx/html
      volumes:
      - name: content
        persistentVolumeClaim:
          claimName: nginx-content
```

Two patterns at work here.

**initContainer for first-run seeding.** The `seed-content`
container runs **before** nginx starts. It checks if
`/content/index.html` already exists; if so, it leaves it alone.
If not, it writes a timestamped HTML page. Because the
initContainer only writes when the file is missing, the
timestamp stays fixed at the time of *first* Pod startup. On
restarts, the initContainer sees the file and skips — the
timestamp persists.

**Volume mount overlays the image's content.** The nginx
container mounts the PVC at `/usr/share/nginx/html`. That path
exists in `nginx-custom:v1` (with the §6-baked index.html). When
the PVC is mounted, the mount **overlays** the image's content —
nginx sees only the PV's contents, not the image's. This is
exactly how you'd run a generic image with content that lives in
a separate, persistent location.

`replicas: 1` because we requested RWO. Multiple replicas on the
same minikube node would work, but the demo stays unambiguous
with one.

### The Service

`examples/08-persistent-volume/manifests/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-pv
  labels:
    app: nginx-pv
spec:
  type: NodePort
  selector:
    app: nginx-pv
  ports:
  - port: 80
    targetPort: 8080
    # Published to 127.0.0.1:18080 at profile creation
    # (--ports=127.0.0.1:18080:30080). Shared slot with §6, §9, §12-http.
    nodePort: 30080
    protocol: TCP
```

A NodePort Service on 30080, the same slot §6 used and the one the
`minikube` profile publishes to `127.0.0.1:18080`. **Delete §6's
`nginx` Service first** (`kubectl delete -f
examples/06-deploy-nginx-kubectl/manifests/`): two Services cannot
hold the same nodePort, and the demo's preflight stops with a "delete
X first" message if one does. Commands in this chapter assume the
`minikube` kubectl context from §4.

## Apply, observe, persist, verify

```bash
kubectl apply -f examples/08-persistent-volume/manifests/
```

Order doesn't matter; Kubernetes resolves the references
asynchronously. Watch the PVC bind:

```bash
kubectl get pvc nginx-content
```

```
NAME            STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS
nginx-content   Bound    pvc-a83b…    100Mi      RWO            standard
```

`STATUS: Bound` means a PV was provisioned and the PVC is using
it. `kubectl get pv` shows the auto-created PV itself.

Curl the published port:

```bash
curl http://127.0.0.1:18080/
```

You should see a timestamped HTML page — note the timestamp.

### Watching persistence in action

Delete the Pod:

```bash
kubectl delete pod -l app=nginx-pv
```

The Deployment immediately creates a replacement. When it's
ready, curl again:

```bash
kubectl wait --for=condition=Ready pod -l app=nginx-pv --timeout=60s
curl http://127.0.0.1:18080/
```

Nothing needs re-attaching: the NodePort routes to whichever Pod is
Ready, so the second request just works. (Right after the old Pod is
deleted there can be a second or two with no ready endpoint; the demo
polls instead of assuming.)

**The timestamp matches.** The new Pod's initContainer found the
file already in the PVC, left it alone; nginx serves the content
that was created during the first Pod's startup. PV data is
independent of Pod lifecycle.

## Reclaim policy and cleanup

When you delete a PVC, what happens to its PV depends on the
PV's **reclaim policy**:

- **`Delete`** (the default for the minikube standard
  StorageClass) — the PV is deleted along with the PVC, data
  gone
- **`Retain`** — the PV is kept in a `Released` state after the
  PVC is deleted. An operator must reclaim it manually. Useful
  for "I might still need this data" scenarios

```bash
kubectl delete -f examples/08-persistent-volume/manifests/
```

Deletes the Deployment, Service, and PVC. The PV is auto-deleted
(Delete policy). The hostpath directory under the minikube
node's `/tmp/hostpath-provisioner/` is cleaned up by the
storage-provisioner.

## Verification: examples/08-persistent-volume/

`examples/08-persistent-volume/demo.sh` runs the §8 happy path
**with** persistence verification:

1. Pre-flight: Docker Engine, `minikube` profile with published
   ports, pinned context; `standard` StorageClass present; image
   loaded (auto-build and load from §6 if not)
2. Clears any prior `nginx-pv` resources and checks nodePort 30080
   is free
3. Applies the manifests
4. Waits for the PVC to bind and the Deployment to be Available
5. Confirms `docker port minikube 30080/tcp` and waits for
   `http://127.0.0.1:18080/`
6. Curls; captures the timestamp from the HTML
7. **Deletes the Pod;** waits for the Deployment's replacement
   to be Ready
8. Polls `http://127.0.0.1:18080/` until the replacement Pod answers
9. Curls again; **verifies the timestamp matches** — persistence
   confirmed
10. Cleans up Deployment + Service + PVC on exit, freeing nodePort
    30080

```bash
cd examples/08-persistent-volume
./demo.sh
```

Expected duration: 30-50 seconds; most of it is waiting for the
Pod restart cycle in the persistence test.

[On to §9: helm →]({{ "/docs/09-helm/" | relative_url }})
