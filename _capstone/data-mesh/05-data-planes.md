---
title: "The data planes"
order: 5
description: The async backbone of Kafka events and the read layer of GraphQL composing REST and gRPC — when to reach for each, and why the capstone uses all of them.
duration: 25 min
---

*Part of the [capstone]({{ '/capstone/data-mesh/00-index/' | relative_url }}).*

The [services]({{ '/capstone/data-mesh/03-services-and-data-products/' | relative_url }})
each expose a contract, and the
[catalog]({{ '/capstone/data-mesh/04-contracts-and-catalog/' | relative_url }}) makes
them discoverable. This page is about how data actually *moves* between them — the
planes the mesh runs on. There are two: a **synchronous read layer** (REST, gRPC, and
a GraphQL gateway composing across them) and an **asynchronous event backbone** (the
streaming spine that lets domains react to each other). The capstone uses all of them
on purpose, and the purpose is the point.

## Protocols by fitness, not by hierarchy

It would be simpler to pick one protocol and use it everywhere. The capstone
deliberately doesn't, because the honest lesson is that each protocol is *best at a
different job*, and a data mesh exercises all those jobs. This isn't a ranking where
one protocol wins; it's a matter of fitness for context:

- **REST at the edge.** External clients meet the system over REST, because it's the
  universal, cacheable, tooling-rich lingua franca for crossing a trust boundary.
- **gRPC between services internally.** Synchronous service-to-service calls inside the
  mesh use gRPC, because it's fast, strongly typed from its Protobuf contract, and
  built for exactly that low-latency internal RPC.
- **GraphQL for composing reads.** When a client needs data assembled from several
  domains in one shaped response, GraphQL composes it — one query, multiple backends,
  the response shaped by the caller rather than by each service.
- **Events for everything asynchronous.** When something *happens* and other domains
  need to react without the producer waiting on them, the event backbone carries it.

The capstone makes this concrete in one place: the gateway's resolvers literally call
REST and gRPC side by side, and GraphQL stitches the result — so you can see all three
synchronous protocols cooperating rather than competing.

## The read layer: a gateway that composes

A consumer that wants an order *and* its current stock level *and* its payment status
shouldn't have to call three services and join the results by hand. The read layer
solves that with a GraphQL gateway: the client sends one query, and the gateway's
resolvers fetch each piece from the owning service over that service's existing
interface — the order from order-service over REST, the nested stock field from
inventory-service over gRPC — and GraphQL assembles the shaped response.

![How analytical data is composed across domains into a served product]({{ '/assets/diagrams/17-analytical-data-composition.svg' | relative_url }})

There's an important precision here about *how* the gateway composes, because there are
two ways to build a unified GraphQL graph and they're often conflated. In **true
subgraph federation**, each service exposes its own GraphQL subgraph and a gateway
plans queries across them into a supergraph — each domain owns and evolves its slice of
the graph independently. That's the production-scale pattern. This capstone uses the
simpler **gateway orchestration** approach instead: one stateless gateway exposes the
unified graph, and its resolvers fetch from the services over their *existing* REST and
gRPC interfaces, with no GraphQL added to the domain services at all.

The reason is honesty about what the capstone is — a learning implementation. Gateway
orchestration demonstrates the *value* GraphQL adds (one client query, multiple
backends, client-shaped response) with one new service and zero changes to the five
domain services, and it makes the protocol comparison vivid because the resolvers call
REST and gRPC right next to each other. The trade-off worth stating: true federation is
what you'd reach for in production, because it preserves domain ownership of the graph
— with orchestration, the gateway has some knowledge of how to reach each domain. For
teaching the shape, orchestration is the right call; for a production mesh, federation
keeps the ownership boundary cleaner. (This is also why the gateway is *not* itself a
domain data product — it's a read-layer convenience that composes products it doesn't
own.)

## The async backbone: domains reacting to events

The read layer is request-and-response: a consumer asks, a service answers, the caller
waits. The other plane is the opposite shape, and it's what actually keeps a mesh's
operational/analytical loop closed. When an order is placed, several domains need to
react — inventory adjusts stock, payment processes, notification informs the customer —
but the order service shouldn't block waiting on any of them, and it certainly
shouldn't call them in a synchronous chain that fails if one is down. Instead it emits
an event, and the interested domains consume it on their own schedule.

![Domain events and change-data-capture feeding the analytical side]({{ '/assets/diagrams/17-ingestion-streaming-sourcing.svg' | relative_url }})

This capstone builds that spine on a Kafka cluster managed by an operator, and models
the canonical pattern with the smallest real flow: order-service emits an
`order.placed` event, keyed by order id, and notification-service consumes it. That one
flow is the whole "something happened, downstreams react" shape in miniature — the
producer doesn't know or care who's listening, and consumers can be added without
touching the producer. Widen it and you get the full choreography: inventory and
payment also react to `order.placed`, shipping reacts to `payments.processed`, and
notification listens across all of them.

This is the plane that distinguishes a data mesh from a pile of services behind a
gateway. The synchronous read layer composes *current* state on demand; the event
backbone propagates *change* as it happens, so analytical consumers attach to the live
operational flow rather than to a stale nightly extract. That's the closed loop the
[concepts page]({{ '/capstone/data-mesh/01-concepts/' | relative_url }}) introduced —
and its absence is the
[open-loop anti-pattern]({{ '/capstone/data-mesh/09-anti-patterns/' | relative_url }}),
where downstream products are disconnected from the operational systems that feed them.

## Two planes, one mesh

The synchronous and asynchronous planes aren't competitors; they're complementary, and
a mesh needs both. Reads compose current state when a consumer asks for it. Events
propagate change when something happens. REST crosses the boundary, gRPC moves between
services, GraphQL shapes the composite, and the event backbone carries the reactions.
Each protocol earns its place by being best at its job — which is the whole argument
for using all of them rather than forcing one to do everything.

With data moving across both planes, the next concern is how the mesh evolves safely
while it's running: shipping a new version of a product's contract without breaking the
consumers depending on it.
