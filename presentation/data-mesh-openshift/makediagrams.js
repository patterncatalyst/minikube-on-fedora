// makediagrams.js — generate the new diagrams in the 101 grammar.
const { SVG } = require("./svglib.js");
const fs = require("fs");
const OUT = "newsvg";
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT);
const save = (name, svg) => {
  fs.writeFileSync(`${OUT}/${name}.svg`, svg.render());
  fs.writeFileSync(`${OUT}/${name}.excalidraw`, svg.excalidraw());
  console.log("wrote", name, "(svg + excalidraw)");
};

/* ========== 1. SERVICE MESH INTERNALS ========== */
(() => {
  const s = new SVG(1180, 560);
  s.title("The service mesh — sidecars, mTLS, and traffic shifting", "Istio / OpenShift Service Mesh: the data plane is a sidecar beside every product");
  // two services each with app + sidecar
  const svc = (x, name, fam) => {
    s.rect(x, 120, 250, 150, fam);
    s.text(x + 125, 145, name, { size: 13, anchor: "middle", weight: 700, fill: "#1a3a6a" });
    s.plainRect(x + 20, 160, 100, 90, "#ffffff", "#5a8a3a");
    s.lines(x + 70, 185, ["app", "container"], { size: 10.5, anchor: "middle", fill: "#2a5a1a", lh: 15 });
    s.plainRect(x + 130, 160, 100, 90, "#fdf0ec", "#c14a3a");
    s.lines(x + 180, 185, ["istio-proxy", "(Envoy)", "sidecar"], { size: 10, anchor: "middle", fill: "#a8331f", lh: 14 });
  };
  svc(120, "order-service", "blue");
  svc(640, "inventory-service", "blue");
  // mTLS arrow sidecar-to-sidecar
  s.arrow(420, 205, 770, 205, { color: "#c14a3a", marker: "arrR", w: 2 });
  s.text(595, 195, "mutual TLS", { size: 11, anchor: "middle", weight: 700, fill: "#a8331f" });
  s.text(595, 300, "encrypted + authenticated, no app code", { size: 10, anchor: "middle", italic: true, fill: "#666666" });
  // control plane
  s.rect(360, 330, 460, 80, "tan");
  s.text(590, 358, "istiod — the control plane", { size: 12.5, anchor: "middle", weight: 700, fill: "#5a3a0a" });
  s.text(590, 380, "issues identities/certs · pushes routing + policy to every sidecar", { size: 10.5, anchor: "middle", fill: "#3a3a3a" });
  s.arrow(450, 330, 300, 272, { color: "#c19a6b", w: 1.4, dash: "4 3" });
  s.arrow(730, 330, 860, 272, { color: "#c19a6b", w: 1.4, dash: "4 3" });
  // canary weights callout
  s.rect(120, 450, 940, 70, "green");
  s.text(140, 478, "Traffic shifting (canary):", { size: 12, weight: 700, fill: "#2a5a1a" });
  s.pill(370, 462, 150, "v1 — 90%", "blue");
  s.pill(540, 462, 150, "v2 — 10%", "orange");
  s.text(820, 478, "weights move 90/10 → 50/50 → 0/100", { size: 11, fill: "#3a3a3a" });
  s.text(820, 498, "the mesh splits live traffic; no client change", { size: 10, italic: true, fill: "#666666" });
  s.footer("The mesh sits between products: it secures their traffic and routes it — both as platform properties, not application code.");
  save("17-service-mesh", s);
})();

/* ========== 2. OBSERVABILITY STACK ========== */
(() => {
  const s = new SVG(1180, 540);
  s.title("Observability — the mesh emits, the platform collects", "Metrics, traces, and the live topology, mostly without touching application code");
  // products row
  for (let i = 0; i < 3; i++) {
    const x = 120 + i * 200;
    s.rect(x, 90, 170, 70, "blue");
    s.text(x + 85, 122, ["order", "inventory", "gateway"][i] + "-svc", { size: 11.5, anchor: "middle", weight: 700, fill: "#1a3a6a" });
    s.text(x + 85, 142, "+ sidecar", { size: 9.5, anchor: "middle", fill: "#666666" });
    s.arrow(x + 85, 160, x + 85, 215, { color: "#5a5a5a", w: 1.4 });
  }
  s.text(420, 195, "metrics + traces (OTLP)", { size: 10.5, anchor: "middle", italic: true, fill: "#666666" });
  // collector
  s.rect(120, 220, 570, 56, "tan");
  s.text(405, 254, "OTEL Collector — receives OTLP, fans out", { size: 12, anchor: "middle", weight: 700, fill: "#5a3a0a" });
  // backends
  const backend = (x, name, desc, fam) => {
    s.rect(x, 320, 250, 90, fam);
    s.text(x + 125, 348, name, { size: 12.5, anchor: "middle", weight: 700 });
    s.lines(x + 125, 370, desc, { size: 10.5, anchor: "middle", fill: "#3a3a3a", lh: 15 });
  };
  s.arrow(260, 276, 245, 320, { color: "#c19a6b", w: 1.4 });
  s.arrow(405, 276, 530, 320, { color: "#c19a6b", w: 1.4 });
  s.arrow(560, 276, 815, 320, { color: "#c19a6b", w: 1.4 });
  backend(120, "Prometheus", ["scrapes mesh metrics:", "rates, errors, latency, lag"], "green");
  backend(405, "Tempo", ["stores distributed traces:", "spans across products"], "orange");
  backend(815, "Kiali", ["live mesh topology:", "who calls whom, canary split"], "red");
  // grafana unifies
  s.rect(120, 440, 690, 60, "blue");
  s.text(465, 476, "Grafana — one pane: dashboards over metrics + traces, correlated", { size: 12, anchor: "middle", weight: 700, fill: "#1a3a6a" });
  s.arrow(245, 410, 360, 440, { color: "#5a8a3a", w: 1.3 });
  s.arrow(530, 410, 500, 440, { color: "#c97a3a", w: 1.3 });
  // kiali standalone note
  s.rect(880, 440, 180, 60, "red");
  s.text(970, 466, "live view", { size: 11, anchor: "middle", weight: 700, fill: "#a8331f" });
  s.text(970, 484, "during demos", { size: 10, anchor: "middle", fill: "#3a3a3a" });
  s.footer("The sidecars already measure the traffic they carry — most of this is observability you get from the platform, not code you write.");
  save("17-observability-stack", s);
})();

/* ========== 3. THREE SIGNALS CORRELATED ACROSS A DOMAIN ========== */
(() => {
  const s = new SVG(1180, 560);
  s.title("Metrics, logs, and traces — correlated across a domain", "One request touches three products; correlation is what makes the whole legible");
  // a single trace spanning three products (top)
  s.text(90, 95, "ONE REQUEST, ONE TRACE", { size: 9, weight: 600, fill: "#8a7a5a" });
  const span = (x, w, label, fam, y) => { s.rect(x, y, w, 34, fam); s.text(x + w / 2, y + 22, label, { size: 10.5, anchor: "middle", weight: 700 }); };
  span(90, 1000, "HTTP server span — GraphQL query @ gateway", "blue", 105);
  span(150, 430, "REST client span → order-service", "orange", 145);
  span(610, 360, "gRPC client span → inventory-service", "green", 145);
  s.text(90, 205, "trace id propagates across every product boundary", { size: 10, italic: true, fill: "#666666" });

  // the three signals as columns, tied by the shared trace/correlation id
  const col = (x, title, fam, rows) => {
    s.rect(x, 250, 320, 230, fam);
    const f = require("./svglib.js").FAM[fam];
    s.text(x + 160, 278, title, { size: 13, anchor: "middle", weight: 700, fill: f.head });
    s.lines(x + 20, 308, rows, { size: 10.5, fill: "#3a3a3a", lh: 19 });
  };
  col(90, "METRICS", "green", ["• request rate, errors, p99 latency", "• consumer-group lag", "• replica count (autoscaler)", "", "answers: is it slow / failing,", "and is the platform reacting?"]);
  col(430, "TRACES", "orange", ["• the span tree above", "• per-hop timing across products", "• which downstream call was slow", "", "answers: WHERE in the path", "did the time or error come from?"]);
  col(770, "LOGS", "blue", ["• the detailed per-event record", "• emitted with the same trace id", "• reached for once you know where", "", "answers: exactly WHAT happened", "at the point of interest"]);

  // correlation key band
  s.rect(90, 500, 1000, 42, "red");
  s.text(110, 526, "Correlation id (trace id) stamped on all three:", { size: 11.5, weight: 700, fill: "#a8331f" });
  s.text(560, 526, "jump from a latency spike (metric) → the slow trace → the exact log line — across the whole domain.", { size: 10.5, fill: "#3a3a3a" });
  save("17-three-signals", s);
})();

/* ========== 4. THE APIs AND THEIR IMPLEMENTATIONS ========== */
(() => {
  const s = new SVG(1180, 560);
  s.title("Four protocols, four contracts — each by fitness", "A data product exposes the protocols that fit its role, not a uniform surface");
  const api = (x, y, name, fam, kind, who, contract) => {
    s.rect(x, y, 250, 175, fam);
    const f = require("./svglib.js").FAM[fam];
    s.text(x + 16, y + 28, name, { size: 14, weight: 700, fill: f.head });
    s.text(x + 16, y + 52, kind, { size: 10.5, fill: "#666666", italic: true });
    s.text(x + 16, y + 82, "WHERE IT FITS", { size: 9, weight: 600, fill: "#8a7a5a" });
    s.lines(x + 16, y + 100, who, { size: 10.5, fill: "#3a3a3a", lh: 15 });
    s.text(x + 16, y + 148, "CONTRACT", { size: 9, weight: 600, fill: "#8a7a5a" });
    s.text(x + 16, y + 166, contract, { size: 11, fill: f.head, weight: 700 });
  };
  api(90, 90, "REST", "blue", "request/response, cacheable", ["external clients cross", "the trust boundary here"], "OpenAPI");
  api(370, 90, "gRPC", "green", "fast, strongly-typed RPC", ["synchronous service-to-", "service calls in the mesh"], "Protobuf (.proto)");
  api(650, 90, "GraphQL", "orange", "client-shaped composition", ["one query composes reads", "across several products"], "GraphQL SDL");
  api(930, 90, "Events", "red", "asynchronous, decoupled", ["something happened;", "downstreams react"], "Avro schema");
  // implementation band (python)
  s.rect(90, 300, 1000, 90, "tan");
  s.text(110, 326, "IMPLEMENTED IN PYTHON", { size: 9, weight: 600, fill: "#8a7a5a" });
  s.lines(110, 348, [
    "FastAPI  →  REST surface + OpenAPI emitted automatically        grpcio  →  gRPC servers from the .proto",
    "Strawberry  →  GraphQL gateway resolvers (call REST + gRPC)      aiokafka  →  async event producer/consumer",
  ], { size: 11, fill: "#3a3a3a", lh: 22 });
  // the gateway composes
  s.rect(90, 415, 1000, 95, "white");
  s.text(110, 441, "THE GATEWAY COMPOSES — one query, multiple backends", { size: 10.5, weight: 700, fill: "#5a3a0a" });
  s.pill(110, 458, 130, "GraphQL in", "orange");
  s.arrow(245, 471, 300, 471, { color: "#5a5a5a" });
  s.pill(310, 458, 180, "REST → order-svc", "blue");
  s.pill(500, 458, 200, "gRPC → inventory-svc", "green");
  s.arrow(710, 471, 765, 471, { color: "#5a5a5a" });
  s.pill(775, 458, 200, "shaped response out", "orange");
  s.footer("REST at the edge, gRPC between services, GraphQL to compose, events to decouple — each protocol earning its place by fitness.");
  save("17-api-implementations", s);
})();

/* ========== 5a. KEDA + METRICS (Kafka lag) ========== */
(() => {
  const s = new SVG(1180, 500);
  s.title("KEDA scaling on Kafka lag — scale to demand, and to zero", "An event consumer's real demand is the backlog waiting for it");
  // topic with lag
  s.rect(90, 110, 250, 110, "red");
  s.text(215, 138, "order.placed topic", { size: 12.5, anchor: "middle", weight: 700, fill: "#a8331f" });
  s.text(215, 165, "consumer-group lag", { size: 10.5, anchor: "middle", fill: "#3a3a3a" });
  s.pill(140, 182, 150, "lag = 0 → 230 msgs", "red");
  // KEDA watches
  s.rect(450, 110, 250, 110, "green");
  s.text(575, 138, "KEDA", { size: 14, anchor: "middle", weight: 700, fill: "#2a5a1a" });
  s.lines(575, 162, ["watches lag via the", "Kafka scaler trigger"], { size: 10.5, anchor: "middle", fill: "#3a3a3a", lh: 15 });
  s.arrow(340, 165, 450, 165, { color: "#c14a3a", marker: "arrR", w: 1.8 });
  s.text(395, 152, "reads", { size: 10, anchor: "middle", italic: true, fill: "#666666" });
  // scales deployment
  s.rect(810, 110, 280, 110, "blue");
  s.text(950, 138, "notification-service", { size: 12.5, anchor: "middle", weight: 700, fill: "#1a3a6a" });
  s.text(950, 162, "replicas scale with lag", { size: 10.5, anchor: "middle", fill: "#3a3a3a" });
  s.pill(835, 182, 230, "0 → 1 → … → up to 10", "blue");
  s.arrow(700, 165, 810, 165, { color: "#5a8a3a", marker: "arrG", w: 1.8 });
  s.text(755, 152, "scales", { size: 10, anchor: "middle", italic: true, fill: "#666666" });
  // scale to zero band
  s.rect(90, 280, 1000, 80, "tan");
  s.text(110, 308, "SCALE TO ZERO", { size: 10, weight: 600, fill: "#8a7a5a" });
  s.text(110, 334, "Idle backlog → zero replicas: the product costs nothing while no events flow, then materializes when lag rises.", { size: 12, fill: "#3a3a3a" });
  // contrast
  s.rect(90, 385, 1000, 70, "white");
  s.text(110, 412, "Why not CPU?  ", { size: 12, weight: 700, fill: "#5a3a0a" });
  s.text(245, 412, "A consumer pegged at 0% CPU with a 10k-message backlog should scale up — CPU can't see that. Lag can.", { size: 11, fill: "#3a3a3a" });
  s.text(110, 438, "The signal is the work waiting, not the work being done.", { size: 11, italic: true, fill: "#666666" });
  s.footer("Elastic data products: scale on the real demand signal — the queue — including all the way down to nothing.");
  save("17-keda-lag", s);
})();

/* ========== 5b. KEDA + HTTP ADD-ON ========== */
(() => {
  const s = new SVG(1180, 500);
  s.title("KEDA HTTP add-on — scaling the read gateway on request volume", "A synchronous read product's demand is incoming queries, including down to zero");
  // requests
  s.rect(90, 110, 230, 110, "orange");
  s.text(205, 138, "incoming queries", { size: 12.5, anchor: "middle", weight: 700, fill: "#7a3a0a" });
  s.text(205, 165, "HTTP request volume", { size: 10.5, anchor: "middle", fill: "#3a3a3a" });
  s.pill(120, 182, 170, "0 → bursts → 0", "orange");
  // interceptor
  s.rect(420, 110, 270, 110, "green");
  s.text(555, 136, "KEDA HTTP add-on", { size: 12.5, anchor: "middle", weight: 700, fill: "#2a5a1a" });
  s.lines(555, 160, ["interceptor counts requests,", "holds them while scaling up"], { size: 10, anchor: "middle", fill: "#3a3a3a", lh: 15 });
  s.arrow(320, 165, 420, 165, { color: "#c97a3a", w: 1.8 });
  // gateway
  s.rect(800, 110, 290, 110, "blue");
  s.text(945, 138, "graphql-gateway", { size: 12.5, anchor: "middle", weight: 700, fill: "#1a3a6a" });
  s.text(945, 162, "scales with request rate", { size: 10.5, anchor: "middle", fill: "#3a3a3a" });
  s.pill(835, 182, 220, "0 → N replicas", "blue");
  s.arrow(690, 165, 800, 165, { color: "#5a8a3a", marker: "arrG", w: 1.8 });
  // placement decision
  s.rect(90, 280, 1000, 95, "red");
  s.text(110, 308, "A DELIBERATE PLACEMENT DECISION", { size: 10, weight: 600, fill: "#8a7a5a" });
  s.lines(110, 332, [
    "HTTP scaling goes on the gateway — NOT on order-service.",
    "order-service carries the canary; HTTP-scaling a service whose traffic is split by weight would have the two mechanisms fight over the same pods.",
  ], { size: 11.5, fill: "#3a3a3a", lh: 20 });
  // at-rest quirk
  s.rect(90, 400, 1000, 56, "white");
  s.text(110, 432, "At rest (scaled to zero) the HTTP scaler reports \"unknown\" until the first request arrives — expected, not a fault.", { size: 11, italic: true, fill: "#666666" });
  s.footer("Match the scaler to the workload: lag for the consumer, requests for the gateway, and neither on the canaried service.");
  save("17-keda-http", s);
})();

/* ========== 6. PER-SECTION VALUE DIAGRAMS (principle → implementing pieces) ========== */
function valueDiagram(name, num, principle, fam, valueLine, pieces, breaks) {
  const s = new SVG(1180, 540);
  s.title(`Principle ${num}: ${principle} — realized`, "The value, and the pieces of the reference implementation that deliver it");
  // principle value banner
  s.rect(90, 75, 1000, 70, fam);
  const f = require("./svglib.js").FAM[fam];
  s.text(110, 103, `${num}  ${principle.toUpperCase()}`, { size: 13, weight: 700, fill: f.head });
  s.text(110, 127, valueLine, { size: 12, fill: "#3a3a3a" });
  // implementing pieces as callout cards
  s.text(90, 180, "REALIZED BY — the reference-implementation pieces", { size: 10, weight: 600, fill: "#8a7a5a" });
  const cols = pieces.length <= 4 ? pieces.length : Math.ceil(pieces.length / 2);
  const cw = (1000 - (cols - 1) * 20) / cols;
  pieces.forEach((p, i) => {
    const row = Math.floor(i / cols), colI = i % cols;
    const x = 90 + colI * (cw + 20), y = 200 + row * 130;
    s.rect(x, y, cw, 110, "white");
    s.pill(x + 12, y + 12, Math.min(cw - 24, 200), p.piece, fam);
    s.lines(x + 14, y + 58, p.does, { size: 10.5, fill: "#3a3a3a", lh: 15 });
  });
  // what breaks without it
  const by = pieces.length <= 4 ? 340 : 470;
  s.rect(90, by, 1000, 60, "red");
  s.text(110, by + 26, "WITHOUT IT", { size: 9, weight: 600, fill: "#8a7a5a" });
  s.text(110, by + 46, breaks, { size: 11.5, fill: "#3a3a3a" });
  s.footer(valueLine);
  save(name, s);
}

valueDiagram("17-value-domain-ownership", "01", "Domain ownership", "blue",
  "Each domain ships its data product on its own, with a clear owner and an enforced boundary — no central team in the path.",
  [
    { piece: "Project / namespace", does: ["the tenancy boundary —", "one per domain"] },
    { piece: "project-scoped RBAC", does: ["the team owns inside,", "nothing reaches across"] },
    { piece: "SCCs", does: ["what the domain's pods", "may do on the node"] },
    { piece: "ResourceQuota", does: ["the budget — one domain", "can't starve another"] },
  ],
  "Fuzzy boundaries and ownership vacuums: data nobody owns, modeled three ways by three teams.");

valueDiagram("17-value-data-product", "02", "Data as a product", "orange",
  "Products are discoverable, addressable, trustworthy, and self-describing — consumers find and depend on them without a broker.",
  [
    { piece: "Deployment + Service", does: ["the product as a", "deployable artifact"] },
    { piece: "schema registry", does: ["versioned contracts;", "rejects breaking changes"] },
    { piece: "OpenMetadata", does: ["catalog: discovery", "+ lineage graph"] },
    { piece: "CRDs", does: ["domain-specific types,", "declared like any object"] },
  ],
  "\"Dumb\" data products — renamed tables that can't serve, govern, or describe themselves; governance has nowhere to live.");

valueDiagram("17-value-self-serve", "03", "Self-serve data platform", "green",
  "Domains consume streaming, databases, scaling, and the mesh by declaration — they don't operate the substrate.",
  [
    { piece: "OperatorHub / OLM", does: ["curated capabilities,", "lifecycle-managed"] },
    { piece: "AMQ Streams / CNPG", does: ["Kafka + Postgres", "as custom resources"] },
    { piece: "KEDA", does: ["elastic products,", "scale to zero"] },
    { piece: "GitOps", does: ["the whole mesh,", "reproducible from Git"] },
  ],
  "Every domain reinvents the same infrastructure badly; ownership fragments into shadow platform teams.");

valueDiagram("17-value-governance", "04", "Federated computational governance", "red",
  "Global rules are enforced by the platform automatically, at the boundary — standards hold while ownership stays decentralized.",
  [
    { piece: "Service Mesh mTLS", does: ["authenticated, encrypted", "traffic — no app code"] },
    { piece: "progressive delivery", does: ["canary a contract;", "shift traffic by weight"] },
    { piece: "admission policy", does: ["every product: owner", "+ contract, enforced"] },
    { piece: "Prometheus/Tempo/Kiali", does: ["governance you can see:", "metrics, traces, topology"] },
  ],
  "Governance bolted on from outside never fits — or re-centralizes into an approval bottleneck (the mesh's own anti-pattern).");

/* ========== 7. PRINCIPLES → PIECES CLOSING DIAGRAM ========== */
(() => {
  const s = new SVG(1180, 620);
  s.title("The four principles, realized on OpenShift", "One picture: each principle and the platform pieces that deliver it");
  const fams = ["blue", "orange", "green", "red"];
  const data = [
    { p: "01  Domain ownership", pieces: ["Projects", "project RBAC", "SCCs", "ResourceQuota", "a DB per domain"] },
    { p: "02  Data as a product", pieces: ["Deployments + Services", "Routes", "schema registry", "OpenMetadata catalog", "lineage"] },
    { p: "03  Self-serve platform", pieces: ["OperatorHub / OLM", "GitOps", "AMQ Streams", "CloudNativePG", "KEDA"] },
    { p: "04  Federated governance", pieces: ["Service Mesh mTLS", "canary delivery", "admission policy", "Prometheus / Tempo", "Kiali"] },
  ];
  const cw = 250, gap = 20, x0 = 90, y0 = 80, ch = 400;
  data.forEach((d, i) => {
    const x = x0 + i * (cw + gap);
    const fam = fams[i];
    const f = require("./svglib.js").FAM[fam];
    s.rect(x, y0, cw, ch, fam);
    s.text(x + cw / 2, y0 + 30, d.p, { size: 13.5, anchor: "middle", weight: 700, fill: f.head });
    d.pieces.forEach((pc, j) => {
      const py = y0 + 60 + j * 64;
      s.plainRect(x + 18, py, cw - 36, 50, "#ffffff", f.stroke, { rx: 8 });
      s.text(x + cw / 2, py + 30, pc, { size: 11.5, anchor: "middle", weight: 700, fill: f.head });
    });
  });
  // base band: the platform
  s.plainRect(90, 500, 1000, 56, "#151515", "#151515", { rx: 8 });
  s.text(590, 534, "OpenShift — the substrate where all four principles find a home", { size: 14, anchor: "middle", weight: 700, fill: "#ffffff" });
  s.footer("The mesh is the network of products — plus the platform and standards that let them interoperate.");
  save("17-principles-to-pieces", s);
})();

/* ========== 8. RED HAT UBI + TRUSTED CONTENT (secure supply chain) ========== */
(() => {
  const s = new SVG(1180, 560);
  s.title("A trusted base for every data product", "Red Hat UBI + trusted content: the supply chain the platform gives each domain");
  // the build pipeline: base -> deps -> image -> signed -> deployed
  const stage = (x, w, fam, title, body) => {
    s.rect(x, 95, w, 120, fam);
    const f = require("./svglib.js").FAM[fam];
    s.text(x + w / 2, 122, title, { size: 12.5, anchor: "middle", weight: 700, fill: f.head });
    s.lines(x + 18, 150, body, { size: 10.5, fill: "#3a3a3a", lh: 16 });
  };
  stage(70, 250, "blue", "Red Hat UBI", ["the base image:", "ubi9/python-311", "freely redistributable,", "enterprise-maintained"]);
  s.arrow(320, 155, 360, 155, { color: "#5a5a5a", w: 1.8 });
  stage(360, 250, "green", "Trusted libraries", ["language deps from", "Red Hat / verified", "channels — known", "provenance, patched"]);
  s.arrow(610, 155, 650, 155, { color: "#5a8a3a", marker: "arrG", w: 1.8 });
  stage(650, 230, "orange", "Your data product", ["FastAPI / gRPC /", "Strawberry app layered", "on the trusted base"]);
  s.arrow(880, 155, 920, 155, { color: "#c97a3a", w: 1.8 });
  stage(920, 190, "red", "Signed & scanned", ["SBOM + signature;", "admission verifies", "before it runs"]);
  // value band — why it matters
  s.rect(70, 250, 1040, 110, "tan");
  s.text(90, 277, "WHY IT EARNS ITS PLACE", { size: 10, weight: 600, fill: "#8a7a5a" });
  s.lines(90, 300, [
    "Provenance you can prove — every layer traces to a maintained, signed source, not an anonymous public image.",
    "Patched at the base — CVE fixes flow from the UBI/trusted channel, so a rebuild re-bases the whole fleet of products.",
    "Governance hooks in — image signing + SBOM let admission policy reject anything unverified, mesh-wide.",
  ], { size: 11.5, fill: "#3a3a3a", lh: 24 });
  // tie to principles
  s.rect(70, 390, 1040, 95, "white");
  s.text(90, 417, "WHERE IT FITS THE MESH", { size: 10, weight: 600, fill: "#5a3a0a" });
  s.lines(90, 440, [
    "Self-serve platform: the trusted base is shared infrastructure every domain consumes — they inherit security, they don't each source it.",
    "Federated governance: signature + SBOM verification is a global rule the platform enforces at admission, automatically.",
  ], { size: 11.5, fill: "#3a3a3a", lh: 24 });
  s.footer("Domains build on a base they can trust and the platform can verify — security as a property they inherit, not a task they own.");
  save("17-trusted-supply-chain", s);
})();

console.log("DONE");
