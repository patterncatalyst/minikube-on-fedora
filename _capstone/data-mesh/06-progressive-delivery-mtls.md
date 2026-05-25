---
title: "Progressive delivery & mTLS"
order: 6
description: Evolving a contract in the open with an Istio v1→v2 canary, and the decision to mesh selectively rather than enabling injection namespace-wide.
duration: 25 min
---

*Part of the [capstone]({{ '/capstone/data-mesh/00-index/' | relative_url }}).*

Data products evolve. A product that can never change its contract is a product nobody
will build on for long — but a product that changes its contract *carelessly* breaks
every consumer downstream. This page is about evolving safely: shifting traffic
gradually between an old and a new version of a product's contract, with the service
mesh both routing the split and securing the traffic. It's also where the capstone
makes a genuine architectural decision that the rest of the set has been alluding to —
to mesh **selectively** rather than meshing everything — and explains why, from
experience.

![The service mesh — sidecars, mTLS, and traffic management]({{ '/assets/diagrams/11-istio-mesh.svg' | relative_url }})

## Canarying a contract, not just a binary

The interesting thing to canary in a data mesh isn't a new build of the same service —
it's a new version of the *contract*. This capstone takes order-service through a
v1→v2 change: v2 adds a `currency` field to the order response, the canonical
"evolve the contract without breaking clients" move. v1 keeps serving the old shape; v2
serves the new one; and Istio splits live traffic between them by weight, so you can
move from all-v1 to all-v2 gradually, watching for trouble at each step rather than
flipping a switch.

The mechanism is the standard Istio trio: a `DestinationRule` defines the v1 and v2
*subsets* (by a `version` pod label), a `VirtualService` routes a weighted split across
them, and a `Gateway` admits the traffic. Shifting the canary is just re-applying the
`VirtualService` with new weights — 90/10, then 50/50, then 0/100 — so the
progressive rollout is a sequence of one-line weight changes, and rolling back is the
same operation in reverse.

A couple of honest simplifications worth naming. v1 and v2 here run the *same image*
with an environment toggle and a different `version` label, rather than two images from
two commits — that keeps the demo focused on the traffic-management mechanism rather
than an image pipeline, and the Istio mechanics are identical either way. And traffic
enters through the ingress gateway (port-forwarded, under the rootless-podman setup
from §11) rather than from a meshed client, so no client needs to join the mesh for the
canary to work.

This was verified end to end: with the split set to 90/10, a run of 100 requests landed
95 on v1 and 5 on v2; shifted to 50/50, it landed 46 on v1 and 54 on v2 — both within
the expected band, both subsets healthy in the mesh. The contract evolved in the open,
under controlled traffic, exactly as the pattern intends.

## mTLS for free

The same mesh that routes the canary also secures it. When two services are in the
mesh, Istio establishes mutual TLS between their sidecars automatically — each service
proves its identity to the other and the traffic between them is encrypted, with no
change to the application code. That's the **federated computational governance**
principle in action: "traffic between products is authenticated and encrypted" becomes
a property the platform enforces, not a checklist item each team implements. The
service author writes no TLS code; the mesh provides it at the boundary.

## The decision: mesh selectively, not namespace-wide

Here's the architectural choice this page exists to make, and it runs against the
convenient default. Istio offers a one-label switch — mark a namespace
`istio-injection=enabled` and *every* pod created in it gets a sidecar automatically.
It's tempting: one label, whole-namespace mTLS, nothing to think about per workload.
The capstone's position, learned the hard way, is that namespace-wide injection is the
wrong default for a mesh that contains more than just mesh-appropriate services — and
that you should instead opt specific workloads *into* the mesh.

The reasoning is that a sidecar is not free, and it's not appropriate for every kind of
workload. Three categories in particular do not belong in the mesh, and meshing them
ranges from wasteful to actively broken:

- **Batch jobs that are supposed to finish.** A meshed Job gets a sidecar that never
  exits — the proxy keeps running after the job's work is done, so the pod never reaches
  a completed state and the Job hangs forever. The catalog's ingestion jobs hit exactly
  this. A workload that's meant to run-and-terminate cannot carry a sidecar designed to
  run-and-stay.
- **Operator-managed infrastructure with its own TLS.** A managed database that runs its
  own TLS on its internal ports collides with an injected sidecar that re-wraps those
  connections — the database's own encrypted channels break, and it crash-loops. Stateful
  infrastructure that already secures itself doesn't want a second TLS layer wrapped
  around it.
- **Anything where the sidecar's overhead or coupling buys nothing.** Each sidecar
  consumes resources and couples the workload's startup to the mesh control plane being
  reachable. For a workload that isn't doing mesh-managed service-to-service traffic,
  that's cost with no benefit.

Beyond those specific breakages, there's a systemic reason: with namespace-wide
injection, *every* pod creation in the namespace depends on the injection webhook being
reachable. If the mesh control plane has a bad moment, you can't create a database pod,
a job, or anything else — workloads that have nothing to do with the mesh are now
coupled to its health. Selective injection contains that blast radius: only the
workloads that actually need the mesh depend on it.

So the capstone meshes the services that participate in mesh-managed traffic — the ones
doing the canary, the ones that benefit from mTLS and traffic management — and keeps the
database, the batch jobs, and other operator-managed infrastructure *out* of the mesh by
opting them out explicitly. The trade-off is real and worth stating plainly:
namespace-wide injection is genuinely simpler to reason about and gives blanket mTLS
with one label, while selective injection is more work to configure and means you have
to decide, per workload, whether it belongs in the mesh. The capstone takes that
configuration cost in exchange for resilience and correctness — because the failures
above aren't hypothetical, they're what happens otherwise.

> The specific incidents behind this decision — the hung ingestion job, the
> crash-looping database, the control-plane dependency that bit during a node
> recovery — are documented as operational gotchas rather than retold here. This
> page is the *decision*; the gotchas are the *evidence*, in detail.

## Why this belongs to the mesh chapter

Progressive delivery and mTLS are two sides of one capability: a service mesh that sits
between products, routing their traffic and securing it. The canary shows the routing
side — moving consumers from one contract version to the next without a flag day. The
mTLS shows the security side — authenticated, encrypted traffic as a platform property.
And the selective-injection decision is what keeps the mesh an asset rather than a
liability: applied where it helps, kept away from where it hurts.

Next, the other half of operating a mesh under real conditions: scaling products to
match demand — including down to zero — and recovering when things fail.
