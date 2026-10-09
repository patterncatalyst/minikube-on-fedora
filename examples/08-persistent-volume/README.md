# 08-persistent-volume

Demonstrates Kubernetes **PersistentVolumes** (PVs) and
**PersistentVolumeClaims** (PVCs) by deploying nginx with content
served from a PV instead of baked into the image. The demo
includes a real persistence test: capture content from
`http://127.0.0.1:18080/`, delete the Pod, poll the same URL until the
replacement Pod answers, capture again — timestamps match → PV did its job.

The example inverts the §6 pattern. §6 baked content into the
image. §8 uses a generic image; content lives in a PV and outlives
any Pod that mounts it.

## What it tests

Seven §8 claims:

1. minikube's `default-storageclass` + `storage-provisioner`
   addons provide a working `standard` StorageClass with
   `k8s.io/minikube-hostpath` as provisioner
2. A PVC without `storageClassName` is bound to a dynamically
   provisioned PV from the default class
3. An `initContainer` can seed a fresh PV with content before the
   main container starts
4. Mounting the PVC at `/usr/share/nginx/html` overlays the
   image's baked-in content (so the same image can serve different
   content via volume mount)
5. The Deployment reaches `Available` with the PVC mounted
6. Deleting the Pod triggers a replacement that re-mounts the
   same PVC
7. **The replacement Pod sees the same content the original
   wrote** — timestamps match → PV is independent of Pod
   lifecycle

## Running

```bash
./demo.sh
```

Expected duration: 30-50 seconds. Most of it is waiting for the
Pod restart cycle in the persistence test (~15-25 seconds for
the new Pod to come up after deletion).

If `nginx-custom:v1` isn't loaded, add 2-4 minutes for the first
build (`docker build` from §6's Containerfile, then `minikube image
load`). The initContainer uses the pinned
`ubi9/ubi-minimal:9.8-1791279563` image.

## What you should see

`==> step` lines for each phase. Highlights:

```
==> capturing initial content from PV
  initial timestamp from PV: 2026-05-17T04:12:33Z
✓ content seeded by initContainer, served by nginx

==> deleting Pod to test persistence across Pod lifecycle
  old Pod: nginx-pv-abc123-x7y8z
  waiting for replacement Pod (up to 90s)
✓ Pod replaced; Deployment Available again

==> checking new Pod's initContainer log (should report existing content)
    [seed-content] content already exists; persistence is working
✓ initContainer found existing content → PV persisted

==> verifying content persisted across Pod restart
    before Pod restart: 2026-05-17T04:12:33Z
    after Pod restart:  2026-05-17T04:12:33Z
✓ timestamps match — PV did its job across Pod lifecycle

==> SUCCESS — Deployment + PVC + persistence all verified
```

## Cluster scope

Uses the **default minikube cluster** and pins every `kubectl` call to
that context. The `nginx-pv` resources (Deployment, Service, PVC) all
use distinct names from §6 and §7 (`nginx`, `nginx-np`). The Service is
`type: NodePort` on `30080`, published at profile creation as
`127.0.0.1:18080`. That slot is shared with §6, §9 and §12-http, one at
a time: the demo calls `require_free_nodeport 30080` first. The PV the StorageClass
provisions is named like `pvc-<uuid>` and is also distinct from
anything §6/§7 creates.

## Cleanup

`demo.sh` installs a `trap cleanup EXIT` that:

1. Deletes the manifests, which cascades to:
   - Deployment → Pods terminated
   - Service deleted (frees the shared nodePort 30080)
   - PVC deleted → PV auto-deleted (Delete reclaim policy)
2. The minikube node's hostpath directory under
   `/tmp/hostpath-provisioner/` is cleaned by the provisioner

`nginx-custom:v1` stays in the cluster's image cache.

Manual cleanup if needed:

```bash
kubectl --context minikube delete -f manifests/ --ignore-not-found=true
# the PV is auto-deleted; verify with:
kubectl get pv
```

## When this fails

1. **PVC stays `Pending` forever** — the storage-provisioner addon
   is disabled. `minikube addons list` to confirm; `minikube
   addons enable storage-provisioner default-storageclass` to fix
2. **Deployment Pending: `pod has unbound immediate
   PersistentVolumeClaims`** — same root cause as above. The PVC
   isn't binding because there's no provisioner
3. **initContainer crashes** — typically a sh syntax issue (the
   heredoc), or permission denied writing to /content. The
   demo's failure path dumps the initContainer log
4. **Timestamps don't match** — the PV genuinely didn't persist.
   Most likely: the PVC was deleted between Pod lifecycles (the
   demo's cleanup runs on script exit, not between phases — so
   this shouldn't happen in the demo, but might if you've been
   experimenting manually)
5. **The NodePort never answers after the Pod is replaced** — the
   new endpoint needs a few seconds to register. The demo polls for
   30s; longer than that suggests a Service selector mismatch
   (`kubectl --context minikube get endpoints nginx-pv`)
6. **`nodePort 30080 is held by Service ...`** — §6, §9 or §12-http
   holds the shared slot. Run the `kubectl delete svc` command the
   script prints
7. **`does not publish nodePort 30080`** — the profile was created
   without the port map. Run the delete-and-recreate command the
   script prints

For any of these, paste the failing output back.
