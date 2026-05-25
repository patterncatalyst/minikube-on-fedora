// Build the Data Mesh on OpenShift implementation deck — v2.
// Diagrams-forward (YAML replaced by diagrams where it doesn't teach); Python API
// examples kept; per-section value-closer diagrams; speaker notes on every slide.
const L = require("./deck-lib.js");
const { pres, C, F, PW, PH, titleSlide, divider, contentSlide, diagramSlide, codeSlide } = L;
const code = (s) => s.replace(/\t/g, "  ");

/* ============================ TITLE ============================ */
titleSlide({
  eyebrow: "Data Mesh · Implementation",
  title: "Data Mesh on OpenShift",
  subtitle: "From the four principles to a running platform — domains owning data as products, on the platform and governance that let them interoperate.",
  tagline: "A reference implementation",
  breadcrumb: "OpenShift · AMQ Streams · CloudNativePG · Service Mesh · KEDA · OpenMetadata",
  notes: "Welcome. This is the implementation companion to the Data Mesh 101 deck. Where 101 made the conceptual case, today we build it — on OpenShift, principle by principle, with the real pieces and the code. Set expectations: a 1.5–3 hour walk through a reference architecture. For each principle I'll show the value it delivers and the OpenShift pieces that deliver it. Today is about the value of the whole — the principles and the pieces that realize them.",
});

/* ============================ AGENDA ============================ */
L.agendaSlide({
  left: [
    { text: "00 · From principles to platform" },
    { text: "01 · Domain ownership" },
    { text: "02 · Data as a product" },
    { text: "03 · Self-serve data platform" },
  ],
  right: [
    { text: "04 · Federated computational governance" },
    { text: "05 · The whole picture" },
    { text: "06 · Anti-patterns" },
  ],
  notes: "The agenda. Seven sections. The spine is the four data-mesh principles (01–04), bookended by an orientation section (00), a synthesis (05), and the anti-patterns (06) that close out the talk. Point out the shape: each principle section follows the same rhythm — principle, pieces, code, value. Roughly 1.5–3 hours depending on how deep you go on the code and diagrams.",
});

(() => {
  const s = pres.addSlide();
  s.background = { color: C.white };
  L.head(s, "Where the 101 deck ended", "From the idea to the running platform");
  L.addBullets(s, [
    { text: "The Data Mesh 101 deck made the case: centralized data platforms stall, and the answer is to decentralize ownership — domains own their data as products on a shared, self-serve platform under federated, automated governance.", },
    { text: "That deck ended by pointing at implementation. This deck is the implementation.", color: C.ink },
    { head: true, text: "What this deck does" },
    { text: "Takes each of the four principles and shows the concrete OpenShift pieces that realize it — with the architecture and the code, not just the diagram." },
    { text: "Frames every piece by the value it delivers: why it earns its place in a production data mesh." },
    { text: "Stays focused on value and the conceptual shape — the through-line is the four principles and how they're realized." },
  ], { x: 0.7, y: 1.95, w: PW - 1.4 });
  L.footer(s);
  s.addNotes("Bridge from 101. If your audience saw the 101 deck, this is a quick recap; if not, it's the whole premise in four sentences. The key move: we are not going to argue for data mesh again — we're going to build one. Emphasize the last bullet: the talk stays on value and the conceptual shape, closing with the anti-patterns that most often derail real efforts.");
})();

/* ====================== 00 · FROM PRINCIPLES TO PLATFORM ====================== */
divider({ num: "00", title: "From principles to platform", sub: "The four principles, the reference architecture, and how to read what follows.",
  notes: "Section 0 is orientation: the four principles in one diagram, the reference architecture we build toward, the domain we model, and the rhythm each section follows. Keep it brisk — the map, not the territory." });

diagramSlide({ eyebrow: "The four principles", title: "Four principles — and how they map in practice",
  image: "four-principles",
  caption: "The tools are expressions of the pattern, not the pattern itself. Each principle below maps to concrete platform pieces.",
  notes: "Straight from the 101 deck, deliberately, so the decks connect. Walk left to right: domain ownership, data as a product, self-serve platform, federated governance. The bottom row of each card already names the Kubernetes/OpenShift primitive — that's the whole structure of today's talk in one slide. The four interlock: implement one without the others and you get a distributed mess, not a mesh." });

(() => {
  const s = pres.addSlide();
  s.background = { color: C.white };
  L.head(s, "Why a platform — and why OpenShift", "The value thesis");
  L.addBullets(s, [
    { text: "A data mesh is a socio-technical pattern. The technical half needs a platform that makes domain ownership, product packaging, self-serve infrastructure, and computational governance the path of least resistance — not a fight.", },
    { head: true, text: "OpenShift gives each principle a home" },
    { text: "Domain ownership → Projects, project-scoped RBAC, SCCs, quotas.", lvl: 1 },
    { text: "Data as a product → Deployments, Services, Routes, CRDs for domain types.", lvl: 1 },
    { text: "Self-serve platform → OperatorHub + OLM, GitOps, the integrated registry, AMQ Streams, Service Mesh.", lvl: 1 },
    { text: "Federated governance → Service Mesh mTLS, admission policy, schema enforcement, built-in observability.", lvl: 1 },
    { text: "The rest of this deck is that mapping, principle by principle, with the code that makes it real.", color: C.ink },
  ], { x: 0.7, y: 1.95, w: PW - 1.4 });
  L.footer(s);
  s.addNotes("The thesis slide. A data mesh fails for organizational reasons far more than technical ones, so the platform's job is to make the right thing the easy thing. OpenShift earns its place because each principle has a home in primitives the audience already knows. Don't dwell on each bullet — they're a preview; we spend a section on each. Payoff line: this whole deck is that mapping.\n\nDefinitions:\n• OperatorHub — OpenShift's catalog of installable operators; the platform team curates what's available.\n• OLM (Operator Lifecycle Manager) — installs, updates, and manages the lifecycle of operators on the cluster.\n• GitOps — desired cluster state lives in Git and is continuously reconciled onto the cluster (OpenShift GitOps is based on Argo CD).\n• RBAC (Role-Based Access Control) — Kubernetes' permission model; Roles grant verbs on resources, RoleBindings bind them to users/groups, enforced by the API server.\n• SCC (Security Context Constraint) — OpenShift policy controlling what a pod may do on the node (run as root, mount host paths, privileged, etc.).\n• mTLS (mutual TLS) — both client and server present certificates; the mesh establishes it automatically between sidecars, with no app code.\n• Admission control — the API-server gate that validates or rejects resources as they're created; where computational governance runs.\n• Service Mesh (OpenShift Service Mesh / Istio) — a layer of sidecar proxies that secures, routes, and observes service-to-service traffic.\n• AMQ Streams — Red Hat's supported distribution of Strimzi: Apache Kafka run on Kubernetes via operators.");
})();

diagramSlide({ eyebrow: "Reference architecture", title: "The data mesh, at a glance",
  image: "reference-data-mesh-architecture",
  caption: "The centerpiece: domain data products, the platform planes beneath them, and the governance and observability that span them. We assemble this piece by piece.",
  notes: "The centerpiece — we return to it assembled at the end. Now, just orient: top is external clients, the middle band is the meshed domain services, the bottom is the self-serve platform, and observability spans the whole. Don't explain every box yet — promise that by the end every piece here will have been built and they'll recognize all of it." });

(() => {
  const s = pres.addSlide();
  s.background = { color: C.white };
  L.head(s, "The domain we model", "Five data products and a read gateway");
  L.addBullets(s, [
    { text: "Order-placement-through-fulfillment, modeled small enough to stay legible and complete enough to exercise every principle.", },
    { text: "order · inventory · payment · shipping · notification — five domain services, each a data product owning its schema, its contract, and its lifecycle.", lvl: 1 },
    { text: "A GraphQL gateway composes reads across them — a read-layer convenience, not a domain data product.", lvl: 1 },
    { head: true, text: "Production framing" },
    { text: "On OpenShift this is five domain Projects plus a platform Project — not one namespace on a laptop. Each domain team owns its Project end to end.", },
    { text: "The protocols vary by fitness: REST at the edge, gRPC between services, GraphQL for composition, events for everything asynchronous.", },
  ], { x: 0.7, y: 1.95, w: PW - 1.4 });
  L.footer(s);
  s.addNotes("Introduce the worked example. Order fulfillment is deliberately mundane so the architecture stays the focus. Five domain products plus a gateway = six deployable things. Stress the distinction: five DOMAIN products (each owns data) plus one gateway (composes reads, owns nothing). The production-framing line matters: five Projects across teams, not a toy.\n\nDefinitions:\n• Project — OpenShift's unit of tenancy: a Kubernetes namespace with added governance (annotations, RBAC, lifecycle). One per domain here.\n• REST — resource-oriented HTTP APIs; used at the edge where external clients cross the trust boundary.\n• gRPC — a fast, strongly-typed RPC protocol over HTTP/2; used for synchronous service-to-service calls.\n• GraphQL — a query language that lets a client request exactly the shape it needs; the gateway uses it to compose reads across products.");
})();

contentSlide({ eyebrow: "How to read this deck", title: "Principle → pieces → code → value",
  bullets: [
    { text: "Each of the next four sections takes one principle and follows the same rhythm:", },
    { text: "The principle, recapped in a sentence — the 101 deck has the full argument.", lvl: 1 },
    { text: "The pieces that realize it on OpenShift, shown as architecture diagrams.", lvl: 1 },
    { text: "The code where code is the lesson — Python for the APIs, the few manifests worth seeing.", lvl: 1 },
    { text: "A closing value picture: the principle's payoff and the pieces that deliver it.", lvl: 1 },
    { head: true, text: "A note on scope" },
    { text: "The main narrative stays on value and leans on diagrams over YAML. We close with the anti-patterns — the conceptual and organizational ways data-mesh efforts go wrong." },
  ],
  notes: "Set the per-section rhythm: principle, pieces as diagrams, code only where it teaches, value-closer picture. Call out explicitly that we favor diagrams over YAML — most people don't want to read manifests off a slide, and the architecture is clearer as a picture. The Python API code we DO show, because seeing the implementation is valuable. The deck closes with the anti-patterns section." });

/* ====================== 01 · DOMAIN OWNERSHIP ====================== */
divider({ num: "01", title: "Domain ownership", sub: "Each domain owns its data end to end — and the platform makes that boundary real.",
  notes: "Principle 1 of 4. Throughline: ownership is only real if the boundary is enforced by the platform, not just agreed in a meeting. We see the bottleneck it removes, the monolith-to-mesh shift, then the OpenShift pieces — Projects, RBAC, quotas, a database per domain — and close with the value picture." });

contentSlide({ eyebrow: "Domain ownership", title: "The principle, in one slide",
  bullets: [
    { text: "Data is owned, end to end, by the domain team that produces it. There is no central team that owns the warehouse.", },
    { text: "The domain owns its schema, its data's lifecycle, and its evolution — and is accountable for its quality.", lvl: 1 },
    { head: true, text: "Why it matters" },
    { text: "The central data team that owns all the data but understands none of the domains is the bottleneck a mesh exists to remove.", },
    { text: "Ownership without an enforced boundary is just a wish. The platform's job is to make the boundary structural — so ownership is the default, not a convention people remember to honor.", },
  ],
  notes: "One-slide principle recap — don't re-teach the 101 argument, just land it. The line to hammer: 'ownership without an enforced boundary is just a wish.' That's the bridge to platform primitives. If someone owns data but anyone can reach in and change it, they don't really own it." });

diagramSlide({ eyebrow: "Domain ownership", title: "The bottleneck it removes",
  image: "central-team-bottleneck",
  caption: "When every domain's data flows through one central team, that team becomes the constraint on the entire organization's data velocity.",
  notes: "The problem diagram. Every domain routing through one central data team makes that team the constraint, no matter how good they are — they own all the data but understand none of the domains. Ask: how long does a schema change take in your org today? That lead time is the bottleneck this principle removes." });

diagramSlide({ eyebrow: "Domain ownership", title: "From monolith to a mesh of products",
  image: "monolith-to-mesh",
  caption: "The same refactor microservices applied to applications, applied to data: bounded contexts, each owned by the domain team that knows it best.",
  notes: "The solution shape, by analogy. Everyone lived the monolith-to-microservices refactor for applications. Data mesh is that same move for data: break the monolithic data platform into bounded data products, each owned by the domain team that knows it. The analogy does a lot of work — lean on it." });

(() => {
  const s = pres.addSlide();
  s.background = { color: C.white };
  L.head(s, "Domain ownership", "Ownership = a Project per domain");
  L.addBullets(s, [
    { text: "On OpenShift, the unit of tenancy is the Project (a namespace with added governance). Each domain gets its own Project — its own identities, permissions, and resource budget.", },
    { text: "A domain team operates inside its Project the way a microservice team operates inside its repository: it owns what's there, and nothing outside reaches in to mutate it.", },
    { head: true, text: "What the Project carries" },
    { text: "ServiceAccounts — the domain's workload identities.", lvl: 1 },
    { text: "Project-scoped RBAC — who in the domain can do what, enforced by the API server.", lvl: 1 },
    { text: "SCCs — what the domain's pods are allowed to do on the node.", lvl: 1 },
    { text: "ResourceQuota and LimitRange — the budget the domain lives within.", lvl: 1 },
  ], { x: 0.7, y: 1.95, w: PW - 1.4 });
  L.footer(s);
  s.addNotes("The OpenShift mapping. The Project IS the ownership boundary. The repository analogy lands: a domain team owns its Project like a microservice team owns its repo. Walk the four things a Project carries — identities, permissions, security context, budget — each enforces ownership in a different dimension. Next slides show the actual code.\n\nDefinitions:\n• Project — OpenShift's unit of tenancy: a Kubernetes namespace with added governance (annotations, RBAC, lifecycle). One per domain here.\n• RBAC (Role-Based Access Control) — Kubernetes' permission model; Roles grant verbs on resources, RoleBindings bind them to users/groups, enforced by the API server.\n• SCC (Security Context Constraint) — OpenShift policy controlling what a pod may do on the node (run as root, mount host paths, privileged, etc.).\n• ResourceQuota — a namespace-level cap on aggregate resource use (CPU, memory, object counts) so one domain can't starve others.\n• LimitRange — per-container default and max resource limits applied within a namespace when a pod omits its own.\n• ServiceAccount — a workload identity inside a namespace; pods run as one, and mesh mTLS and authorization policies key off it.");
})();

codeSlide({ eyebrow: "Domain ownership", title: "The domain's Project and identity",
  lang: "YAML · OpenShift",
  note: "One Project per domain — the tenancy boundary. The istio-injection label opts this domain into the mesh explicitly (selective, not cluster-wide). The ServiceAccount is the domain's workload identity, which mesh mTLS and authorization policy key off.",
  code: code(`apiVersion: project.openshift.io/v1
kind: Project
metadata:
  name: order              # one Project per domain
  labels:
    data-mesh/domain: order
    istio-injection: enabled   # opt INTO the mesh
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: order-service
  namespace: order`),
  notes: "One of the few manifests worth showing — the labels carry meaning. Point at istio-injection: enabled — we OPT this domain INTO the mesh explicitly. That's a deliberate choice justified in section 04: selective meshing, not cluster-wide. The ServiceAccount is the workload identity that mesh mTLS and authorization policies key off — remember it for section 04.\n\nDefinitions:\n• Project — OpenShift's unit of tenancy: a Kubernetes namespace with added governance (annotations, RBAC, lifecycle). One per domain here.\n• ServiceAccount — a workload identity inside a namespace; pods run as one, and mesh mTLS and authorization policies key off it.\n• mTLS (mutual TLS) — both client and server present certificates; the mesh establishes it automatically between sidecars, with no app code." });

codeSlide({ eyebrow: "Domain ownership", title: "The domain owns its access",
  lang: "YAML · OpenShift",
  note: "Project-scoped RBAC, enforced by the API server: the domain team holds full rights inside its own Project and none outside it. Ownership is not a convention people remember — it's a rule the platform applies on every request.",
  code: code(`apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: order-owner
  namespace: order
rules:
  - apiGroups: ["apps", ""]
    resources: ["deployments", "services", "configmaps"]
    verbs: ["*"]           # the domain owns its workloads
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: order-team
  namespace: order
subjects:
  - kind: Group
    name: order-domain-team
roleRef:
  kind: Role
  name: order-owner
  apiGroup: rbac.authorization.k8s.io`),
  notes: "The enforcement. RBAC is namespace-scoped — the order team has full rights inside the order Project and none outside it, enforced on every request by the API server. This is 'structural, not a convention' made concrete: ownership isn't remembered, it's a rule that runs. Don't read line by line — point at the Role verbs and the Group binding and move on.\n\nDefinitions:\n• RBAC (Role-Based Access Control) — Kubernetes' permission model; Roles grant verbs on resources, RoleBindings bind them to users/groups, enforced by the API server." });

diagramSlide({ eyebrow: "Domain ownership", title: "The domain owns its data, end to end",
  image: "17-value-domain-ownership",
  caption: "Each domain ships its data product on its own — clear owner, enforced boundary, no central team in the path.",
  notes: "SECTION VALUE-CLOSER for domain ownership — the slide that should stick. Value banner up top is the payoff; the callout pills are the reference-implementation pieces (Project, RBAC, SCCs, ResourceQuota); the red band is what breaks without it — fuzzy boundaries and ownership vacuums. Recap the whole section in 60 seconds against this picture, then move to data as a product." });

/* ====================== 02 · DATA AS A PRODUCT ====================== */
divider({ num: "02", title: "Data as a product", sub: "Discoverable, addressable, trustworthy, self-describing — held to the standard of any software product.",
  notes: "Principle 2 — the big section: contracts, catalog, protocols, APIs. Throughline: a data product is an autonomous unit, not a renamed table, and autonomy makes the rest of the mesh possible. We see the anatomy, the four protocol APIs and their Python implementations, the contracts (runtime vs discovery), the catalog — then the value-closer." });

contentSlide({ eyebrow: "Data as a product", title: "The principle, in one slide",
  bullets: [
    { text: "A data product is held to the same standard as any software product: discoverable, addressable, trustworthy, self-describing, interoperable, and secure.", },
    { text: "It is the architectural quantum of a mesh — the smallest unit you independently deploy and operate, carrying everything it needs to do its job.", lvl: 1 },
    { head: true, text: "Why it matters" },
    { text: "A 'data product' that is really just a renamed table can't serve itself, enforce its own policies, or describe itself — and federated governance has nowhere to live in it.", },
    { text: "Autonomy is what makes the rest of the mesh possible. Lose it, and you lose the governance model with it.", },
  ],
  notes: "Principle recap. Land the phrase 'architectural quantum' — the smallest independently deployable unit that carries everything it needs. The warning is the most-cited failure in the literature: calling a renamed table a 'data product.' If it can't serve, govern, and describe itself, it's not a product, and you've lost the governance model too." });

diagramSlide({ eyebrow: "Data as a product", title: "Anatomy of a data product",
  image: "data-product-anatomy",
  caption: "Input ports, output ports, the transformation between them, and the metadata and policies that make it discoverable and governed. Not a dataset — a product.",
  notes: "The anatomy. Input ports, output ports, transformation logic, metadata/policies wrapped around it — a real data product is self-contained. Contrast again with the renamed table, which has none of this. In our build, each domain service IS this picture: owns data, serves APIs, emits events, publishes a contract." });

diagramSlide({ eyebrow: "Data as a product", title: "Four protocols, four contracts — each by fitness",
  image: "17-api-implementations",
  caption: "REST at the edge, gRPC between services, GraphQL to compose, events to decouple — and the Python that implements each.",
  notes: "NEW diagram — the APIs and their implementations. Walk the four cards: REST (FastAPI, OpenAPI) at the edge; gRPC (grpcio, Protobuf) between services; GraphQL (Strawberry, SDL) to compose reads; events (aiokafka, Avro) to decouple. The middle band names the Python library for each — this audience wants to know what actually implements it. Bottom band: the gateway composing one query across REST + gRPC. Key message: not one protocol everywhere — each earns its place by fitness. Next slide shows the gateway code.\n\nDefinitions:\n• REST — resource-oriented HTTP APIs; used at the edge where external clients cross the trust boundary.\n• gRPC — a fast, strongly-typed RPC protocol over HTTP/2; used for synchronous service-to-service calls.\n• GraphQL — a query language that lets a client request exactly the shape it needs; the gateway uses it to compose reads across products.\n• OpenAPI — the contract format describing a REST API's endpoints, parameters, and responses.\n• Protobuf (Protocol Buffers) — the strongly-typed contract format for gRPC interfaces (.proto files).\n• SDL (Schema Definition Language) — GraphQL's contract format describing the available types and queries.\n• Avro — a binary serialization format with a schema; the runtime event contract, enforced by the registry at publish time." });

codeSlide({ eyebrow: "Data as a product", title: "The gateway composes — in Python",
  lang: "Python · Strawberry + clients",
  note: "The gateway exposes one GraphQL graph; its resolvers fetch each piece from the owning product over that product's existing interface — order over REST, stock over gRPC — and GraphQL assembles the shaped response. One query, multiple backends, no GraphQL added to the domain services.",
  code: code(`import strawberry

@strawberry.type
class Order:
    id: str
    total: float
    currency: str
    # nested field resolved from a DIFFERENT product:
    @strawberry.field
    async def stock(self) -> int:
        # gRPC call to inventory-service
        reply = await inventory.GetStock(sku=self.sku)
        return reply.available

@strawberry.type
class Query:
    @strawberry.field
    async def order(self, id: str) -> Order:
        # REST call to order-service
        data = await rest.get(f"/orders/{id}")
        return Order(**data)`),
  notes: "Real Python — the kind of code the audience wants. Strawberry defines the GraphQL types; resolvers call out to the owning products. Point at the two resolver bodies: order() makes a REST call to order-service; the nested stock field makes a gRPC call to inventory-service. One query, two backends, two protocols, composed by the gateway — and the domain services were NOT changed; they keep their REST and gRPC interfaces. This is gateway orchestration; true subgraph federation is the production alternative worth a mention.\n\nDefinitions:\n• GraphQL — a query language that lets a client request exactly the shape it needs; the gateway uses it to compose reads across products.\n• REST — resource-oriented HTTP APIs; used at the edge where external clients cross the trust boundary.\n• gRPC — a fast, strongly-typed RPC protocol over HTTP/2; used for synchronous service-to-service calls.\n• Strawberry — the Python GraphQL library used to implement the gateway's resolvers." });

diagramSlide({ eyebrow: "Data as a product", title: "Two jobs the registry does",
  image: "contract-flow",
  caption: "A runtime contract is load-bearing on the hot path — the event won't serialize without it. A discovery contract describes the product for humans, CI, and the catalog.",
  notes: "The conceptual heart of contracts. Two jobs, very different coupling. RUNTIME contract: the event schema — producer/consumer serialize against it, so the event won't encode/decode without it; the registry is in the hot path, which is why it can REJECT a breaking change at publish time. DISCOVERY contract: OpenAPI and SDL — source of truth for humans, CI, and the catalog, but nothing fails at runtime if absent. Don't conflate them. Most useful idea in the contracts story." });

codeSlide({ eyebrow: "Data as a product", title: "The runtime contract: a registered schema",
  lang: "Avro · schema registry",
  note: "The event schema is load-bearing: producer and consumer serialize against it, so the registry can reject an incompatible change at publish time — governance enforced computationally, before a single consumer breaks. v2 adds currency additively, with a default that keeps v1 consumers working.",
  code: code(`{
  "type": "record",
  "namespace": "com.acme.order",
  "name": "OrderPlaced",
  "version": 2,
  "fields": [
    { "name": "orderId",  "type": "string" },
    { "name": "customer", "type": "string" },
    { "name": "total",    "type": "double" },
    {
      "name": "currency",        // v2: additive, compatible
      "type": "string",
      "default": "USD"           // default keeps v1 working
    }
  ]
}
# registry compatibility: BACKWARD`),
  notes: "Show the contract because the contract IS the lesson. This is the v2 evolution we canary in section 04: currency added with a default, so backward-compatible — old consumers keep working. The registry is set to BACKWARD compatibility, so it rejects any change that would break consumers, at publish time. Federated governance made computational: the rule runs automatically. Tie forward to the canary.\n\nDefinitions:\n• Avro — a binary serialization format with a schema; the runtime event contract, enforced by the registry at publish time.\n• Apicurio Registry — the schema/contract registry; stores Avro/Protobuf/OpenAPI/SDL and enforces compatibility." });

diagramSlide({ eyebrow: "Data as a product", title: "Discovery and lineage — the catalog",
  image: "contracts-registry-catalog",
  caption: "Contracts live in one registry; the catalog ingests them — plus schemas and topics — to make products discoverable and their lineage visible.",
  notes: "The catalog story. The registry holds contract SHAPES; the catalog (OpenMetadata) answers which products exist, who owns them, who consumes whom, and lineage. The load-bearing argument: a mesh's premise is consumers finding and trusting products WITHOUT a central team. Without a usable catalog, they fall back to asking the central team — and you've rebuilt the bottleneck. So the catalog is a requirement, not an add-on. Ties back to ownership and forward to the anti-patterns.\n\nDefinitions:\n• OpenMetadata — the data catalog: which products exist, their schemas, owners, and the lineage graph across domains.\n• Lineage — the graph of which products produce and which consume each dataset/event; answers 'if this changes, what's downstream?'\n• Apicurio Registry — the schema/contract registry; stores Avro/Protobuf/OpenAPI/SDL and enforces compatibility." });

diagramSlide({ eyebrow: "Data as a product", title: "Products others can find and trust",
  image: "17-value-data-product",
  caption: "Discoverable, addressable, trustworthy, self-describing — consumers depend on products without a broker in the middle.",
  notes: "SECTION VALUE-CLOSER for data as a product. Payoff: products others can find and depend on without a broker. Pills: Deployment+Service, schema registry, OpenMetadata, CRDs. Failure mode in the red band: 'dumb' data products — renamed tables that can't serve or govern themselves. Recap against this picture, then move to the platform that provides the shared infrastructure." });

/* ====================== 03 · SELF-SERVE DATA PLATFORM ====================== */
divider({ num: "03", title: "Self-serve data platform", sub: "Shared infrastructure domains consume — so they don't each build Kafka, a registry, a catalog, or observability.",
  notes: "Principle 3. Throughline: the self-serve platform is what lets domain ownership SCALE — many domains, one platform, no central team in the critical path. Hero concept: the operator. We cover operators/OperatorHub, elasticity with KEDA (as diagrams), recoverability, then the value-closer with OpenShift specifics." });

contentSlide({ eyebrow: "Self-serve platform", title: "The principle, in one slide",
  bullets: [
    { text: "Domain teams should not each build their own streaming, database operations, registry, catalog, or observability. The platform provides these as shared infrastructure they consume by declaration.", },
    { text: "A domain that needs Kafka asks for a topic — it does not learn to operate Kafka.", lvl: 1 },
    { head: true, text: "Why it matters" },
    { text: "Without a self-serve platform, every domain reinvents the same infrastructure, badly, and ownership fragments into shadow platform teams.", },
    { text: "The self-serve layer is what lets domain ownership scale: many domains, one platform, no central team in the critical path.", },
  ],
  notes: "Principle recap. The one-liner that lands: 'a domain that needs Kafka asks for a topic — it does not learn to operate Kafka.' Without this layer, every domain reinvents infrastructure badly, and you get shadow platform teams — re-fragmented ownership. The self-serve platform lets ownership actually scale." });

diagramSlide({ eyebrow: "Self-serve platform", title: "The three planes of the platform",
  image: "platform-planes",
  caption: "The infrastructure plane, the data-product developer-experience plane, and the mesh-experience plane — what a domain consumes to ship a product without operating the substrate.",
  notes: "The platform-planes model. Three planes: raw infrastructure at the bottom, the developer-experience plane in the middle (how a domain declares a product), the mesh-experience plane (discovery, governance across products). The audience needn't memorize the names — the point is 'platform' is layered, and domains interact with the higher planes by declaration, not raw infrastructure.\n\nDefinitions:\n• Kafka — the distributed event log / streaming platform; domains publish and consume domain events on topics.\n• OpenMetadata — the data catalog: which products exist, their schemas, owners, and the lineage graph across domains." });

(() => {
  const s = pres.addSlide();
  s.background = { color: C.white };
  L.head(s, "Self-serve platform", "Operators are the self-serve mechanism");
  L.addBullets(s, [
    { text: "An operator packages the knowledge of how to run a complex system — Kafka, Postgres, a service mesh, autoscaling — into a controller that reconciles a simple declarative request into a running system.", },
    { head: true, text: "On OpenShift" },
    { text: "OperatorHub + OLM: the platform team curates which operators are available; domains install capabilities from a catalog, with lifecycle and upgrades managed.", lvl: 1 },
    { text: "GitOps (OpenShift GitOps / Argo CD): the desired state of every domain and the platform lives in Git and is continuously reconciled.", lvl: 1 },
    { text: "The integrated image registry, Routes, and Service Mesh round out the substrate — all consumed by declaration.", lvl: 1 },
    { text: "The result: a domain declares what it wants; the platform delivers the operational behavior.", color: C.ink },
  ], { x: 0.7, y: 1.95, w: PW - 1.4 });
  L.footer(s);
  s.addNotes("The hero concept: the operator. Define it clearly — an operator encodes the operational knowledge of running a complex system into a controller that turns a declarative request into a running system. On OpenShift, OperatorHub + OLM curate and lifecycle these; GitOps makes the whole mesh reproducible from Git; the integrated registry/Routes/Service Mesh complete the substrate. Payoff: the domain declares what it wants; the platform delivers the behavior. We deliberately DON'T show operator YAML — the next slides show the value as diagrams.\n\nDefinitions:\n• OperatorHub — OpenShift's catalog of installable operators; the platform team curates what's available.\n• OLM (Operator Lifecycle Manager) — installs, updates, and manages the lifecycle of operators on the cluster.\n• GitOps — desired cluster state lives in Git and is continuously reconciled onto the cluster (OpenShift GitOps is based on Argo CD).\n• Argo CD — the GitOps controller that syncs Git-declared state to the cluster.\n• CRD (Custom Resource Definition) — extends the Kubernetes API with new object types; operators define and reconcile these.\n• AMQ Streams — Red Hat's supported distribution of Strimzi: Apache Kafka run on Kubernetes via operators.\n• CloudNativePG (CNPG) — an operator that runs PostgreSQL clusters on Kubernetes as a custom resource.\n• Service Mesh (OpenShift Service Mesh / Istio) — a layer of sidecar proxies that secures, routes, and observes service-to-service traffic.");
})();

diagramSlide({ eyebrow: "Self-serve platform", title: "A trusted base for every data product",
  image: "17-trusted-supply-chain",
  caption: "Red Hat UBI + trusted content: domains build on a base they can trust and the platform can verify — security inherited, not re-sourced per team.",
  notes: "NEW slide — the secure supply chain, a strong piece of the self-serve value. The platform doesn't just give domains Kafka and Postgres; it gives them a trusted FOUNDATION to build on. Walk the chain left to right: Red Hat UBI is the base image — enterprise-maintained, freely redistributable, a legitimate production base, not a community image of unknown provenance. Trusted libraries layer language dependencies from Red Hat / verified channels with known provenance and patching. The domain's app layers on top. The result is signed and SBOM-stamped, and admission verifies it before it runs. The value, three ways: provenance you can prove; patched at the base (a CVE fix in UBI re-bases the whole fleet on rebuild); and it gives governance something to enforce (signatures and SBOMs let admission policy reject anything unverified, mesh-wide). This sits at the intersection of two principles: self-serve (shared infrastructure every domain consumes) AND federated governance (verification enforced automatically at admission).\n\nDefinitions:\n• UBI (Universal Base Image) — Red Hat's freely redistributable, enterprise-maintained container base image; a legitimate production base without a subscription.\n• SBOM (Software Bill of Materials) — a manifest of every component in an image, used to audit and verify what's inside.\n• CVE (Common Vulnerabilities and Exposures) — a publicly catalogued security vulnerability identifier.\n• Admission control — the API-server gate that validates or rejects resources as they're created; where computational governance runs." });

diagramSlide({ eyebrow: "Self-serve platform", title: "Elastic products: scale on lag, even to zero",
  image: "17-keda-lag",
  caption: "An event consumer's real demand is the backlog waiting for it — KEDA scales notification-service on Kafka lag, down to zero when idle.",
  notes: "NEW KEDA diagram — shown as a diagram, not a ScaledObject YAML, on purpose. Walk left to right: the topic's consumer lag is the signal; KEDA reads it via the Kafka scaler; it scales notification-service from zero up to ten. The 'why not CPU' callout is the teaching point — a consumer idling at 0% CPU with a 10,000-message backlog SHOULD scale up, and CPU can't see that, but lag can. Scale-to-zero makes 'elastic data product' real economics: it costs nothing while idle.\n\nDefinitions:\n• KEDA (Kubernetes Event-Driven Autoscaling) — scales workloads on external signals (queue lag, request rate), including to zero.\n• Kafka — the distributed event log / streaming platform; domains publish and consume domain events on topics." });

diagramSlide({ eyebrow: "Self-serve platform", title: "Elastic reads: the KEDA HTTP add-on",
  image: "17-keda-http",
  caption: "A read gateway's demand is request volume — the HTTP add-on scales it on traffic, and deliberately not on the canaried service.",
  notes: "Second KEDA diagram, also a picture. The gateway scales on HTTP request volume via the add-on's interceptor. The DESIGN point is the red band: HTTP scaling goes on the gateway, NOT order-service — because order-service carries the canary, and HTTP-scaling a service whose traffic is split by weight would have the two mechanisms fight over the same pods. 'Fit the mechanism to the workload.' The 'unknown at rest' note pre-empts a question: a scaled-to-zero workload reports unknown until the first request — expected.\n\nDefinitions:\n• KEDA (Kubernetes Event-Driven Autoscaling) — scales workloads on external signals (queue lag, request rate), including to zero.\n• Canary — a progressive rollout that shifts a fraction of live traffic to a new version, increasing it as confidence grows." });

contentSlide({ eyebrow: "Self-serve platform", title: "Resilience: recoverability as a platform property",
  bullets: [
    { text: "The cloud-native answer to failure isn't 'prevent it' — it's 'make recovery cheap and automatic.' A mesh inherits this from the platform.", },
    { text: "A crashed pod is restarted; a failed rollout is rolled back; a node's workloads are rescheduled; declarative state continuously reconciles toward what you asked for.", lvl: 1 },
    { head: true, text: "Design products toward recoverability" },
    { text: "Don't hold critical state only in memory; come back to a known-good state after a crash; let the operator recover the systems it manages; let a downed consumer catch up on the backlog it missed.", },
    { text: "A product deployed this way is recoverable by construction — and that resilience is something the domain gets from the platform, not something it builds.", color: C.ink },
  ],
  notes: "Resilience as the other half of the platform's value. Cloud-native doesn't prevent failure — it makes recovery cheap and automatic, and a mesh inherits that. List the reconciliation behaviors quickly. Then design guidance: build TOWARD recoverability — no critical in-memory-only state, known-good recovery, let operators recover what they manage, let consumers catch up. Payoff: recoverable by construction, from the platform." });

diagramSlide({ eyebrow: "Self-serve platform", title: "Infrastructure domains consume, not operate",
  image: "17-value-self-serve",
  caption: "Streaming, databases, scaling, and the mesh — declared, not operated. One platform team's work, leveraged by every domain.",
  notes: "SECTION VALUE-CLOSER for self-serve platform. Payoff: leverage — one platform team's work consumed by every domain — plus consistency and focus. Pills: OperatorHub/OLM, AMQ Streams/CNPG, KEDA, GitOps. Failure mode: every domain reinventing infrastructure, shadow platform teams. This is where the OpenShift value is most concrete: OperatorHub curates capabilities, GitOps makes it reproducible, the integrated substrate is there to consume, not assemble. Then to governance." });

/* ====================== 04 · FEDERATED COMPUTATIONAL GOVERNANCE ====================== */
divider({ num: "04", title: "Federated computational governance", sub: "Standards enforced computationally by the platform — not by meetings and policy documents.",
  notes: "Principle 4 — the one that holds the others together. Throughline: encode the few global rules so the platform RUNS them, and ownership stays decentralized while standards hold. We cover the governance model, the canary (contract evolution + selective-meshing decision), the mesh and mTLS as a diagram, admission policy framing, and observability as governance — then the value-closer." });

contentSlide({ eyebrow: "Federated governance", title: "The principle, in one slide",
  bullets: [
    { text: "A small set of global rules keeps independent products interoperable, and the platform enforces them automatically, at the boundary — not a review board after the fact.", },
    { text: "Federated: domains decide their own local rules; the platform enforces the few global ones that let products join up.", lvl: 1 },
    { head: true, text: "Why it matters" },
    { text: "Bolt governance on from outside and it never fits; over-correct into an approval bureaucracy and you've rebuilt the central bottleneck.", },
    { text: "Computational governance is the resolution: encode the global rules so the platform runs them, and ownership stays decentralized while standards hold.", },
  ],
  notes: "Principle recap. The tension: governance fails in two opposite directions — bolted on from outside (never fits) or over-corrected into an approval bureaucracy (the bottleneck returns). Computational governance resolves it: encode the few global rules, let the platform enforce them automatically. 'Federated' = domains own local rules, platform enforces global ones. This is the principle that lets all the others coexist." });

diagramSlide({ eyebrow: "Federated governance", title: "Global rules, local autonomy",
  image: "federated-governance-model",
  caption: "A few global rules the platform enforces; the rest left to domains. Where that line falls is the central governance design decision.",
  notes: "The governance-model diagram. The design question every mesh faces: which rules are GLOBAL (so products interoperate — shared identifiers, contract formats, lineage conventions) versus LOCAL (left to domains). Wrong toward global and you have a bottleneck; wrong toward local and nothing joins up. The platform enforces the global few automatically. Judgment, not a formula — but the diagram frames the decision." });

diagramSlide({ eyebrow: "Federated governance", title: "The service mesh: secure by default, shiftable on demand",
  image: "17-service-mesh",
  caption: "Sidecars beside every product establish mTLS automatically and let the platform shift traffic by weight — both without application code.",
  notes: "NEW service-mesh diagram — replaces PeerAuthentication YAML, because the mesh's shape is far clearer as a picture. Walk it: every product has a sidecar (Envoy) beside the app container; sidecar-to-sidecar traffic is mutual TLS, automatic, no app code; istiod is the control plane issuing identities and pushing routing/policy. Bottom band: the canary — weights shift 90/10 → 50/50 → 0/100, mesh splits live traffic, no client change. Two capabilities, one mechanism: security and traffic management as platform properties. The one piece of mesh code worth seeing — the canary weights — is next.\n\nDefinitions:\n• Istio — the service mesh project underlying OpenShift Service Mesh; injects sidecar proxies and controls traffic/security.\n• Service Mesh (OpenShift Service Mesh / Istio) — a layer of sidecar proxies that secures, routes, and observes service-to-service traffic.\n• Sidecar — a proxy container (Envoy) injected next to your app container; carries the mesh's traffic, security, and telemetry.\n• Envoy — the high-performance proxy used as the mesh sidecar/data plane.\n• istiod — the Istio control plane; issues identities/certificates and pushes routing and policy to every sidecar.\n• mTLS (mutual TLS) — both client and server present certificates; the mesh establishes it automatically between sidecars, with no app code.\n• Canary — a progressive rollout that shifts a fraction of live traffic to a new version, increasing it as confidence grows." });

codeSlide({ eyebrow: "Federated governance", title: "Canary a contract — the one mesh manifest worth seeing",
  lang: "YAML · OpenShift Service Mesh",
  note: "The interesting thing to canary in a mesh isn't a new binary — it's a new version of the contract. v2 adds the currency field from section 02; the mesh shifts live traffic by weight. Shifting the canary is a one-line weight change: 90/10 → 50/50 → 0/100.",
  code: code(`apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata: { name: order-service, namespace: order }
spec:
  hosts: [order-service]
  http:
    - route:
        - destination: { host: order-service, subset: v1 }
          weight: 90
        - destination: { host: order-service, subset: v2 }
          weight: 10        # move 90/10 → 50/50 → 0/100`),
  notes: "We show this ONE manifest because the weights ARE the lesson — everything else about the mesh was a diagram. Connect to section 02: v2 is the contract that added the currency field. The canary isn't canarying a new binary, it's canarying a CONTRACT CHANGE — the data-mesh-specific insight. Shifting the rollout is changing two numbers and re-applying; rolling back is the same in reverse. In the reference implementation: 90/10 produced ~95/5, 50/50 produced ~46/54 — both in band.\n\nDefinitions:\n• VirtualService — Istio's routing rule; here it splits traffic between service versions by weight (the canary).\n• DestinationRule — Istio's object defining service subsets (e.g. v1/v2) that a VirtualService routes to.\n• Canary — a progressive rollout that shifts a fraction of live traffic to a new version, increasing it as confidence grows.\n• Service Mesh (OpenShift Service Mesh / Istio) — a layer of sidecar proxies that secures, routes, and observes service-to-service traffic.\n• Istio — the service mesh project underlying OpenShift Service Mesh; injects sidecar proxies and controls traffic/security." });

contentSlide({ eyebrow: "Federated governance", title: "Mesh selectively — a design decision",
  bullets: [
    { text: "The convenient default is namespace-wide sidecar injection: one label, everything meshed. The better default for a real platform is to opt specific workloads into the mesh.", },
    { head: true, text: "Three kinds of workload don't belong in the mesh" },
    { text: "Batch jobs meant to finish — a sidecar that never exits keeps the job from ever completing.", lvl: 1 },
    { text: "Operator-managed infrastructure with its own TLS — a second TLS layer collides with the database's own.", lvl: 1 },
    { text: "Anything where the sidecar's cost buys nothing — resource overhead and a control-plane dependency for no benefit.", lvl: 1 },
    { text: "Selective injection also contains blast radius: only workloads that need the mesh depend on its control plane being healthy.", color: C.ink },
  ],
  notes: "An important DESIGN DECISION, framed as value not war-story. The convenient default — namespace-wide injection — is wrong for a platform that holds more than just services. Opt workloads INTO the mesh instead. Three categories that don't belong: finish-and-terminate jobs (sidecar never exits, job hangs), operator-managed infra with its own TLS (collision), anything where the sidecar buys nothing. Plus the systemic argument: selective injection contains blast radius. State it as a principle here — the reasoning matters more than the war stories.\n\nDefinitions:\n• Sidecar — a proxy container (Envoy) injected next to your app container; carries the mesh's traffic, security, and telemetry.\n• Istio — the service mesh project underlying OpenShift Service Mesh; injects sidecar proxies and controls traffic/security.\n• Admission control — the API-server gate that validates or rejects resources as they're created; where computational governance runs." });

diagramSlide({ eyebrow: "Federated governance", title: "Observability — the mesh emits, the platform collects",
  image: "17-observability-stack",
  caption: "Sidecars emit metrics and traces; Prometheus, Tempo, and Kiali collect them — most of it without touching application code.",
  notes: "NEW observability diagram — replaces config YAML. Walk the flow: products with sidecars emit metrics and traces over OTLP; the OTEL Collector fans out to Prometheus (metrics), Tempo (traces), Kiali (live topology); Grafana unifies into dashboards. Headline: because the sidecars already measure the traffic they carry, most of this is observability you get FROM THE PLATFORM, not code you write. That 'for free from the mesh' property is the self-serve principle showing up inside governance.\n\nDefinitions:\n• Prometheus — the metrics database; scrapes request rates, errors, latencies, and consumer lag (much of it emitted by the mesh sidecars).\n• Tempo — the distributed-tracing backend; stores spans so a request's path across products can be reconstructed.\n• Kiali — the mesh console showing the live service topology and traffic, including the canary split.\n• Grafana — the dashboard layer over metrics and traces.\n• OTLP (OpenTelemetry Protocol) — the wire format workloads and sidecars use to export metrics and traces to the collector.\n• Sidecar — a proxy container (Envoy) injected next to your app container; carries the mesh's traffic, security, and telemetry." });

diagramSlide({ eyebrow: "Federated governance", title: "Three signals, correlated across a domain",
  image: "17-three-signals",
  caption: "Metrics say something is wrong, traces say where, logs say what — tied together by a shared trace id across products.",
  notes: "NEW three-signals diagram — explains WHY you need all three, correlated. Top: one request becomes one trace whose spans cross three products. The three columns: metrics answer 'is it slow/failing and is the platform reacting,' traces answer 'WHERE in the path,' logs answer 'exactly WHAT happened.' The red correlation band is the punchline: the same trace id on all three, so you jump from a latency spike to the slow trace to the exact log line — across the whole domain. Why it matters in a mesh: the interesting behavior lives BETWEEN products, where no single product's logs can see it. The slide that makes observability click.\n\nDefinitions:\n• OpenTelemetry (OTel) — the vendor-neutral standard and SDKs for emitting traces and metrics from application code." });

codeSlide({ eyebrow: "Federated governance", title: "A trace span across products — in Python",
  lang: "Python · OpenTelemetry",
  note: "Instrument the gateway and one GraphQL query becomes a connected tree of spans — an HTTP server span, a REST client span to order-service, a gRPC client span to inventory-service — stitched into one distributed trace. One well-chosen instrumentation point illuminates the whole read path.",
  code: code(`from opentelemetry import trace
tracer = trace.get_tracer("graphql-gateway")

async def resolve_order(info, order_id: str):
    with tracer.start_as_current_span("resolve.order") as span:
        span.set_attribute("order.id", order_id)

        # REST client span → order-service
        order = await rest.get(f"/orders/{order_id}")

        # gRPC client span → inventory-service
        stock = await inventory.GetStock(sku=order["sku"])

        return compose(order, stock)`),
  notes: "Python again — the audience wants to see how tracing attaches. The gateway is the entry point for the federated read path, so instrumenting it yields the most instructive trace. One query produces an HTTP server span plus a REST client span plus a gRPC client span — the composition from section 02, now visible as a span tree in Tempo. Instrument-the-entry-point-first is the same incremental discipline as the rest of the build. This produces the trace in the previous diagram.\n\nDefinitions:\n• OpenTelemetry (OTel) — the vendor-neutral standard and SDKs for emitting traces/metrics; here, used to instrument the gateway.\n• GraphQL — a query language that lets a client request exactly the shape it needs; the gateway uses it to compose reads across products.\n• REST — resource-oriented HTTP APIs; used at the edge where external clients cross the trust boundary.\n• gRPC — a fast, strongly-typed RPC protocol over HTTP/2; used for synchronous service-to-service calls.\n• Tempo — the distributed-tracing backend; stores spans so a request's path across products can be reconstructed." });

diagramSlide({ eyebrow: "Federated governance", title: "Standards that hold, ownership that stays put",
  image: "17-value-governance",
  caption: "Global rules enforced by the platform automatically — decentralization preserved, interoperability guaranteed.",
  notes: "SECTION VALUE-CLOSER for federated governance. Payoff: standards hold WITHOUT re-centralizing — the platform enforces the global rules automatically, so ownership stays decentralized. Pills: Service Mesh mTLS, progressive delivery, admission policy, the observability stack. Failure mode: governance bolted on from outside, or re-centralized into an approval bottleneck — the mesh's own anti-pattern. This closes the four principles; next we assemble the whole picture.\n\nDefinitions:\n• mTLS (mutual TLS) — both client and server present certificates; the mesh establishes it automatically between sidecars, with no app code.\n• Admission control — the API-server gate that validates or rejects resources as they're created; where computational governance runs.\n• Prometheus — the metrics database; scrapes request rates, errors, latencies, and consumer lag (much of it emitted by the mesh sidecars).\n• Tempo — the distributed-tracing backend; stores spans so a request's path across products can be reconstructed.\n• Kiali — the mesh console showing the live service topology and traffic, including the canary split." });

/* ====================== 05 · THE WHOLE PICTURE ====================== */
divider({ num: "05", title: "The whole picture", sub: "The four principles, realized — and what the assembled platform lets you see it do.",
  notes: "Synthesis section. Return to the reference architecture assembled, show the principles-to-pieces closer, describe what you can SEE it do (the acceptance vision), give adoption guidance, the honest 'when not to,' and close. Bring the energy up — this is where it lands." });

diagramSlide({ eyebrow: "The whole picture", title: "The reference architecture, assembled",
  image: "reference-data-mesh-architecture",
  caption: "Every piece in its place: domain products owning their data, the platform planes beneath, governance and observability spanning the whole — the mesh, complete.",
  notes: "Callback to the centerpiece from section 0 — now the audience has built every box. Walk it once more, quickly, naming the principle each layer serves: domain products (ownership + product), the platform planes (self-serve), the mesh and observability spanning everything (governance). The promise from the start is kept: you recognize all of it. The 'it all fits' moment." });

diagramSlide({ eyebrow: "The whole picture", title: "The four principles, realized on OpenShift",
  image: "17-principles-to-pieces",
  caption: "One picture to leave with: each principle, the pieces that deliver it, on the OpenShift substrate that gives all four a home.",
  notes: "THE closing picture — replaces the old table, because a picture sticks and a table doesn't. Four color-coded columns, one per principle, each stacking its implementing pieces, all on the black OpenShift substrate bar. If the audience remembers one slide, make it this one. Read down each column, then land on the base: OpenShift is where all four principles find a home. The takeaway image.\n\nDefinitions:\n• Project — OpenShift's unit of tenancy: a Kubernetes namespace with added governance (annotations, RBAC, lifecycle). One per domain here.\n• RBAC (Role-Based Access Control) — Kubernetes' permission model; Roles grant verbs on resources, RoleBindings bind them to users/groups, enforced by the API server.\n• SCC (Security Context Constraint) — OpenShift policy controlling what a pod may do on the node (run as root, mount host paths, privileged, etc.).\n• ResourceQuota — a namespace-level cap on aggregate resource use (CPU, memory, object counts) so one domain can't starve others.\n• OperatorHub — OpenShift's catalog of installable operators; the platform team curates what's available.\n• OLM (Operator Lifecycle Manager) — installs, updates, and manages the lifecycle of operators on the cluster.\n• GitOps — desired cluster state lives in Git and is continuously reconciled onto the cluster (OpenShift GitOps is based on Argo CD).\n• KEDA (Kubernetes Event-Driven Autoscaling) — scales workloads on external signals (queue lag, request rate), including to zero.\n• mTLS (mutual TLS) — both client and server present certificates; the mesh establishes it automatically between sidecars, with no app code.\n• Canary — a progressive rollout that shifts a fraction of live traffic to a new version, increasing it as confidence grows.\n• Admission control — the API-server gate that validates or rejects resources as they're created; where computational governance runs.\n• Prometheus — the metrics database; scrapes request rates, errors, latencies, and consumer lag (much of it emitted by the mesh sidecars).\n• Tempo — the distributed-tracing backend; stores spans so a request's path across products can be reconstructed.\n• Kiali — the mesh console showing the live service topology and traffic, including the canary split.\n• OpenMetadata — the data catalog: which products exist, their schemas, owners, and the lineage graph across domains." });

contentSlide({ eyebrow: "The whole picture", title: "What you can see it do",
  bullets: [
    { text: "Not just that the mesh runs — that you can watch it run. This is the acceptance bar the platform is built toward:", },
    { text: "A single GraphQL query appears as a trace whose spans cross three products and three protocols.", lvl: 1 },
    { text: "Metrics show the gateway's load and the autoscaler waking replicas to meet it.", lvl: 1 },
    { text: "A contract rolls out version by version as live traffic shifts across the canary.", lvl: 1 },
    { text: "The catalog shows the lineage of which products feed which.", lvl: 1 },
    { text: "Kiali shows the live topology, canary split and all.", lvl: 1 },
    { text: "These are the instruments through which you understand a system too distributed for any single vantage point.", color: C.ink },
  ],
  notes: "The acceptance vision — what a live demo would show. If you're doing a live demo (the walkthrough), this slide is your script: the trace across products, the autoscaler reacting, the canary shifting, the lineage graph, the Kiali topology. Even without a live demo, it paints 'done looks like this.' Closing line is the observability thesis: instruments for a system too distributed to see from any one place.\n\nDefinitions:\n• GraphQL — a query language that lets a client request exactly the shape it needs; the gateway uses it to compose reads across products.\n• Kiali — the mesh console showing the live service topology and traffic, including the canary split.\n• Canary — a progressive rollout that shifts a fraction of live traffic to a new version, increasing it as confidence grows.\n• Lineage — the graph of which products produce and which consume each dataset/event; answers 'if this changes, what's downstream?'" });

contentSlide({ eyebrow: "The whole picture", title: "Adoption: start small",
  bullets: [
    { text: "You don't adopt a mesh by building all of this at once. The principles are independent enough to land incrementally.", },
    { text: "Start with one domain and one product — give it a Project, a contract, and an owner.", lvl: 1 },
    { text: "Add the self-serve platform pieces as the second and third products need them, not before.", lvl: 1 },
    { text: "Introduce computational governance once you have products to govern — the registry before the catalog, mTLS before policy.", lvl: 1 },
    { head: true, text: "Let the architecture correct against reality" },
    { text: "Each piece is verifiable on its own. Stand one up, confirm it, then add the next — the same incremental discipline the reference implementation followed.", },
  ],
  notes: "Practical adoption advice — the natural next question is 'where do I start?' Answer: not all at once. One domain, one product, with a Project, a contract, and an owner. Add platform pieces as products need them. Introduce governance once there are products to govern. Meta-point: each piece is independently verifiable, so build incrementally and let reality correct the design — exactly how the reference implementation was built." });

/* ====================== 06 · ANTI-PATTERNS ====================== */
divider({ num: "06", title: "Anti-patterns", sub: "How data-mesh efforts go wrong — the conceptual and organizational failure modes, so you can spot them early.",
  notes: "Final section before we close. Everything so far was what to build and how. This section is what goes WRONG — and deliberately NOT the implementation potholes (those are operational and a different kind of lesson); these are the CONCEPTUAL and ORGANIZATIONAL failure modes that show up again and again. The framing to open with: a data mesh is a socio-technical system, and the literature is nearly unanimous that these efforts fail for organizational reasons far more than technical ones. Most of these are invisible at the architecture-diagram level and only become obvious months in, once they've calcified. Each anti-pattern: the trap, the tell, and the fix." });

contentSlide({ eyebrow: "Anti-patterns", title: "The architecture diagram is the easy part",
  bullets: [
    { text: "A data mesh is a socio-technical system. The technical pieces — registry, catalog, streams, autoscaling — are the concrete, runnable part this deck spent most of its time on.", },
    { text: "But the literature is nearly unanimous: data-mesh efforts fail for organizational reasons far more often than technical ones.", color: C.ink },
    { head: true, text: "Why these are worth knowing before you start" },
    { text: "Most are invisible on the architecture diagram. They only become obvious months in — once they've calcified into how teams work.", },
    { text: "Each of the next slides: the trap, the tell that reveals it, and the fix the literature points to.", },
  ],
  notes: "Set up the section. The key reframe for a technical audience that just sat through 40 slides of architecture: the diagram was the easy part. The parts that aren't on the diagram — who owns what, how governance is enforced, whether the loop is closed, whether the org needed a mesh at all — are where efforts actually succeed or fail. These anti-patterns are drawn from practitioners who've watched many of these efforts up close. They're stated generally; I'll note where each touched our own build." });

(() => {
  // each anti-pattern: trap (what it is) + tell (the symptom) + fix
  const items = [
    { h: "\u201cThe tool will solve it\u201d",
      trap: "Treating data mesh as something you buy or install — adopt a catalog, relabel the lake's tables as \u201cdata products,\u201d declare victory. But the principles are about how teams work, not which software runs.",
      tell: "A project plan that's entirely a tooling rollout, with no mention of team boundaries, ownership, or incentives.",
      fix: "Change the operating model first; let tools support the principles rather than substitute for them.",
      n: "The most common trap, and practitioners put it first. A data mesh is an operating-model change; no tool delivers that on its own. The tell is a plan that's all tooling and no team-structure change — if the only thing changing is the software, you end up with the old centralized model plus a new dashboard. In our build, every component (Apicurio, OpenMetadata, KEDA, Istio) is deliberately a substrate the domains build on, not a turnkey mesh." },
    { h: "Centralization wearing a new name",
      trap: "Recreating the central-team bottleneck under new vocabulary: a \u201cplatform team\u201d that's still the only group that can ship a product; governance as a manual approval gate; or domains spinning up shadow data teams.",
      tell: "Decisions still funnel through one team — for control, for \u201cconsistency,\u201d for governance — and the old lead times quietly return.",
      fix: "Push real ownership and the ability to ship to the domains; make governance automated and policy-driven, not approval-driven.",
      n: "Data mesh exists to break the single-central-team bottleneck; the failure is rebuilding it under new words. Three shapes: the central team stays the proxy for every domain; governance re-centralizes as a review board; or domains build shadow data teams and you get silos again. Decentralization is the whole point — anything that funnels decisions back through one team reintroduces the original problem. In our build, the namespace-and-operator model gives each domain a place to own its slice with no central team in the loop." },
    { h: "Data products that are \u201cdumb\u201d",
      trap: "Stripping a data product down to a renamed table or a catalog row. A real product serves its data, governs it, describes itself, and is discoverable; a dumb one is a static dataset with a label.",
      tell: "A \u201cdata product\u201d you can't deploy, version, or call — you can only query the table it points at.",
      fix: "Give every product ports, a versioned contract, an owner, and a lifecycle. Autonomy is what lets governance live inside it.",
      n: "The failure the principle's own author warns about most sharply. Lose product autonomy and you lose the governance model with it — because there's nowhere to embed governance in a renamed table, federated computational governance gets dropped too. The downgrade cascades. In our build, each service IS its data product: owns its schema, publishes a versioned contract, emits its own events, exposes its own API." },
    { h: "Governance as an afterthought — or as bureaucracy",
      trap: "Governance fails in two opposite directions: bolted on from outside (it never fits — quality and access become things done TO a product), or over-corrected into a heavyweight approval bureaucracy (centralization again).",
      tell: "Either a free-for-all where nothing joins up, or a bottleneck where nothing ships.",
      fix: "Federated computational governance: a small set of global rules the platform enforces automatically, embedded in each product — not administered by a committee.",
      n: "The interesting design question for any mesh is which rules are GLOBAL (so products interoperate — shared identifiers, contract formats, lineage conventions) versus left to domains. Get that line wrong either way and you get the free-for-all or the bottleneck. In our build, contracts live in a registry and lineage is recorded in the catalog automatically as part of deploying, not as a separate review step." },
    { h: "No clear owner, or fuzzy domain boundaries",
      trap: "Two related failures: the ownership vacuum (a dataset nobody is responsible for, so quality drifts and trust erodes), and fuzzy boundaries (the same concept modeled three ways by three teams).",
      tell: "Consumers get conflicting versions of nominally the same data, and changes ripple across services that should have been independent.",
      fix: "Bounded contexts — the same discipline that makes microservices work. Map the domains, name an owner per product, revisit boundaries as the org changes.",
      n: "A mesh is only as good as the clarity of who owns what. Both failures come down to bounded contexts. Without clear, agreed domain boundaries and an explicit owner per product, the mesh degrades into the distributed mess the principles were meant to prevent. The remedy is unglamorous: actually map the domains and write down who owns each product. In our build, each domain is a service with a single clear responsibility and an owner by construction." },
    { h: "The open loop — no feedback",
      trap: "Static analytical products built downstream from a lake, disconnected from the operational systems that produce the data and from the consumers who use them. No operational-to-analytical loop, no consumer-feedback loop.",
      tell: "A data product nobody monitors for use and nobody updates in response to how it's consumed — published once, then frozen.",
      fix: "Close the loop by domain: react to operational events as they happen, and track whether products are actually useful to their consumers.",
      n: "Data mesh is meant to close the loop between operational systems and analytical uses, organized by domain. The degraded version is an open loop — products go stale, the lead time between an app change and its analytical impact never shrinks, and the mesh delivers little more than the warehouse it replaced. In our build, the async spine means analytical consumers react to operational events as they happen rather than to a nightly extract." },
    { h: "Hype-driven and wrong-fit adoption",
      trap: "Adopting a mesh because it's fashionable. It earns its complexity in large orgs with many domains, many consumers, and the maturity to operate products and standards across teams — for a small org, the overhead can cost more than the bottleneck it removes.",
      tell: "Chasing more data products as an end in itself; months of planning the perfect mesh instead of shipping one real product; adopting the whole paradigm when one principle would do.",
      fix: "Weigh data size, organizational complexity, existing tooling, and culture. Be willing to conclude a full mesh — or only some of its principles — is the right fit.",
      n: "Less about HOW you build a mesh and more about WHETHER you should. This is the honest slide — and it builds credibility. A mesh is not for every organization. Sometimes a single principle, usually the self-serve platform, delivers most of the value without the full paradigm. Telling people when NOT to do this makes them trust you on when to. In our build, the capstone is deliberately a learning implementation — sized to teach the shape, not to argue everyone should run a mesh in production." },
  ];
  items.forEach((it) => {
    const s = pres.addSlide();
    s.background = { color: C.white };
    L.head(s, "Anti-patterns", it.h, { titleH: 1.0 });
    L.addBullets(s, [
      { head: true, text: "The trap" }, { text: it.trap },
      { head: true, text: "The tell" }, { text: it.tell },
      { head: true, text: "The fix" }, { text: it.fix, color: C.ink },
    ], { x: 0.7, y: 1.95, w: PW - 1.4, fontSize: 15 });
    L.footer(s);
    s.addNotes(it.n);
  });
})();

contentSlide({ eyebrow: "Anti-patterns", title: "Recognizing them early",
  bullets: [
    { text: "None of these are exotic. They're the predictable result of taking a paradigm about ownership, autonomy, and feedback — and implementing only its visible technical surface.", },
    { text: "The recurring lesson across everyone who's written about failed efforts is the same:", color: C.ink },
    { text: "The architecture diagram is the easy part. Who owns what, how governance is enforced, whether the loop is closed, whether the organization needed a mesh at all — the parts that aren't on the diagram are where efforts actually succeed or fail.", lvl: 1 },
  ],
  notes: "Section close. Tie the seven together: each is what happens when you implement the technical surface of a paradigm that's fundamentally about ownership, autonomy, and feedback — and skip the rest. The single sentence to leave them with: the architecture diagram is the easy part. That's a strong setup for the conclusion, which reframes the whole deck as having built exactly the parts that ARE on the diagram, while naming what isn't. Then go to the closing slide." });

(() => {
  const s = pres.addSlide();
  s.addImage({ path: L.ILLUS, x: 0, y: 0, w: PW, h: PH, sizing: { type: "cover", w: PW, h: PH } });
  const rx = PW * 0.42, rw = PW - rx - 0.7;
  s.addText("The mesh is the network of products —", { x: rx, y: 2.5, w: rw, h: 0.9, fontSize: 28, color: "FFFFFF", fontFace: F.head, bold: true, valign: "top", margin: 0 });
  s.addText("plus the platform and standards that let them interoperate.", { x: rx, y: 3.35, w: rw, h: 1.2, fontSize: 28, color: "FFD9D9", fontFace: F.head, bold: true, valign: "top", margin: 0 });
  s.addText("OpenShift is where all four principles find a home.", { x: rx, y: 4.85, w: rw, h: 0.6, fontSize: 15, color: "FFFFFF", fontFace: F.body, italic: true, valign: "top", margin: 0 });
  const lw = 1.25, lh = lw / L.LOGO_AR;
  s.addImage({ path: L.LOGO_LIGHT, x: PW - 0.6 - lw, y: PH - 0.3 - lh, w: lw, h: lh });
  L.pageNumOnly(s, { dark: true });
  s.addNotes("Closing. The one-sentence definition that ties the talk together: a mesh is the network of products PLUS the platform and standards that let them interoperate — every word of which we built today. And, per the anti-patterns we just covered, the platform and standards are exactly the parts teams skip. End on OpenShift as the home for all four principles. Open for questions.");
})();

/* ============================ WRITE ============================ */
pres.writeFile({ fileName: "Data_Mesh_on_OpenShift.pptx" }).then((f) => console.log("WROTE", f));
