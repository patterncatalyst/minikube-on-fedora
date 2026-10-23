---
title: "Bibliography"
layout: plan
permalink: /bibliography/
description: "The primary references this tutorial follows for minikube, Kubernetes, and the platform tools it deploys."
---

This is a hands-on tutorial built around official tool documentation rather
than a reading list. The references below are the authoritative sources it
follows; check them for current flags, versions, and behavior. Nothing in these
chapters or the runnable examples copies text from them.

## Primary references

- [minikube documentation](https://minikube.sigs.k8s.io/docs/): the local Kubernetes cluster this tutorial runs on, including the Docker driver and containerd runtime.
- [Kubernetes documentation](https://kubernetes.io/docs/): the API objects, `kubectl`, and the workload, service, and storage concepts the examples deploy.
- [Helm documentation](https://helm.sh/docs/): the chart model and release lifecycle used in the Helm example.
- [Istio documentation](https://istio.io/latest/docs/): the service mesh installed in the mesh example.
- [KEDA documentation](https://keda.sh/docs/): the event-driven autoscaler behind the HTTP and Kafka scaling examples.
- [Fedora documentation](https://docs.fedoraproject.org/): the host platform the tutorial targets.

## Further reading

For the architecture of the data-mesh application the examples deploy, see the
companion [cloud-native tutorials and workshops hub](https://patterncatalyst.github.io/workshops-tutorials-list/),
which collects the related sites and their reading lists.
