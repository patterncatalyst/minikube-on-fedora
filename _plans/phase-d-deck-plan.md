# Phase D — "Data Mesh on OpenShift" implementation deck plan

Spine: **the four principles**, each → the pieces that realize it. OpenShift-forward.
Idealized production-shaped code snippets throughout. Gotchas → Appendix A only.
Reuses the 101 design system (Red Hat brand). Target 1.5–3 h.

Continues exactly where the 101 deck ends (its slide 32–36 "IMPLEMENTATION" turn).

## Arc (section dividers use two-digit eyebrows like the 101 deck)

TITLE (1–2)
- 1. Title: "Data Mesh on OpenShift" — red left panel, eyebrow "THE DATA MESH · IMPLEMENTATION"
- 2. "Where the 101 deck ended" — bridge: principles recap, this deck = the build

00 · FROM PRINCIPLES TO PLATFORM (3–8)
- divider 00
- the four principles, one-slide recap (diagram: four-principles)
- why a platform, and why OpenShift specifically (the value thesis)
- the reference architecture at a glance (diagram: reference-data-mesh-architecture) — centerpiece
- the domain we model (5 products + gateway), production framing
- how to read this deck (principle → pieces → code → value)

01 · DOMAIN OWNERSHIP (9–20)
- divider 01
- the principle (recap from 101, one slide)
- the bottleneck it removes (diagram: central-team-bottleneck)
- monolith → mesh (diagram: monolith-to-mesh)
- ownership = a Project/namespace per domain (OpenShift Projects, multitenancy)
- code: Namespace/Project + ServiceAccount + RBAC Role/RoleBinding
- code: ResourceQuota + LimitRange per domain
- a data product = Deployment + Service (code)
- product owns its data: schema-per-domain (CloudNativePG Cluster, code)
- OpenShift value: Projects, SCCs, project-scoped RBAC, multitenant isolation
- value recap for domain ownership

02 · DATA AS A PRODUCT (21–34)
- divider 02
- the principle (recap)
- anatomy of a data product (diagram: data-product-anatomy)
- discoverable/addressable/trustworthy/self-describing → concrete pieces
- every protocol is a contract (diagram: contracts-registry-catalog)
- runtime vs discovery contracts (diagram: contract-flow)
- code: Avro schema (runtime contract) in the registry
- code: OpenAPI/Protobuf/SDL (discovery contracts)
- the catalog: discovery + lineage (OpenMetadata)
- code: catalog ingestion / lineage config
- the data planes: protocol by fitness (diagram: operational-vs-analytical)
- code: gRPC service def + GraphQL gateway resolver
- async backbone (diagram: ingestion-streaming-sourcing) + code: Kafka/AMQ Streams topic + event
- value recap for data-as-a-product

03 · SELF-SERVE DATA PLATFORM (35–46)
- divider 03
- the principle (recap)
- platform planes (diagram: platform-planes)
- operators as the self-serve mechanism (OperatorHub, OLM)
- code: Kafka cluster via operator (AMQ Streams)
- code: Postgres via operator (CloudNativePG)
- elastic products: KEDA scale-to-zero (diagram: hpa-vs-keda)
- code: KEDA ScaledObject (Kafka lag) + HTTP scaler
- resilience: recoverability as a platform property
- OpenShift value: OperatorHub, GitOps (Argo CD), integrated registry, Routes
- value recap for self-serve platform

04 · FEDERATED COMPUTATIONAL GOVERNANCE (47–58)
- divider 04
- the principle (recap)
- governance model (diagram: federated-governance-model)
- computational, not committee: enforced at the boundary
- progressive delivery: canary a contract (diagram: reference or istio-mesh)
- code: Istio/OSSM VirtualService + DestinationRule (weighted canary)
- mTLS for free (OpenShift Service Mesh / Istio PeerAuthentication, code)
- selective meshing as a design decision (value framing, NOT the war stories)
- admission control / policy (OPA Gatekeeper / Kyverno, code)
- observability as governance: metrics, traces, Kiali
- code: trace span across products (OTel)
- value recap for federated governance

05 · THE WHOLE PICTURE (59–64)
- divider 05
- the reference architecture, fully assembled (diagram: reference-data-mesh-architecture)
- the four principles, realized (table: principle → OpenShift pieces)
- what you can see it do (the acceptance vision: trace, scale, canary, lineage)
- adoption: start small, one principle/product at a time
- where this is NOT the right fit (honest, from anti-patterns)
- conclusion / thank you

APPENDIX A · GOTCHAS (65+)
- divider "A"
- the operational potholes (single-node + rootless were tutorial-specific; here:
  meshed Jobs that never complete, operator-infra TLS collisions, control-plane
  coupling, resource sizing for recovery) — framed as "what we learned running it"
- each: symptom → cause → fix, vendor-neutral

Total ≈ 64 main + appendix ≈ 70+ slides → fits 1.5–3 h.
