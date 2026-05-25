---
title: "The data-mesh capstone — start here"
order: 0
description: "The map — what the capstone builds, the reading order, and a link to each page in the set. Start here."
duration: 5 min
---

This is the reading guide for the data-mesh capstone — the map of what the set covers
and the order to read it in. The capstone takes every building block from the main
tutorial and assembles them into one working system: a data mesh of services that own
their data as products, talk over a deliberate mix of protocols, evolve their contracts
safely, scale to demand, and stay observable throughout.

The set is written to be read straight through the first time — each page picks up where
the last left off, and the cross-references assume you've seen the earlier material. If
you're returning to find one thing, the descriptions below will point you at the right
page.

## How the set is organized

The nine pages fall into three movements. The **conceptual grounding** (pages 1–2)
establishes what a data mesh is and why Kubernetes is a natural substrate for one. The
**implementation** (pages 3–8) builds the system: the services and their data products,
the contracts and catalog that make them discoverable, the data planes they communicate
over, progressive delivery with mutual TLS, elastic scaling and recovery, and the
observability to see it all. The closing page (9) steps back to the **failure modes** —
the conceptual and organizational anti-patterns that derail data-mesh efforts even when
the technology is sound.

## The pages

- [**1 · Concepts & principles**]({{ '/capstone/data-mesh/01-concepts/' | relative_url }}) —
  What a data mesh is, operational versus analytical data, and Dehghani's four
  principles. The grounding before any commands.
- [**2 · Kubernetes as the substrate**]({{ '/capstone/data-mesh/02-kubernetes-substrate/' | relative_url }}) —
  Why the four principles map cleanly onto namespaces, operators, RBAC, and platform
  primitives, and the shape of the system you'll build.
- [**3 · Services & data products**]({{ '/capstone/data-mesh/03-services-and-data-products/' | relative_url }}) —
  The anatomy of a data product, the five domain services plus the gateway, and the
  order-service template the others follow.
- [**4 · Contracts & the catalog**]({{ '/capstone/data-mesh/04-contracts-and-catalog/' | relative_url }}) —
  Versioned contracts in a registry, the runtime-versus-discovery distinction, and why a
  catalog is a mesh requirement rather than an add-on.
- [**5 · The data planes**]({{ '/capstone/data-mesh/05-data-planes/' | relative_url }}) —
  The synchronous read layer (REST, gRPC, a GraphQL gateway) and the asynchronous event
  backbone — and why the capstone uses all of them.
- [**6 · Progressive delivery & mTLS**]({{ '/capstone/data-mesh/06-progressive-delivery-mtls/' | relative_url }}) —
  Evolving a contract in the open with a v1→v2 canary, mTLS for free, and the decision to
  mesh selectively rather than namespace-wide.
- [**7 · Elastic & resilient**]({{ '/capstone/data-mesh/07-elastic-and-resilient/' | relative_url }}) —
  Scaling to demand and to zero with KEDA, and the cloud-native recoverability the
  platform provides.
- [**8 · Observability**]({{ '/capstone/data-mesh/08-observability/' | relative_url }}) —
  Metrics, distributed traces across products, and the live view of traffic moving
  through the mesh.
- [**9 · Anti-patterns**]({{ '/capstone/data-mesh/09-anti-patterns/' | relative_url }}) —
  The conceptual and organizational ways data-mesh efforts go wrong, drawn from the
  literature, so you can recognize them early.

## If you have time for only a few

Read [**concepts**]({{ '/capstone/data-mesh/01-concepts/' | relative_url }}) for the
vocabulary, [**contracts & the catalog**]({{ '/capstone/data-mesh/04-contracts-and-catalog/' | relative_url }})
for the idea that holds a mesh together, and
[**anti-patterns**]({{ '/capstone/data-mesh/09-anti-patterns/' | relative_url }}) for what
to avoid. Those three cover the shape of the thing without the full implementation
depth.

Start with [concepts & principles]({{ '/capstone/data-mesh/01-concepts/' | relative_url }}).
