---
title: "Capstone: a data mesh on minikube"
order: 17
description: A working data-mesh implementation that exercises everything from §1–§12 in one coherent system — services across REST, gRPC, GraphQL, and Kafka, deployed via helm to a dedicated minikube profile, with contracts, a catalog, progressive delivery, autoscaling, and full observability.
duration: multi-session
---

This is the section where everything converges. The earlier sections introduced the building blocks individually — minikube profiles, kubectl, helm, Istio, KEDA, Strimzi. §17 puts them together into a single coherent system that demonstrates *when, how, and why* each one earns its place. It's the largest part of the tutorial by far, and the one that justifies the time invested in §1–§12.

The system built here is a **data mesh**: a domain of services modeling order-placement-through-shipment, with each service owning its data, its API surface, and its operational lifecycle. The services communicate through a deliberate mix of REST, gRPC, GraphQL, and Kafka — each protocol's strengths showing up in a different context.

Because the capstone is so much larger than the other sections, it's organized as its own set of pages with its own reading order, rather than one long section here.

## Where the capstone continues

This capstone grew into two standalone reference architectures that
take the same data mesh further:

- [**Data mesh reference architecture — Python**](https://patterncatalyst.github.io/datamesh-reference-arch-python/)
  ([repo](https://github.com/patterncatalyst/datamesh-reference-arch-python))
  is a fork of this capstone, broken out for its own audience. It
  carries the same services and domain, with its own workshop
  chapters, demos and an OpenShift Local appendix.
- [**Data mesh reference architecture — Quarkus**](https://patterncatalyst.github.io/datamesh-reference-arch-quarkus/)
  ([repo](https://github.com/patterncatalyst/datamesh-reference-arch-quarkus))
  builds the same mesh with Quarkus and Camel.

Use this capstone to see how §1–§12 fit together on one minikube
profile; use the reference architectures when the data mesh itself
is the subject.

<p><a class="btn btn--primary" href="{{ '/capstone/data-mesh/' | relative_url }}">Start the capstone: a data mesh on minikube →</a></p>
