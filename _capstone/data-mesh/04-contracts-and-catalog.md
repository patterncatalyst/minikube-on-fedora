---
title: "Contracts & the catalog"
order: 4
description: Versioned contracts in Apicurio and discovery plus lineage in OpenMetadata — and why a catalog is a mesh requirement, not an optional add-on.
duration: 25 min
---

*Part of the [capstone]({{ '/capstone/data-mesh/00-index/' | relative_url }}).*

The [previous page]({{ '/capstone/data-mesh/03-services-and-data-products/' | relative_url }})
established that each service is a data product. But a data product is only useful to
*other* domains if they can find it, understand its shape, trust that it won't change
out from under them, and trace where its data came from. That's what this page is
about: the registry that holds every product's contract, and the catalog that makes
the products discoverable and their lineage visible. This is the
**data-as-a-product** and **federated-governance** principles made operational — and
the place where "catalog" stops being an add-on and becomes a requirement.

## Every protocol is a contract

The mesh speaks four protocols, and each one *is* a contract: the REST API has an
OpenAPI description, the gRPC services have Protobuf definitions, the events have a
schema, and the gateway has a GraphQL SDL. Left informal, these contracts drift —
a field gets renamed, a type changes, and a consumer three domains away breaks with no
warning. The mesh's answer is to give every contract a versioned home in a single
registry, regardless of its format.

![Each service's contract surface — OpenAPI, Protobuf, schema, SDL]({{ '/assets/diagrams/17-capstone-contracts.svg' | relative_url }})

This capstone uses **Apicurio** as that registry, holding all four contract types as
their native artifacts: the event schemas, the gRPC Protobuf definitions, the REST
OpenAPI documents, and the gateway's GraphQL SDL. One registry, every contract — so
there's a single place to ask "what is this product's shape, and what version am I
depending on?"

## Two jobs the registry does: runtime vs. discovery

Here's the distinction that makes the registry more than a documentation folder, and
it's worth getting clear because the two jobs have very different coupling.

![How a contract flows — the runtime path versus the discovery path]({{ '/assets/diagrams/17-capstone-contract-flow.svg' | relative_url }})

A **runtime contract** is load-bearing on the hot path. The event schema is the
example: the producer serializes an event against the registered schema and the
consumer deserializes against it, so the event literally won't encode or decode
correctly if the contract is wrong or missing. The registry is in the live path of
every event. (The gRPC Protobuf definitions are similar in spirit, though compiled
ahead of time rather than fetched at runtime.) Because a runtime contract is
load-bearing, the registry can enforce real governance on it: reject a
schema-incompatible change at publish time, before it can break a single consumer.

A **discovery contract** is different. The OpenAPI document and the GraphQL SDL are
published as the source of truth for a product's shape, but nothing fails at runtime
if they're absent — they exist for humans reading the API, for breaking-change checks
in CI, and for the catalog to ingest. They describe; they don't serialize.

The same registry does both jobs, but the coupling is the thing to internalize: the
runtime path is tightly coupled and online, the discovery path is loosely coupled and
offline. Conflating them — treating a discovery contract as if it were enforced at
runtime, or a runtime contract as if it were just documentation — is how teams get
surprised in both directions.

## The catalog: discovery and lineage

A registry tells you the *shape* of each contract. It doesn't, on its own, tell you
which products exist, who owns them, who consumes whom, or where a given piece of data
ultimately came from. That's the catalog's job.

![Contracts in the registry, discovery and lineage in the catalog]({{ '/assets/diagrams/17-contracts-registry-catalog.svg' | relative_url }})

This capstone layers **OpenMetadata** on top as the catalog. It ingests from the
registry (the contracts), from the database (the schemas each domain owns), and from
the event backbone (the topics), and assembles the picture a consumer actually needs:
the products that exist, their schemas, their owners, and — crucially — their
**lineage**, the who-produces-and-who-consumes graph across domains. When an order is
placed, an event flows to inventory, payment, and notification; the catalog records
that path, so you can answer "if the order schema changes, what's downstream?" without
reverse-engineering it from code.

The sequencing matters and reflects a real dependency: the registry comes before the
catalog, because a catalog with nothing to catalog is empty — the contracts have to
exist before lineage over them can be built.

## Why this is a requirement, not an add-on

It's tempting to treat a catalog as a nice-to-have you bolt on once the "real" system
works. In a data mesh it's the opposite, and this is the conceptually load-bearing
point of the page. The entire premise of a mesh is that domains own their data
independently and other domains consume it without a central team brokering access.
That premise *only works* if products are discoverable and their contracts are
trustworthy. Without a registry, contracts drift and consumers break silently. Without
a catalog, nobody can find products or understand lineage, so in practice they fall
back to asking the central team — which reintroduces exactly the bottleneck the mesh
exists to remove.

So discovery infrastructure isn't decoration on top of a mesh; it's load-bearing
structure. A mesh without a usable catalog degrades into the
[proxy anti-pattern]({{ '/capstone/data-mesh/09-anti-patterns/' | relative_url }}) — a
central team back in the middle of every cross-domain question — even if every other
piece is in place. The registry and catalog are what let federated governance be
*computational*: contracts enforced at publish time, lineage recorded automatically as
part of deploying, rather than standards administered by meeting.

One operational note that belongs to building this rather than to the concept: when the
catalog ingests by running jobs in the cluster, those jobs have to be kept *out* of the
service mesh, or they can't complete. That's a real sharp edge we hit, and it lives
with the operational gotchas rather than here — but it's worth knowing the catalog's
ingestion has a deployment subtlety when a mesh is in play.

With products that describe themselves and a catalog that makes them discoverable, the
next question is how data actually moves between them — the synchronous read paths and
the asynchronous event backbone.
