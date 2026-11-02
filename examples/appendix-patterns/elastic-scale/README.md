# Elastic Scale

Runnable example for the [Elastic Scale chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/23-elastic-scale/).

Three autoscalers, two shipping services: `shipping-service` under an HPA and
a Recommendation-only VPA (resource-based scaling, never below one replica),
and `graphql-gateway` under a KEDA `HTTPScaledObject` (event-based,
scale-to-zero). A reference-only Kafka consumer-lag `ScaledObject` rounds out
the KEDA half without being applied live, since nothing in this appendix's
`shipping-service` skeleton actually consumes a Kafka topic.

## Part 1: HPA and VPA on shipping-service

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh shipping-service v1
kubectl --context mof-patterns apply -n patterns -f elastic-scale/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f elastic-scale/01-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=shipping-service -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f elastic-scale/02-hpa.yaml
kubectl --context mof-patterns get hpa shipping-service -n patterns
```

`TARGETS` reads `<unknown>/50%` for the first few seconds while
metrics-server's first scrape lands, then settles to the actual percentage.
Generate load from inside the cluster to push it up:

```bash
kubectl --context mof-patterns run load-generator -n patterns --image=busybox:1.37 --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://shipping-service/health; done'
kubectl --context mof-patterns get hpa shipping-service -n patterns -w
```

Replicas climb from 1 toward 5 as the average CPU request percentage crosses
50%, then settle back down a few minutes after the load stops (HPA's default
downscale stabilization window). Stop the generator:

```bash
kubectl --context mof-patterns delete pod load-generator -n patterns
```

### VPA: recommendations, not automatic changes

VPA needs its own components, not bundled with any minikube addon. Either the
upstream install script from the autoscaler repo:

```bash
git clone https://github.com/kubernetes/autoscaler.git /tmp/autoscaler
cd /tmp/autoscaler/vertical-pod-autoscaler
KUBECONFIG=<path-from-'kubectl config view --minify --raw'> ./hack/vpa-up.sh
```

or the community Helm chart:

```bash
helm repo add fairwinds-stable https://charts.fairwinds.com/stable
helm repo update fairwinds-stable
helm install --kube-context mof-patterns vpa fairwinds-stable/vpa \
  --version 5.1.0 -n vpa --create-namespace --wait
```

Either installs the same three components (recommender, updater, admission
controller). With VPA running:

```bash
kubectl --context mof-patterns apply -n patterns -f elastic-scale/03-vpa.yaml
kubectl --context mof-patterns describe vpa shipping-service -n patterns
```

`updateMode: "Off"` means `describe` is the whole interaction: a
`recommendation` block showing a `target` CPU/memory pair computed from
actual usage, with nothing in the cluster acting on it automatically. That
matters alongside the HPA above running on the same Deployment: VPA in
`"Auto"` mode rewrites a Pod's own CPU request, which would retroactively
change the denominator HPA's utilization percentage is computed against,
out from under it, on the same resource, at the same time. `"Off"` mode
sidesteps the conflict by design: a human (or a separate, deliberate change)
decides whether to act on VPA's number, rather than two controllers fighting
over the same field.

## Part 2: KEDA scale-to-zero on graphql-gateway

Install KEDA core plus the HTTP add-on onto the `mof-patterns` profile
(pinned to the same versions the §12 KEDA chapter uses):

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update kedacore
helm install --kube-context mof-patterns keda kedacore/keda \
  --version 2.21.0 -n keda --create-namespace --wait --timeout 5m
helm install --kube-context mof-patterns keda-add-ons-http kedacore/keda-add-ons-http \
  --version 0.16.0 -n keda --wait --timeout 5m
```

Build and deploy the gateway, starting at zero replicas:

```bash
cd examples/appendix-patterns
./scripts/build-service.sh graphql-gateway v1
kubectl --context mof-patterns apply -n patterns -f elastic-scale/04-gateway-deployment.yaml
kubectl --context mof-patterns apply -n patterns -f elastic-scale/05-gateway-httpscaledobject.yaml
kubectl --context mof-patterns get deployment graphql-gateway -n patterns
```

`REPLICAS` reads `0`: the `HTTPScaledObject` owns this count from the moment
it was applied, the same way the Operator chapter's `ShippingPolicy` owns its
own child Deployment's replica count, just through KEDA's generated HPA
instead of a hand-written reconciler.

Reach the interceptor and send one request:

```bash
kubectl --context mof-patterns port-forward -n keda svc/keda-add-ons-http-interceptor-proxy 8080:8080 &
curl -H 'Host: graphql-gateway.patterns' http://127.0.0.1:8080/health
```

The first request is slow: the interceptor holds it open while the
scale-from-zero HPA spins up a Pod, then forwards it once the Pod reports
Ready. Watch the climb and the eventual return to zero in a second terminal:

```bash
kubectl --context mof-patterns get deployment graphql-gateway -n patterns -w
```

Thirty seconds (`scaledownPeriod`) after the last request, replicas return to
zero. Stop the port-forward (`kill %1` or `Ctrl-C`) when done.

## Part 3: the Kafka consumer-lag shape (reference only)

`06-shipping-kafka-scaledobject.yaml` is the Kafka consumer-lag counterpart
to the HTTP add-on above, identical in shape to the data mesh's own
`notification-service-scaler`. It is not applied in this chapter's run:
`shipping-service` here is the same REST-only skeleton every other chapter
in this appendix uses, with no Kafka consumer loop of its own, so its
`bootstrapServers` trigger would never resolve a real lag number. Read it
alongside `04-gateway-httpscaledobject.yaml` as the other half of KEDA's
story: one trigger type measuring HTTP concurrency, the other measuring an
external queue's backlog, both capable of the same zero-to-N-to-zero
lifecycle the §12 KEDA chapter demonstrates live against a real Strimzi
cluster.

![HPA and VPA watching shipping-service's own resource usage; KEDA's HTTPScaledObject watching request concurrency in front of graphql-gateway instead, scaling it from zero]({{ "/assets/diagrams/appendix-23-elastic-scale.svg" | relative_url }})
*Resource-based autoscaling reads the Pods themselves; KEDA reads an external signal instead, which is the only path to scaling below one replica.*

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f elastic-scale/05-gateway-httpscaledobject.yaml
kubectl --context mof-patterns delete -n patterns -f elastic-scale/04-gateway-deployment.yaml
helm uninstall --kube-context mof-patterns keda-add-ons-http -n keda
helm uninstall --kube-context mof-patterns keda -n keda
kubectl --context mof-patterns delete -n patterns -f elastic-scale/03-vpa.yaml --ignore-not-found
helm uninstall --kube-context mof-patterns vpa -n vpa   # if installed via the Helm chart; otherwise ./hack/vpa-down.sh
kubectl --context mof-patterns delete -n patterns -f elastic-scale/02-hpa.yaml
kubectl --context mof-patterns delete -n patterns -f elastic-scale/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f elastic-scale/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
