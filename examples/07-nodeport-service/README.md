# 07-nodeport-service

Exposes the §6 nginx workload through a **NodePort Service** instead
of ClusterIP — giving you a host-reachable URL without `kubectl
port-forward`. This is the second runnable example and the first
one where the cluster's IP is directly hit from your host shell.

## What it tests

Six §7 claims:

1. The `nginx-custom:v1` image is available in the cluster's image
   cache (built from §6's Containerfile if missing — automatic)
2. `kubectl apply -f manifests/` ships both the Deployment and
   NodePort Service cleanly
3. The Deployment reaches `Available` within 3 minutes
4. `minikube service nginx-np --url` returns a non-empty URL
5. Curling that URL from the host shell succeeds (no
   port-forwarding, no tunnel — direct hit via node IP : node port)
6. The response contains the sentinel string from §6's baked-in
   index.html

## Running

```bash
./demo.sh
```

Expected duration:

- **If §6 has been run** (image cached): 25-40 seconds
- **First time** (image build needed): 2-4 minutes (build is
  automatic)

## What you should see

`==> step` lines for each phase, ending in:

```
==> SUCCESS — NodePort Service exposes nginx-np at http://192.168.49.2:30808

  This URL is host-reachable directly (no kubectl port-forward).
  Cleanup on exit removes the Deployment and Service; the image
  stays cached for the next demo.
```

The exact node IP varies (`192.168.49.2` is typical for the podman
driver) but the NodePort `30808` is pinned in the manifest.

## Cluster scope

Uses the **default minikube cluster** (the `minikube` profile),
same as §6. The §7 Deployment and Service use distinct names
(`nginx-np` instead of `nginx`) and labels (`app: nginx-np`) so
they can coexist with §6's resources without selector confusion —
useful if you have §6 resources lying around from manual prose
walkthrough.

## Cleanup

`demo.sh` installs a `trap cleanup EXIT` that deletes Deployment
and Service on script exit (success or failure). The
`nginx-custom:v1` image stays in the cluster's cache for fast
re-runs.

Manual cleanup if needed:

```bash
kubectl delete -f manifests/ --ignore-not-found=true
```

## When this fails

Likely failure modes in order:

1. **`minikube image build` fails** — same paths as §6's failure
   modes (transient network, microdnf hiccup). Retry
2. **`minikube service` returns no URL** — kube-proxy hasn't wired
   the NodePort yet. The demo polls for up to 10 seconds; if it
   times out, the cluster may have a kube-proxy issue.
   `kubectl get pods -n kube-system | grep kube-proxy` will show
   the proxy pod's state
3. **`curl` returns 0 bytes / connection refused** — the URL was
   returned but kube-proxy hasn't connected the NodePort to the
   endpoint yet. The demo polls for 15 seconds; longer than that
   suggests endpoints aren't being populated. `kubectl get
   endpoints nginx-np` should show the Pod IPs; if empty, the
   Service selector isn't matching any Pods
4. **`curl` returns the wrong content** — pods running but not the
   expected ones. `kubectl get pods --all-namespaces -o wide`
   shows where everything's running

For any of these, paste the failing output back.
