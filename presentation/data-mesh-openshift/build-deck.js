// Build the Data Mesh on OpenShift implementation deck.
const L = require("./deck-lib.js");
const { pres, C, F, PW, PH, titleSlide, divider, contentSlide, diagramSlide, codeSlide } = L;

// helper for code text as a single string (mono panel)
const code = (s) => s.replace(/\t/g, "  ");

/* ============================ TITLE ============================ */
titleSlide({
  title: "Data Mesh on OpenShift",
  subtitle: "A reference implementation — the four principles, realized in pieces you can deploy, secure, scale, and observe.",
  author: "Robert Sedor · Chief Architect",
});

(() => {
  const s = pres.addSlide();
  s.background = { color: C.white };
  L.head(s, "Where the 101 deck ended", "From the idea to the running platform");
  L.addBullets(s, [
    { text: "The Data Mesh 101 deck made the case: centralized data platforms stall, and the answer is to decentralize ownership — domains own their data as products on a shared, self-serve platform under federated, automated governance.", },
    { text: "That deck ended by pointing at implementation. This deck is the implementation.", color: C.ink },
    { head: true, text: "What this deck does" },
    { text: "Takes each of the four principles and shows the concrete OpenShift pieces that realize it — with the code and the architecture, not just the diagram." },
    { text: "Frames every piece by the value it delivers: why it earns its place in a production data mesh." },
    { text: "Keeps the operational war-stories out of the main story — they live in Appendix A, so the through-line stays on value." },
  ], { x: 0.7, y: 1.95, w: PW - 1.4 });
  L.footer(s);
})();

/* ====================== 00 · FROM PRINCIPLES TO PLATFORM ====================== */
divider({ num: "00", title: "From principles to platform", sub: "The four principles, the reference architecture, and how to read what follows." });

diagramSlide({ eyebrow: "The four principles", title: "Four principles — and how they map in practice",
  image: "four-principles",
  caption: "The tools are expressions of the pattern, not the pattern itself. Each principle below maps to concrete platform pieces." });

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
})();

diagramSlide({ eyebrow: "Reference architecture", title: "The data mesh, at a glance",
  image: "reference-data-mesh-architecture",
  caption: "The centerpiece: domain data products, the platform planes beneath them, and the governance and observability that span them. We assemble this piece by piece." });

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
})();

contentSlide({ eyebrow: "How to read this deck", title: "Principle → pieces → code → value",
  bullets: [
    { text: "Each of the next four sections takes one principle and follows the same rhythm:", },
    { text: "The principle, recapped in a sentence — the 101 deck has the full argument.", lvl: 1 },
    { text: "The pieces that realize it on OpenShift, with the architecture diagram.", lvl: 1 },
    { text: "The code: real, production-shaped manifests and definitions — not laptop specifics.", lvl: 1 },
    { text: "The value: what the principle buys you, and what breaks without it.", lvl: 1 },
    { head: true, text: "A note on scope" },
    { text: "The main narrative stays on value. The operational gotchas — the sharp edges you hit running this — are gathered in Appendix A, so they inform without derailing." },
  ] });

/* ====================== 01 · DOMAIN OWNERSHIP ====================== */
divider({ num: "01", title: "Domain ownership", sub: "Each domain owns its data end to end — and the platform makes that boundary real." });

contentSlide({ eyebrow: "Domain ownership", title: "The principle, in one slide",
  bullets: [
    { text: "Data is owned, end to end, by the domain team that produces it. There is no central team that owns the warehouse.", },
    { text: "The domain owns its schema, its data's lifecycle, and its evolution — and is accountable for its quality.", lvl: 1 },
    { head: true, text: "Why it matters" },
    { text: "The central data team that owns all the data but understands none of the domains is the bottleneck a mesh exists to remove.", },
    { text: "Ownership without an enforced boundary is just a wish. The platform's job is to make the boundary structural — so ownership is the default, not a convention people remember to honor.", },
  ] });

diagramSlide({ eyebrow: "Domain ownership", title: "The bottleneck it removes",
  image: "central-team-bottleneck",
  caption: "When every domain's data flows through one central team, that team becomes the constraint on the entire organization's data velocity." });

diagramSlide({ eyebrow: "Domain ownership", title: "From monolith to a mesh of products",
  image: "monolith-to-mesh",
  caption: "The same refactor microservices applied to applications, applied to data: bounded contexts, each owned by the domain team that knows it best." });

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
});

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
});

codeSlide({ eyebrow: "Domain ownership", title: "The domain lives within its budget",
  lang: "YAML · OpenShift",
  note: "A quota makes the ownership boundary enforceable in resource terms: a domain uses what it owns and no more, so one domain can't starve another. A companion LimitRange sets per-container defaults. The platform team sets the envelope; the domain governs itself inside it.",
  code: code(`apiVersion: v1
kind: ResourceQuota
metadata:
  name: order-quota
  namespace: order
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
    persistentvolumeclaims: "10"
    services.loadbalancers: "2"
    count/deployments.apps: "20"`),
});

codeSlide({ eyebrow: "Domain ownership", title: "A data product is a Deployment + Service",
  lang: "YAML · OpenShift",
  note: "The product's runtime and its stable address — the two primitives that make a data product a first-class, deployable thing rather than a row in a catalog. A Route (not shown) publishes it outside the cluster when it serves external consumers.",
  code: code(`apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: order
  labels:
    app: order-service
    data-mesh/product: orders
spec:
  replicas: 2
  selector:
    matchLabels: { app: order-service }
  template:
    metadata:
      labels: { app: order-service, version: v1 }
    spec:
      serviceAccountName: order-service
      containers:
        - name: order-service
          image: .../order/order-service:1.4.0
          ports: [{ containerPort: 8080 }]`),
});

codeSlide({ eyebrow: "Domain ownership", title: "The product owns its data: a schema per domain",
  lang: "YAML · CloudNativePG",
  note: "Each domain owns a Postgres cluster (or a schema within a managed one) declared as a custom resource. The operator runs it; the domain owns it. Ownership of data is literal — the order domain's data lives in the order domain's database, governed by the order domain.",
  code: code(`apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: order-db
  namespace: order
spec:
  instances: 3              # HA by default in production
  storage:
    size: 20Gi
    storageClass: ocs-storagecluster-ceph-rbd
  bootstrap:
    initdb:
      database: orders
      owner: order
  monitoring:
    enablePodMonitor: true  # metrics to the platform
  resources:
    requests: { cpu: 500m, memory: 1Gi }
    limits:   { cpu: "2",  memory: 2Gi }`),
});

contentSlide({ eyebrow: "Domain ownership", title: "What the principle buys you",
  bullets: [
    { text: "Velocity. A domain ships changes to its data product without waiting on a central team — the boundary is its own Project, and it owns everything inside it.", },
    { text: "Accountability. There is always a clear owner for every product, with the access and the budget to be responsible for it.", },
    { text: "Isolation. Quotas and project-scoped RBAC mean one domain's mistakes stay contained — no shared mutable state to corrupt across domains.", },
    { head: true, text: "What breaks without it" },
    { text: "Fuzzy boundaries and ownership vacuums: data nobody is responsible for, modeled three different ways by three teams. The platform-enforced Project boundary is what keeps that from happening by default.", },
  ] });

/* ====================== 02 · DATA AS A PRODUCT ====================== */
divider({ num: "02", title: "Data as a product", sub: "Discoverable, addressable, trustworthy, self-describing — held to the standard of any software product." });

contentSlide({ eyebrow: "Data as a product", title: "The principle, in one slide",
  bullets: [
    { text: "A data product is held to the same standard as any software product: discoverable, addressable, trustworthy, self-describing, interoperable, and secure.", },
    { text: "It is the architectural quantum of a mesh — the smallest unit you independently deploy and operate, carrying everything it needs to do its job.", lvl: 1 },
    { head: true, text: "Why it matters" },
    { text: "A 'data product' that is really just a renamed table can't serve itself, enforce its own policies, or describe itself — and federated governance has nowhere to live in it.", },
    { text: "Autonomy is what makes the rest of the mesh possible. Lose it, and you lose the governance model with it.", },
  ] });

diagramSlide({ eyebrow: "Data as a product", title: "Anatomy of a data product",
  image: "data-product-anatomy",
  caption: "Input ports, output ports, the transformation between them, and the metadata and policies that make it discoverable and governed. Not a dataset — a product." });

diagramSlide({ eyebrow: "Data as a product", title: "Every protocol is a contract",
  image: "contracts-registry-catalog",
  caption: "REST, gRPC, GraphQL, and events each carry a contract. One registry holds them all; the catalog makes the products discoverable and their lineage visible." });

diagramSlide({ eyebrow: "Data as a product", title: "Two jobs the registry does",
  image: "contract-flow",
  caption: "A runtime contract is load-bearing on the hot path — the event won't serialize without it. A discovery contract describes the product for humans, CI, and the catalog." });

codeSlide({ eyebrow: "Data as a product", title: "The runtime contract: a registered schema",
  lang: "Avro · schema registry",
  note: "The event schema is load-bearing: producer and consumer serialize against it, so the registry can reject an incompatible change at publish time — governance enforced computationally, before a single consumer breaks.",
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
      "name": "currency",        // v2: additive, backward-compatible
      "type": "string",
      "default": "USD"           // default keeps v1 consumers working
    },
    { "name": "placedAt", "type":
      { "type": "long", "logicalType": "timestamp-millis" } }
  ]
}

# compatibility: BACKWARD  (registry rejects breaking changes)`),
});

codeSlide({ eyebrow: "Data as a product", title: "Discovery contracts: published, not enforced at runtime",
  lang: "Protobuf · gRPC",
  note: "The gRPC contract and the REST OpenAPI document describe the product's synchronous surface. They're the source of truth for consumers, CI breaking-change checks, and catalog ingestion — published as artifacts, not serialized on the hot path.",
  code: code(`syntax = "proto3";
package acme.inventory.v1;

// inventory-service: the synchronous read surface
service Inventory {
  rpc GetStock(StockRequest) returns (StockReply);
  rpc Reserve(ReserveRequest) returns (ReserveReply);
}

message StockRequest {
  string sku = 1;
}

message StockReply {
  string sku       = 1;
  int32  available = 2;
  int32  reserved  = 3;
}`),
});

diagramSlide({ eyebrow: "Data as a product", title: "Operational vs. analytical — two planes, by domain",
  image: "operational-vs-analytical",
  caption: "A mesh reorganizes the operational/analytical split by domain rather than by technology layer — each domain owns both sides and closes the loop between them." });

codeSlide({ eyebrow: "Data as a product", title: "The async backbone: a domain event",
  lang: "YAML + Python · AMQ Streams",
  note: "When an order is placed, the order product emits an event; interested domains consume it on their own schedule. The producer doesn't know who's listening — consumers are added without touching it. This is the plane that keeps the operational/analytical loop closed.",
  code: code(`# KafkaTopic — declared, operator-managed (AMQ Streams)
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: order.placed
  namespace: platform
  labels: { strimzi.io/cluster: mesh-kafka }
spec:
  partitions: 6
  replicas: 3
  config: { retention.ms: 604800000 }
---
# producer (order-service) — emit on state change
await producer.send(
    "order.placed",
    key=order.id.encode(),
    value=avro.encode(OrderPlaced(
        orderId=order.id, customer=order.customer,
        total=order.total, currency=order.currency,
        placedAt=now_millis())))`),
});

contentSlide({ eyebrow: "Data as a product", title: "Why the catalog is a requirement, not an add-on",
  bullets: [
    { text: "The whole premise of a mesh is that domains own data independently and others consume it without a central team brokering access.", },
    { text: "That only works if products are discoverable and their contracts trustworthy. Without discovery infrastructure, consumers fall back to asking the central team — and the bottleneck returns.", },
    { head: true, text: "The catalog (OpenMetadata) provides" },
    { text: "Discovery: which products exist, their schemas, their owners.", lvl: 1 },
    { text: "Lineage: the who-produces-and-who-consumes graph across domains — answer 'if this schema changes, what's downstream?' without reading code.", lvl: 1 },
    { text: "So discovery is load-bearing structure, not decoration. A mesh without a usable catalog degrades into the proxy anti-pattern, even if every other piece is in place.", color: C.ink },
  ] });

/* ====================== 03 · SELF-SERVE DATA PLATFORM ====================== */
divider({ num: "03", title: "Self-serve data platform", sub: "Shared infrastructure domains consume — so they don't each build Kafka, a registry, a catalog, or observability." });

contentSlide({ eyebrow: "Self-serve platform", title: "The principle, in one slide",
  bullets: [
    { text: "Domain teams should not each build their own streaming, database operations, registry, catalog, or observability. The platform provides these as shared infrastructure they consume by declaration.", },
    { text: "A domain that needs Kafka asks for a topic — it does not learn to operate Kafka.", lvl: 1 },
    { head: true, text: "Why it matters" },
    { text: "Without a self-serve platform, every domain reinvents the same infrastructure, badly, and ownership fragments into shadow platform teams.", },
    { text: "The self-serve layer is what lets domain ownership scale: many domains, one platform, no central team in the critical path.", },
  ] });

diagramSlide({ eyebrow: "Self-serve platform", title: "The three planes of the platform",
  image: "platform-planes",
  caption: "The infrastructure plane, the data-product developer-experience plane, and the mesh-experience plane — what a domain consumes to ship a product without operating the substrate." });

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
})();

codeSlide({ eyebrow: "Self-serve platform", title: "Kafka, consumed by declaration",
  lang: "YAML · AMQ Streams (Strimzi)",
  note: "The platform runs one Kafka cluster as a custom resource; domains get topics by declaring KafkaTopic objects. No domain operates a broker — they consume the streaming plane the platform provides.",
  code: code(`apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: mesh-kafka
  namespace: platform
spec:
  kafka:
    replicas: 3
    listeners:
      - name: tls
        port: 9093
        type: internal
        tls: true
    storage:
      type: persistent-claim
      size: 100Gi
      class: ocs-storagecluster-ceph-rbd
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      min.insync.replicas: 2
  entityOperator:
    topicOperator: {}      # enables declarative KafkaTopic`),
});

diagramSlide({ eyebrow: "Self-serve platform", title: "Elastic products: scale to demand, and to zero",
  image: "decentralization-checklist",
  caption: "Decentralize everything except the platform's shared capabilities — elasticity among them. A product that costs nothing while idle can exist without justifying a standing footprint." });

codeSlide({ eyebrow: "Self-serve platform", title: "KEDA: scaling on real signals",
  lang: "YAML · KEDA",
  note: "Standard autoscaling watches CPU; a data product's real demand is requests or event lag. KEDA scales on those — including down to zero. The consumer scales on Kafka lag; the read gateway scales on HTTP volume.",
  code: code(`apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: notification-consumer
  namespace: notification
spec:
  scaleTargetRef:
    name: notification-service
  minReplicaCount: 0        # scale to zero when idle
  maxReplicaCount: 10
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: mesh-kafka-bootstrap.platform:9093
        consumerGroup: notification
        topic: order.placed
        lagThreshold: "50"   # one replica per ~50 lagging msgs`),
});

contentSlide({ eyebrow: "Self-serve platform", title: "Resilience: recoverability as a platform property",
  bullets: [
    { text: "The cloud-native answer to failure isn't 'prevent it' — it's 'make recovery cheap and automatic.' A mesh inherits this from the platform.", },
    { text: "A crashed pod is restarted; a failed rollout is rolled back; a node's workloads are rescheduled; declarative state continuously reconciles toward what you asked for.", lvl: 1 },
    { head: true, text: "Design products toward recoverability" },
    { text: "Don't hold critical state only in memory; come back to a known-good state after a crash; let the operator recover the systems it manages; let a downed consumer catch up on the backlog it missed.", },
    { text: "A product deployed this way is recoverable by construction — and that resilience is something the domain gets from the platform, not something it builds.", color: C.ink },
  ] });

contentSlide({ eyebrow: "Self-serve platform", title: "What the principle buys you — the OpenShift value",
  bullets: [
    { text: "Leverage. One platform team's work — an operator, a GitOps pipeline, a mesh — is consumed by every domain, instead of re-solved per domain.", },
    { text: "Consistency. Every product is deployed, scaled, secured, and observed the same way, because the platform provides the mechanism.", },
    { text: "Focus. Domain teams spend their time on their data and their logic, not on operating infrastructure.", },
    { head: true, text: "OpenShift specifically" },
    { text: "OperatorHub/OLM curate and lifecycle the capabilities; GitOps makes the whole mesh reproducible from Git; the integrated registry, Routes, and Service Mesh mean the substrate is there to consume, not assemble.", },
  ] });

/* ====================== 04 · FEDERATED COMPUTATIONAL GOVERNANCE ====================== */
divider({ num: "04", title: "Federated computational governance", sub: "Standards enforced computationally by the platform — not by meetings and policy documents." });

contentSlide({ eyebrow: "Federated governance", title: "The principle, in one slide",
  bullets: [
    { text: "A small set of global rules keeps independent products interoperable, and the platform enforces them automatically, at the boundary — not a review board after the fact.", },
    { text: "Federated: domains decide their own local rules; the platform enforces the few global ones that let products join up.", lvl: 1 },
    { head: true, text: "Why it matters" },
    { text: "Bolt governance on from outside and it never fits; over-correct into an approval bureaucracy and you've rebuilt the central bottleneck.", },
    { text: "Computational governance is the resolution: encode the global rules so the platform runs them, and ownership stays decentralized while standards hold.", },
  ] });

diagramSlide({ eyebrow: "Federated governance", title: "The governance model",
  image: "federated-governance-model",
  caption: "Global rules the platform enforces, local rules the domains own. The line between them is the central design decision of a mesh's governance." });

codeSlide({ eyebrow: "Federated governance", title: "Progressive delivery: canary a contract",
  lang: "YAML · OpenShift Service Mesh",
  note: "The interesting thing to canary in a mesh isn't a new binary — it's a new version of the contract. v2 adds the currency field; the mesh shifts live traffic by weight, so the contract evolves under controlled traffic. Shifting the canary is a one-line weight change: 90/10 → 50/50 → 0/100.",
  code: code(`apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata: { name: order-service, namespace: order }
spec:
  host: order-service
  subsets:
    - { name: v1, labels: { version: v1 } }
    - { name: v2, labels: { version: v2 } }
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata: { name: order-service, namespace: order }
spec:
  hosts: [order-service]
  http:
    - route:
        - destination: { host: order-service, subset: v1 }
          weight: 90
        - destination: { host: order-service, subset: v2 }
          weight: 10`),
});

codeSlide({ eyebrow: "Federated governance", title: "mTLS for free",
  lang: "YAML · OpenShift Service Mesh",
  note: "When products are in the mesh, the sidecars establish mutual TLS automatically — each service proves its identity and the traffic is encrypted, with no application code. 'Traffic between products is authenticated and encrypted' becomes a platform property, not a per-team checklist.",
  code: code(`apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT          # require mTLS mesh-wide
---
# authorization: only the gateway may call order-service
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: order-service-callers
  namespace: order
spec:
  selector: { matchLabels: { app: order-service } }
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - cluster.local/ns/gateway/sa/graphql-gateway`),
});

contentSlide({ eyebrow: "Federated governance", title: "Mesh selectively — a design decision",
  bullets: [
    { text: "The convenient default is namespace-wide sidecar injection: one label, everything meshed. The better default for a real platform is to opt specific workloads into the mesh.", },
    { head: true, text: "Three kinds of workload don't belong in the mesh" },
    { text: "Batch jobs meant to finish — a sidecar that never exits keeps the job from ever completing.", lvl: 1 },
    { text: "Operator-managed infrastructure with its own TLS — a second TLS layer collides with the database's own.", lvl: 1 },
    { text: "Anything where the sidecar's cost buys nothing — resource overhead and a control-plane dependency for no benefit.", lvl: 1 },
    { text: "Selective injection also contains blast radius: only workloads that need the mesh depend on its control plane being healthy. (The specific incidents behind this are in Appendix A.)", color: C.ink },
  ] });

codeSlide({ eyebrow: "Federated governance", title: "Policy at the boundary",
  lang: "YAML · Kyverno",
  note: "Global rules become admission policy the platform enforces as resources are created — every data product must declare an owner, must carry a contract label, must not run privileged. Governance is computational: the rule runs, rather than being remembered.",
  code: code(`apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: data-product-standards
spec:
  validationFailureAction: Enforce
  rules:
    - name: require-owner-and-contract
      match:
        any:
          - resources:
              kinds: [Deployment]
              selector:
                matchLabels: { "data-mesh/product": "*" }
      validate:
        message: "data products must declare owner + contract"
        pattern:
          metadata:
            labels:
              data-mesh/owner: "?*"
              data-mesh/contract: "?*"`),
});

contentSlide({ eyebrow: "Federated governance", title: "Observability is governance you can see",
  bullets: [
    { text: "In a system of independently-owned products talking to each other, the interesting behavior lives between products — where no single product's logs can see it. Observability is how anyone understands it.", },
    { head: true, text: "Three signals, each with a job" },
    { text: "Metrics — the mesh sidecars emit request rates, errors, and latencies for free; Prometheus scrapes them, Grafana shows the autoscaler responding and the canary split landing.", lvl: 1 },
    { text: "Traces — instrument the gateway and one GraphQL query produces an HTTP span, a REST client span, and a gRPC client span: all three protocols cooperating, in one trace.", lvl: 1 },
    { text: "Kiali — the live topology of products and the traffic between them, canary split and all.", lvl: 1 },
  ] });

codeSlide({ eyebrow: "Federated governance", title: "A trace span across products",
  lang: "Python · OpenTelemetry",
  note: "The gateway is the entry point for the federated read path, so instrumenting it yields the most instructive trace in the system. A single query becomes a connected tree of spans crossing three products and three protocols — the composition made visible.",
  code: code(`from opentelemetry import trace
tracer = trace.get_tracer("graphql-gateway")

async def resolve_order(info, order_id: str):
    with tracer.start_as_current_span("resolve.order") as span:
        span.set_attribute("order.id", order_id)

        # REST client span → order-service
        order = await rest.get(f"/orders/{order_id}")

        # gRPC client span → inventory-service
        stock = await inventory.GetStock(sku=order["sku"])

        return compose(order, stock)
# one query → HTTP server span + REST span + gRPC span,
# stitched into a single distributed trace in Tempo`),
});

/* ====================== 05 · THE WHOLE PICTURE ====================== */
divider({ num: "05", title: "The whole picture", sub: "The four principles, realized — and what the assembled platform lets you see it do." });

diagramSlide({ eyebrow: "The whole picture", title: "The reference architecture, assembled",
  image: "reference-data-mesh-architecture",
  caption: "Every piece in its place: domain products owning their data, the platform planes beneath, governance and observability spanning the whole — the mesh, complete." });

(() => {
  const s = pres.addSlide();
  s.background = { color: C.white };
  L.head(s, "The whole picture", "The four principles, realized on OpenShift");
  const rows = [
    [{ text: "Principle", options: { bold: true, color: "FFFFFF", fill: { color: C.red }, fontFace: F.head } },
     { text: "Realized by", options: { bold: true, color: "FFFFFF", fill: { color: C.red }, fontFace: F.head } }],
    ["Domain ownership", "Projects · project-scoped RBAC · SCCs · ResourceQuota · a database per domain"],
    ["Data as a product", "Deployments + Services + Routes · schema registry contracts · OpenMetadata catalog + lineage"],
    ["Self-serve platform", "OperatorHub/OLM · GitOps · AMQ Streams · CloudNativePG · KEDA · integrated registry"],
    ["Federated governance", "Service Mesh mTLS + canary · Kyverno admission policy · Prometheus/Tempo/Kiali"],
  ];
  s.addTable(rows, { x: 0.7, y: 2.0, w: PW - 1.4, colW: [3.3, PW - 1.4 - 3.3], rowH: [0.45, 0.95, 0.95, 0.95, 0.95],
    fontFace: F.body, fontSize: 13, color: C.ink, valign: "middle", border: { type: "solid", pt: 1, color: "E2E2E2" },
    fill: { color: "FBFAF7" } });
  L.footer(s);
})();

contentSlide({ eyebrow: "The whole picture", title: "What you can see it do",
  bullets: [
    { text: "Not just that the mesh runs — that you can watch it run. This is the acceptance bar the platform is built toward:", },
    { text: "A single GraphQL query appears as a trace whose spans cross three products and three protocols.", lvl: 1 },
    { text: "Metrics show the gateway's load and the autoscaler waking replicas to meet it.", lvl: 1 },
    { text: "A contract rolls out version by version as live traffic shifts across the canary.", lvl: 1 },
    { text: "The catalog shows the lineage of which products feed which.", lvl: 1 },
    { text: "Kiali shows the live topology, canary split and all.", lvl: 1 },
    { text: "These are the instruments through which you understand a system too distributed for any single vantage point.", color: C.ink },
  ] });

contentSlide({ eyebrow: "The whole picture", title: "Adoption: start small",
  bullets: [
    { text: "You don't adopt a mesh by building all of this at once. The principles are independent enough to land incrementally.", },
    { text: "Start with one domain and one product — give it a Project, a contract, and an owner.", lvl: 1 },
    { text: "Add the self-serve platform pieces as the second and third products need them, not before.", lvl: 1 },
    { text: "Introduce computational governance once you have products to govern — the registry before the catalog, mTLS before policy.", lvl: 1 },
    { head: true, text: "Let the architecture correct against reality" },
    { text: "Each piece is verifiable on its own. Stand one up, confirm it, then add the next — the same incremental discipline the reference implementation followed.", },
  ] });

contentSlide({ eyebrow: "The whole picture", title: "When a mesh is the wrong choice",
  bullets: [
    { text: "Honesty closes the value story: a data mesh is not for every organization, and saying so protects the ones it would only burden.", },
    { text: "It earns its complexity with many domains, many consumers, and the organizational maturity to operate products and standards across teams.", lvl: 1 },
    { text: "For a small organization, the overhead of decentralization can cost more than the bottleneck it removes.", lvl: 1 },
    { head: true, text: "Adopt principles, not fashion" },
    { text: "Sometimes a single principle — self-serve platform infrastructure, say — delivers most of the value without the full paradigm. Weigh data size, organizational complexity, existing tooling, and culture before committing.", },
  ] });

(() => {
  const s = pres.addSlide();
  s.background = { color: C.red };
  s.addText("The mesh is the network of products —", { x: 1.0, y: 2.5, w: PW - 2, h: 0.9, fontSize: 30, color: "FFFFFF", fontFace: F.head, bold: true, valign: "top", margin: 0 });
  s.addText("plus the platform and standards that let them interoperate.", { x: 1.0, y: 3.4, w: PW - 2, h: 1.2, fontSize: 30, color: "FFD9D9", fontFace: F.head, bold: true, valign: "top", margin: 0 });
  s.addText("OpenShift is where all four principles find a home.", { x: 1.0, y: 4.9, w: PW - 2, h: 0.6, fontSize: 16, color: "FFFFFF", fontFace: F.body, valign: "top", margin: 0 });
  L.pageNum(s, { dark: true });
  s.addText("Thank you", { x: PW - 3.0, y: PH - 0.55, w: 2.5, h: 0.35, fontSize: 13, color: "FFFFFF", fontFace: F.head, bold: true, align: "right", margin: 0 });
})();

/* ====================== APPENDIX A · GOTCHAS ====================== */
divider({ num: "A", title: "Appendix A — Gotchas", sub: "What we learned running it. Operational sharp edges, kept out of the value story on purpose." });

contentSlide({ eyebrow: "Appendix A · Gotchas", title: "Why these live in an appendix",
  bullets: [
    { text: "The main narrative is about the value each piece delivers. These are the operational potholes you hit making the pieces work together — a different kind of lesson: specific, technical, and best learned before you trip on them.", },
    { text: "Some are particular to a constrained learning cluster; the ones below generalize to any real deployment. Each is symptom → cause → fix.", color: C.ink },
  ] });

(() => {
  const items = [
    { h: "A meshed batch job never completes", c: "A Job pod gets a sidecar that never exits; the pod sits at 1/2 forever and the Job hangs. Catalog ingestion jobs hit this.", f: "Opt jobs out of injection (sidecar.istio.io/inject: \"false\"), or run them in an unmeshed namespace. A run-and-terminate workload can't carry a run-and-stay sidecar." },
    { h: "Operator-managed database crash-loops under the mesh", c: "A managed Postgres runs its own TLS on its internal ports; an injected sidecar re-wraps those connections and breaks the database's own TLS. It exits and restarts repeatedly.", f: "Exclude operator-managed infrastructure with its own TLS from the mesh. Selective injection, not namespace-wide." },
    { h: "Everything in a namespace depends on the mesh control plane", c: "With namespace-wide injection, every pod creation goes through the injection webhook. If the control plane has a bad moment, you can't start a database pod or a job either.", f: "Mesh selectively so only workloads that need it depend on it — contain the blast radius." },
    { h: "Stateful workloads need headroom to recover", c: "A database sized only to run can be OOM-killed during crash-recovery (e.g. WAL replay), turning a brief blip into a crash loop.", f: "Size stateful workloads for their recovery path, not just steady state. Give the operator room to bring them back." },
  ];
  items.forEach((it) => {
    const s = pres.addSlide();
    s.background = { color: C.white };
    L.head(s, "Appendix A · Gotchas", it.h, { titleH: 1.1 });
    L.addBullets(s, [
      { head: true, text: "Symptom" }, { text: it.c },
      { head: true, text: "Fix" }, { text: it.f },
    ], { x: 0.7, y: 2.1, w: PW - 1.4, fontSize: 17 });
    L.footer(s);
  });
})();

/* ============================ WRITE ============================ */
pres.writeFile({ fileName: "Data_Mesh_on_OpenShift.pptx" }).then((f) => {
  console.log("WROTE", f);
});
