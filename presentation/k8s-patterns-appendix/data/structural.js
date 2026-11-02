// data/structural.js: Structural family (chapters 06-09).
// Source: _appendix/k8s-patterns/0{6..9}-*.md. Voice: lgtm-professional-voice.

"use strict";

module.exports = {
  divider: {
    code: "02",
    title: "Structural Patterns",
    subtitle: "How containers inside one Pod compose: gated, alongside, translating, or brokering.",
    notes: "The structural family covers four ways a Pod's containers can relate to each other: gated by an init container that must finish first, running alongside as a native sidecar with its own start and stop order, translating a format as a narrower kind of sidecar, or brokering an outbound connection as an ambassador. Each pattern reuses the same two primitives, a shared network namespace and an optional shared volume, for a different purpose. What to show: these patterns answer a different question than the foundational family does, not whether a container behaves well on its own, but how two containers in the same Pod divide responsibility. Fallback: if time is tight, Sidecar and Ambassador are the two most heavily tested on the CKAD exam and worth covering live.",
  },
  slides: [
    // ---- 06 Init Container ----
    {
      t: "bullets",
      eyebrow: "STRUCTURAL · INIT CONTAINER",
      title: "Init Container",
      bullets: [
        "The kubelet runs every **init container** to completion, in order, before it starts a single main container, a stronger guarantee than retries or health checks inside an app could provide.",
        "`notification-service`'s **migrate** init container runs `alembic upgrade head` from the same image as the app, so the schema it migrates to is always the one the app's own models declare.",
        "A failed migration shows as **Init:Error**, then **Init:CrashLoopBackOff**; the main container sits `Waiting: PodInitializing` the entire time, since it hasn't been created yet.",
        "Alembic's migration is **idempotent**, so scaling to three replicas or rolling to a new revision reruns it safely: the first Pod to start applies the work, the rest find it already done.",
      ],
      notes: "notification-service graduated off Base.metadata.create_all because its schema needs to change over time, something create_all can't express. What to show: kubectl get pods -w during a missing-Postgres apply, watching Init:Error settle into Init:CrashLoopBackOff while the main container never gets created. Fallback: the runnable example already captures that sequence end to end in its README.",
    },
    {
      t: "code",
      eyebrow: "STRUCTURAL · INIT CONTAINER",
      title: "The migration gate",
      lang: "yaml · deployment",
      code: [
        "initContainers:",
        "  - name: migrate",
        "    image: notification-service:v1",
        "    imagePullPolicy: Never",
        "    command: [\"alembic\", \"upgrade\", \"head\"]",
        "    env:",
        "      - name: PG_HOST",
        "        value: patterns-postgres.patterns.svc.cluster.local",
        "      # ...PG_PORT, PG_USER, PG_PASSWORD",
      ],
      caption: "Same image, same connection settings as the app container that follows it: no separate migration image to keep in sync.",
      notes: "The command differs from the app's own uvicorn entrypoint, but the image and database settings are identical, since both come from the same build artifact. Alembic's env.py opens a connection and fails immediately if Postgres isn't reachable, unlike the app's own retrying init_schema(). What to show: the container's own exit code is the only thing that gates the main container, nothing else about its output matters. Fallback: mention splitting a wait-for-dependency init container ahead of the migration when a driver's failure is less legible than Alembic's.",
    },
    {
      t: "diagram",
      eyebrow: "STRUCTURAL · INIT CONTAINER",
      title: "The exit code gate",
      png: "appendix-06-init-container",
      caption: "Figure: the init container's exit code is the only gate; zero unblocks the main container, nonzero leaves the Pod waiting indefinitely.",
      notes: "The figure traces one Pod through PodInitializing twice: once while migrate runs, once while the main container is created after it exits zero. What to show: the main container doesn't exist as an object yet during the first PodInitializing, so there's nothing to probe or log until migrate succeeds. Fallback: the same figure and its editable source live on the reference site.",
    },
    {
      t: "bullets",
      eyebrow: "STRUCTURAL · INIT CONTAINER",
      title: "Run it and the exam",
      bullets: [
        "**Run:** apply notification-service's Deployment before its Postgres exists to surface Init:Error and Init:CrashLoopBackOff, then supply Postgres and watch the Pod reach Ready.",
        "**Observe:** kubectl get pods -w shows the state transitions live; kubectl describe pod's initContainerStatuses records the last exit code and reason.",
        "**CKAD domain:** Application Design and Build (20%).",
        "**Drill:** kubectl get pod -n patterns -l app.kubernetes.io/name=notification-service -o jsonpath='{.status.initContainerStatuses[0].state}'",
      ],
      notes: "The drill reads the same field the live kubectl get pods -w output narrates, just as a single JSON snapshot instead of a stream. What to show: run the drill against both a healthy Pod and one still stuck on Init:CrashLoopBackOff, since the state object's shape changes between the two. Fallback: the example's README has the drill output captured at each stage of the walkthrough.",
    },

    // ---- 07 Sidecar ----
    {
      t: "bullets",
      eyebrow: "STRUCTURAL · SIDECAR",
      title: "Sidecar",
      bullets: [
        "Two containers in one Pod share a **network namespace** by definition: one reaches the other at `localhost`, with no Service, no DNS lookup, and no network policy in between.",
        "`shipping-service`'s **probe-tailer** polls `/health` and `/healthz` over `127.0.0.1` and appends each result to a shared `emptyDir` volume, with zero changes to the app itself.",
        "The case for a separate container is **isolation**: a different language, a different release cadence, a bug that can't corrupt the main process's own memory.",
        "An ordinary second container under `containers:` starts and stops with no ordering guarantee relative to the main one, the problem the **native sidecar** mechanism fixes.",
      ],
      notes: "probe-tailer's payload stays simple so the Pod lifecycle mechanics stay the visible thing; a production sidecar usually tails real logs for Fluent Bit or a vector agent instead. What to show: kubectl exec into probe-tailer and tail the shared log file to confirm it's reading the app over localhost, not through a Service. Fallback: the example's README has the exec command and a sample of the tailed output.",
    },
    {
      t: "code",
      eyebrow: "STRUCTURAL · SIDECAR",
      title: "Native sidecar: restartPolicy Always",
      lang: "yaml · deployment",
      code: [
        "initContainers:",
        "  - name: probe-tailer",
        "    restartPolicy: Always  # the native sidecar switch",
        "    image: registry.../python-minimal:10.2",
        "    # starts before the main container,",
        "    # never blocks it, never expected to exit",
      ],
      caption: "restartPolicy: Always on an initContainers entry starts the sidecar first and stops it last, the reverse of an ordinary second container.",
      notes: "Native sidecars reached beta in Kubernetes 1.29 and went stable in 1.33; the cluster profile here runs well past that line, so every behavior is available as-is. The kubelet moves on to the main container once the sidecar is considered started, not once it exits, because it isn't supposed to exit. What to show: kubectl get pods -w during startup, watching probe-tailer reach Running while the main container still reads PodInitializing. Fallback: the chapter's figure makes the same point without a live cluster.",
    },
    {
      t: "bullets",
      eyebrow: "STRUCTURAL · SIDECAR",
      title: "Resource accounting and shutdown order",
      bullets: [
        "An ordinary init container's requests are reserved only while it runs. A **native sidecar** breaks that: restartPolicy: Always keeps its requests reserved for the Pod's whole life.",
        "On shutdown, native sidecars stop **last**: the main container gets SIGTERM first, the sidecar stays reachable until it's gone, then the kubelet terminates the sidecar too.",
        "That ordering protects two dependencies: a proxy the app needs ready before its first outbound call, and a logging sidecar that needs to still be alive for the app's last burst of output.",
        "A native sidecar still counts toward a Pod's READY column (2/2), but it does **not** count toward a Job's completion: only the main container finishing matters there.",
      ],
      notes: "probe-tailer's own requests, 20 millicores and 32Mi, stay modest because they're paid for the Pod's whole lifetime rather than just its startup, a cost a heavier sidecar like a full mesh proxy has to size the node pool for explicitly. What to show: delete the Pod while watching both containers' states, confirming probe-tailer terminates after shipping-service, not alongside it. Fallback: the Job-completion distinction applies more directly to the Behavioral family's BatchJob pattern, worth a forward pointer if asked.",
    },
    {
      t: "diagram",
      eyebrow: "STRUCTURAL · SIDECAR",
      title: "Brackets the app's lifetime",
      png: "appendix-07-sidecar",
      caption: "Figure: restartPolicy: Always inverts the usual race, bracketing the app's whole lifetime instead of merely running alongside it.",
      notes: "The figure lines up both containers' timelines: the sidecar's Running state starts before the app's and ends after it. What to show: point at the two SIGTERM arrows landing at different moments, the detail that distinguishes a native sidecar from an ordinary second container. Fallback: the reference site hosts the same figure with its editable Excalidraw source.",
    },
    {
      t: "bullets",
      eyebrow: "STRUCTURAL · SIDECAR",
      title: "Run it and the exam",
      bullets: [
        "**Run:** deploy shipping-service with probe-tailer as a native sidecar, confirm it reaches Running before the main container, then delete the Pod while watching both containers' states.",
        "**Observe:** kubectl exec into probe-tailer and tail the shared log file; the sidecar keeps answering after the main container has already received SIGTERM.",
        "**CKAD domain:** Application Design and Build (20%).",
        "**Drill:** kubectl get pod -n patterns -l app.kubernetes.io/name=shipping-service -o jsonpath='{.spec.initContainers[0].restartPolicy}'",
      ],
      notes: "The drill confirms the switch that makes the whole pattern work; an empty result means the field was never set and the container is an ordinary init container instead. What to show: run the drill, then remove restartPolicy from the manifest and rerun it to see the field disappear. Fallback: the chapter's agent prompt walks through exactly that removal and its effect on the rollout.",
    },

    // ---- 08 Adapter ----
    {
      t: "bullets",
      eyebrow: "STRUCTURAL · ADAPTER",
      title: "Adapter",
      bullets: [
        "Adapter is narrower than Sidecar: every adapter is a sidecar, but the defining trait is a **format obligation**, reading what the main container already produces and re-emitting the same fact in a required shape.",
        "`shipping-service` reports health as **JSON**, fine for curl, jq, and kubectl's own probe, but not something a Prometheus scraper can ingest: it expects line-based exposition text, not a status field.",
        "The **metrics-adapter** sidecar polls `/healthz` over localhost and re-emits the same readiness fact as a Prometheus gauge, `shipping_service_up`, on its own `:9100/metrics` port.",
        "The adapter invents nothing and changes no behavior. It only changes the wire format, which is why the translation belongs in its own container instead of inside the app.",
      ],
      notes: "Teaching shipping-service to speak Prometheus natively would mean adding a metrics library and a new endpoint to every service needing the same translation, for a concern unrelated to shipping logic. What to show: curl both /healthz and :9100/metrics side by side to see the same underlying fact in two different wire formats. Fallback: the example's README has both responses captured together.",
    },
    {
      t: "code",
      eyebrow: "STRUCTURAL · ADAPTER",
      title: "Translating JSON into exposition text",
      lang: "python · adapter",
      code: [
        "APP_URL = \"http://127.0.0.1:8080/healthz\"",
        "",
        "def do_GET(self):",
        "    up = 1 if poll(APP_URL) == 200 else 0",
        "    # HELP shipping_service_up ready flag",
        "    # TYPE shipping_service_up gauge",
        "    print(f\"shipping_service_up {up}\")",
      ],
      caption: "Every scrape triggers a fresh poll of /healthz; the adapter hardcodes one upstream and one metric by design, not as a shortcut.",
      notes: "A Content-Type of text/plain; version=0.0.4 matters as much as the body itself: a scraper strict about content negotiation can reject a correct-looking response missing that header. What to show: curl -s http://127.0.0.1:9100/metrics next to curl -s http://127.0.0.1:8080/healthz to see the same readiness fact in both formats. Fallback: the chapter's prometheus.io/scrape annotations are the convention a Prometheus Operator setup would use to discover this port.",
    },
    {
      t: "diagram",
      eyebrow: "STRUCTURAL · ADAPTER",
      title: "Same fact, new syntax",
      png: "appendix-08-adapter",
      caption: "Figure: an adapter sidecar translates shipping-service's JSON health body into Prometheus exposition text for an external scraper.",
      notes: "The figure shows the scraper reading only the adapter's translated port, never touching the app's own /healthz directly. What to show: the adapter never changes what's true about shipping-service, only the syntax a scraper needs to read it in. Fallback: scale Postgres to zero and watch shipping_service_up follow /healthz down, without the adapter itself failing.",
    },
    {
      t: "bullets",
      eyebrow: "STRUCTURAL · ADAPTER",
      title: "Run it and the exam",
      bullets: [
        "**Run:** deploy shipping-service with metrics-adapter as a second container, compare /healthz's JSON against /metrics's Prometheus text for the same readiness fact.",
        "**Observe:** scale Postgres to zero and watch shipping_service_up follow the app's real state down to 0, without the adapter container crashing or restarting.",
        "**CKAD domain:** Application Observability and Maintenance (15%).",
        "**Drill:** kubectl exec -n patterns deploy/shipping-service -c metrics-adapter -- curl -s localhost:9100/metrics",
      ],
      notes: "The drill execs into the adapter container directly, the same way a troubleshooter would check a sidecar's own output without going through the Service at all. What to show: run the drill before and after scaling Postgres to zero, since the metric's value is the whole demonstration. Fallback: the example's README has both outputs captured together for comparison.",
    },

    // ---- 09 Ambassador ----
    {
      t: "bullets",
      eyebrow: "STRUCTURAL · AMBASSADOR",
      title: "Ambassador",
      bullets: [
        "An ambassador sidecar hides **where** a dependency lives, not whether it exists: the main container always talks to a fixed `localhost` address, and the ambassador decides what's really on the other end.",
        "`shipping-service`'s own config defaults already point at `127.0.0.1:5432`, written for local development; the example's Deployment sets **zero Postgres environment variables** and the app still connects.",
        "**postgres-ambassador** is a plain TCP relay with no Postgres protocol awareness: it opens a second connection to the real `patterns-postgres` Service and copies bytes in both directions.",
        "Moving the target is a **one-container edit**: kubectl set env on the ambassador's UPSTREAM_HOST changes where the connection goes, with zero changes to the application's own manifest.",
      ],
      notes: "The pattern decouples the app's configuration from the cluster's real topology, the same slot a connection pooler, a credential-rotation proxy, or an Istio sidecar fills. What to show: kubectl set env against only the ambassador container, then watch /healthz fail within one probe interval while the application container itself shows nothing wrong. Fallback: the example's README has the before-and-after kubectl describe pod output.",
    },
    {
      t: "code",
      eyebrow: "STRUCTURAL · AMBASSADOR",
      title: "A protocol-blind byte pipe",
      lang: "python · ambassador",
      code: [
        "async def handle(client_reader, client_writer):",
        "    server_reader, server_writer = await (",
        "        asyncio.open_connection(",
        "            UPSTREAM_HOST, UPSTREAM_PORT))",
        "    await asyncio.gather(",
        "        pipe(client_reader, server_writer),",
        "        pipe(server_reader, client_writer),",
        "    )",
      ],
      caption: "The ambassador never parses or stores shipping-service's credentials; they travel end to end inside the relayed TCP stream.",
      notes: "Bound to 127.0.0.1 rather than 0.0.0.0 by design: a Pod IP is routable from anywhere in the cluster network, so binding every interface would turn a scoped convenience into an open relay onto patterns-postgres. What to show: the listener's loopback bind is the one line that makes the whole pattern safe to run. Fallback: a more capable ambassador could terminate TLS or inject rotated credentials on top of this same shape.",
    },
    {
      t: "bullets",
      eyebrow: "STRUCTURAL · AMBASSADOR",
      title: "Failing fast, and the mesh parallel",
      bullets: [
        "If the ambassador's own connection to the upstream fails, it closes the client connection immediately: asyncpg on the app side sees a connection actively refused, not a hang.",
        "That fast, visible failure is exactly what shipping-service's own readiness check is built to catch within one probe interval, with no retry logic required on the ambassador's own part.",
        "`order-service`'s Istio-injected Pod fills the **same slot**, automated: `istio-proxy` intercepts outbound connections via iptables rather than a hand-dialed localhost address.",
        "A hand-rolled ambassador makes that slot inspectable: one Python script, one upstream address, every rule visible directly in the Pod spec, unlike an automatically injected mesh proxy.",
      ],
      notes: "pool_pre_ping=True on shipping-service's own SQLAlchemy engine guards against a connection going stale while idle in the pool, a separate concern from what the ambassador changes on a first connection attempt. What to show: repoint UPSTREAM_HOST at a Service that doesn't exist and read /healthz failing while kubectl describe pod for the application container shows nothing wrong. Fallback: point at the Istio parallel as the generalized, automated version of the same mechanism.",
    },
    {
      t: "diagram",
      eyebrow: "STRUCTURAL · AMBASSADOR",
      title: "One fixed address, one movable target",
      png: "appendix-09-ambassador",
      caption: "Figure: shipping-service always connects to 127.0.0.1:5432; only the ambassador's upstream, not the app's configuration, ever changes.",
      notes: "The figure separates the app's fixed local target from the ambassador's configurable real one, the whole value of the decoupling in one picture. What to show: trace the credentials flowing through the ambassador unmodified, since it relays bytes without ever parsing the protocol. Fallback: the same figure and its editable source are on the reference site.",
    },
    {
      t: "bullets",
      eyebrow: "STRUCTURAL · AMBASSADOR",
      title: "Run it and the exam",
      bullets: [
        "**Run:** deploy shipping-service with zero Postgres environment variables and a postgres-ambassador sidecar, confirm /healthz succeeds, then repoint only the ambassador's upstream.",
        "**Observe:** /healthz fails within one probe interval after the repoint, while kubectl describe pod shows the application container itself untouched and correct.",
        "**CKAD domain:** Application Design and Build (20%).",
        "**Drill:** kubectl get deployment shipping-service -n patterns -o jsonpath='{.spec.template.spec.containers[0].env}' (confirm it's empty)",
      ],
      notes: "An empty result from the drill is the whole point: the application container carries no Postgres-aware configuration at all, because the ambassador owns that decision entirely. What to show: run the drill before and after the UPSTREAM_HOST change, since the application's own env array never moves. Fallback: the example's README has the full repoint-and-recover sequence.",
    },
  ],
};
