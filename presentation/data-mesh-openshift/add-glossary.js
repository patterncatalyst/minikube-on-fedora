// add-glossary.js — append "Definitions:" bullet blocks to the speaker notes of
// slides that list acronyms / Kubernetes-OpenShift objects. Idempotent-ish:
// only appends if the note doesn't already contain "Definitions:".
const fs = require("fs");
const path = "build-deck.js";
let src = fs.readFileSync(path, "utf8");

// master glossary
const G = {
  Project: "Project — OpenShift's unit of tenancy: a Kubernetes namespace with added governance (annotations, RBAC, lifecycle). One per domain here.",
  RBAC: "RBAC (Role-Based Access Control) — Kubernetes' permission model; Roles grant verbs on resources, RoleBindings bind them to users/groups, enforced by the API server.",
  SCC: "SCC (Security Context Constraint) — OpenShift policy controlling what a pod may do on the node (run as root, mount host paths, privileged, etc.).",
  ResourceQuota: "ResourceQuota — a namespace-level cap on aggregate resource use (CPU, memory, object counts) so one domain can't starve others.",
  LimitRange: "LimitRange — per-container default and max resource limits applied within a namespace when a pod omits its own.",
  ServiceAccount: "ServiceAccount — a workload identity inside a namespace; pods run as one, and mesh mTLS and authorization policies key off it.",
  Deployment: "Deployment — the Kubernetes object that runs and maintains a replicated set of pods for a service.",
  Service: "Service — a stable in-cluster address (name + virtual IP) that load-balances to a Deployment's pods.",
  Route: "Route — OpenShift's object for exposing a Service to traffic outside the cluster (akin to an Ingress).",
  CRD: "CRD (Custom Resource Definition) — extends the Kubernetes API with new object types; operators define and reconcile these.",
  OperatorHub: "OperatorHub — OpenShift's catalog of installable operators; the platform team curates what's available.",
  OLM: "OLM (Operator Lifecycle Manager) — installs, updates, and manages the lifecycle of operators on the cluster.",
  GitOps: "GitOps — desired cluster state lives in Git and is continuously reconciled onto the cluster (OpenShift GitOps is based on Argo CD).",
  Argo: "Argo CD — the GitOps controller that syncs Git-declared state to the cluster.",
  "AMQ Streams": "AMQ Streams — Red Hat's supported distribution of Strimzi: Apache Kafka run on Kubernetes via operators.",
  Strimzi: "Strimzi — the upstream operator project that runs Apache Kafka on Kubernetes (Kafka, KafkaTopic, etc. as custom resources).",
  CloudNativePG: "CloudNativePG (CNPG) — an operator that runs PostgreSQL clusters on Kubernetes as a custom resource.",
  CNPG: "CNPG (CloudNativePG) — an operator that runs PostgreSQL on Kubernetes; manages HA, backups, and its own TLS.",
  KEDA: "KEDA (Kubernetes Event-Driven Autoscaling) — scales workloads on external signals (queue lag, request rate), including to zero.",
  ScaledObject: "ScaledObject — KEDA's custom resource that ties a workload to a scaling trigger (e.g. Kafka lag).",
  mTLS: "mTLS (mutual TLS) — both client and server present certificates; the mesh establishes it automatically between sidecars, with no app code.",
  Istio: "Istio — the service mesh project underlying OpenShift Service Mesh; injects sidecar proxies and controls traffic/security.",
  "Service Mesh": "Service Mesh (OpenShift Service Mesh / Istio) — a layer of sidecar proxies that secures, routes, and observes service-to-service traffic.",
  sidecar: "Sidecar — a proxy container (Envoy) injected next to your app container; carries the mesh's traffic, security, and telemetry.",
  Envoy: "Envoy — the high-performance proxy used as the mesh sidecar/data plane.",
  istiod: "istiod — the Istio control plane; issues identities/certificates and pushes routing and policy to every sidecar.",
  VirtualService: "VirtualService — Istio's routing rule; here it splits traffic between service versions by weight (the canary).",
  DestinationRule: "DestinationRule — Istio's object defining service subsets (e.g. v1/v2) that a VirtualService routes to.",
  PeerAuthentication: "PeerAuthentication — Istio policy that requires mTLS for traffic between meshed workloads.",
  Kyverno: "Kyverno — a Kubernetes-native policy engine that validates/mutates resources at admission.",
  admission: "Admission control — the API-server gate that validates or rejects resources as they're created; where computational governance runs.",
  Prometheus: "Prometheus — the metrics database; scrapes request rates, errors, latencies, and consumer lag (much of it emitted by the mesh sidecars).",
  Tempo: "Tempo — the distributed-tracing backend; stores spans so a request's path across products can be reconstructed.",
  Kiali: "Kiali — the mesh console showing the live service topology and traffic, including the canary split.",
  Grafana: "Grafana — the dashboard layer over metrics and traces.",
  OTLP: "OTLP (OpenTelemetry Protocol) — the wire format workloads and sidecars use to export metrics and traces to the collector.",
  OTel: "OpenTelemetry (OTel) — the vendor-neutral standard and SDKs for emitting traces and metrics from application code.",
  OpenTelemetry: "OpenTelemetry (OTel) — the vendor-neutral standard and SDKs for emitting traces/metrics; here, used to instrument the gateway.",
  OpenMetadata: "OpenMetadata — the data catalog: which products exist, their schemas, owners, and the lineage graph across domains.",
  Apicurio: "Apicurio Registry — the schema/contract registry; stores Avro/Protobuf/OpenAPI/SDL and enforces compatibility.",
  Avro: "Avro — a binary serialization format with a schema; the runtime event contract, enforced by the registry at publish time.",
  Protobuf: "Protobuf (Protocol Buffers) — the strongly-typed contract format for gRPC interfaces (.proto files).",
  gRPC: "gRPC — a fast, strongly-typed RPC protocol over HTTP/2; used for synchronous service-to-service calls.",
  GraphQL: "GraphQL — a query language that lets a client request exactly the shape it needs; the gateway uses it to compose reads across products.",
  SDL: "SDL (Schema Definition Language) — GraphQL's contract format describing the available types and queries.",
  OpenAPI: "OpenAPI — the contract format describing a REST API's endpoints, parameters, and responses.",
  REST: "REST — resource-oriented HTTP APIs; used at the edge where external clients cross the trust boundary.",
  FastAPI: "FastAPI — the Python web framework used to implement the REST surface; emits OpenAPI automatically.",
  Strawberry: "Strawberry — the Python GraphQL library used to implement the gateway's resolvers.",
  Kafka: "Kafka — the distributed event log / streaming platform; domains publish and consume domain events on topics.",
  lineage: "Lineage — the graph of which products produce and which consume each dataset/event; answers 'if this changes, what's downstream?'",
  UBI: "UBI (Universal Base Image) — Red Hat's freely redistributable, enterprise-maintained container base image; a legitimate production base without a subscription.",
  SBOM: "SBOM (Software Bill of Materials) — a manifest of every component in an image, used to audit and verify what's inside.",
  CVE: "CVE (Common Vulnerabilities and Exposures) — a publicly catalogued security vulnerability identifier.",
  WAL: "WAL (Write-Ahead Log) — the database's durability log; replaying it on restart is memory-intensive, which is why recovery needs headroom.",
  canary: "Canary — a progressive rollout that shifts a fraction of live traffic to a new version, increasing it as confidence grows.",
  Pydantic: "Pydantic — the Python data-validation library FastAPI uses to enforce request/response contracts.",
};

// which terms to attach to which slide (matched by a unique snippet of the slide's title string in build-deck.js)
// We match on the title text that appears in head(...) or title: "..." for that slide.
const SLIDES = [
  { match: '"The value thesis"', terms: ["OperatorHub", "OLM", "GitOps", "RBAC", "SCC", "mTLS", "admission", "Service Mesh", "AMQ Streams"] },
  { match: '"Five data products and a read gateway"', terms: ["Project", "REST", "gRPC", "GraphQL"] },
  { match: '"Ownership = a Project per domain"', terms: ["Project", "RBAC", "SCC", "ResourceQuota", "LimitRange", "ServiceAccount"] },
  { match: '"The domain\'s Project and identity"', terms: ["Project", "ServiceAccount", "mTLS"] },
  { match: '"The domain owns its access"', terms: ["RBAC"] },
  { match: '"Four protocols, four contracts — each by fitness"', terms: ["REST", "gRPC", "GraphQL", "OpenAPI", "Protobuf", "SDL", "Avro"] },
  { match: '"The gateway composes — in Python"', terms: ["GraphQL", "REST", "gRPC", "Strawberry"] },
  { match: '"The runtime contract: a registered schema"', terms: ["Avro", "Apicurio"] },
  { match: '"Discovery and lineage — the catalog"', terms: ["OpenMetadata", "lineage", "Apicurio"] },
  { match: '"Operators are the self-serve mechanism"', terms: ["OperatorHub", "OLM", "GitOps", "Argo", "CRD", "AMQ Streams", "CloudNativePG", "Service Mesh"] },
  { match: '"A trusted base for every data product"', terms: ["UBI", "SBOM", "CVE", "admission"] },
  { match: '"Elastic products: scale on lag, even to zero"', terms: ["KEDA", "Kafka"] },
  { match: '"Elastic reads: the KEDA HTTP add-on"', terms: ["KEDA", "canary"] },
  { match: '"The three planes of the platform"', terms: ["Kafka", "OpenMetadata"] },
  { match: '"The service mesh: secure by default, shiftable on demand"', terms: ["Istio", "Service Mesh", "sidecar", "Envoy", "istiod", "mTLS", "canary"] },
  { match: '"Canary a contract — the one mesh manifest worth seeing"', terms: ["VirtualService", "DestinationRule", "canary", "Service Mesh", "Istio"] },
  { match: '"Mesh selectively — a design decision"', terms: ["sidecar", "Istio", "admission"] },
  { match: '"Observability — the mesh emits, the platform collects"', terms: ["Prometheus", "Tempo", "Kiali", "Grafana", "OTLP", "sidecar"] },
  { match: '"Three signals, correlated across a domain"', terms: ["OTel"] },
  { match: '"A trace span across products — in Python"', terms: ["OpenTelemetry", "GraphQL", "REST", "gRPC", "Tempo"] },
  { match: '"Standards that hold, ownership that stays put"', terms: ["mTLS", "admission", "Prometheus", "Tempo", "Kiali"] },
  { match: '"What you can see it do"', terms: ["GraphQL", "Kiali", "canary", "lineage"] },
  { match: '"The four principles, realized on OpenShift"', terms: ["Project", "RBAC", "SCC", "ResourceQuota", "OperatorHub", "OLM", "GitOps", "KEDA", "mTLS", "canary", "admission", "Prometheus", "Tempo", "Kiali", "OpenMetadata"] },
  { match: '"A meshed batch job never completes"', terms: ["sidecar"] },
  { match: '"Operator-managed database crash-loops under the mesh"', terms: ["sidecar", "CNPG", "mTLS"] },
  { match: '"Everything in a namespace depends on the mesh control plane"', terms: ["sidecar", "admission", "istiod"] },
  { match: '"Stateful workloads need headroom to recover"', terms: ["WAL"] },
];

function buildBlock(terms) {
  // emitted into a JS double-quoted string literal in the source file, so newlines
  // must be the two-character escape \n and double-quotes must be escaped.
  const defs = terms.filter((t) => G[t]).map((t) => "\\n• " + G[t].replace(/"/g, '\\"'));
  return "\\n\\nDefinitions:" + defs.join("");
}

let applied = 0, skipped = 0, missing = 0;
for (const sl of SLIDES) {
  const idx = src.indexOf(sl.match);
  if (idx === -1) { console.log("NOT FOUND:", sl.match); missing++; continue; }
  // locate this slide's note string: the first of `notes:` or `addNotes(` after the title match
  const niA = src.indexOf("notes:", idx);
  const niB = src.indexOf("addNotes(", idx);
  let ni;
  if (niA === -1) ni = niB;
  else if (niB === -1) ni = niA;
  else ni = Math.min(niA, niB);
  if (ni === -1) { console.log("NO notes for:", sl.match); missing++; continue; }
  const q1 = src.indexOf('"', ni);
  let i = q1 + 1;
  while (i < src.length) {
    if (src[i] === "\\") { i += 2; continue; }
    if (src[i] === '"') break;
    i += 1;
  }
  const closing = i;
  const existing = src.slice(q1 + 1, closing);
  if (existing.includes("Definitions:")) { skipped++; continue; }
  src = src.slice(0, closing) + buildBlock(sl.terms) + src.slice(closing);
  applied++;
}
fs.writeFileSync(path, src);
console.log(`applied glossary to ${applied} slides, skipped ${skipped}, missing ${missing}`);
