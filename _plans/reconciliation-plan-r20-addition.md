# Reconciliation plan addition — r20 (capstone skeleton)

> Merge instructions: append the entry below to Section D of
> `_plans/reconciliation-plan.md`, after the r19 entry.

---

- **r20** (capstone skeleton — directory structure, helm umbrella
  chart scaffolding, profile setup, architecture diagram, §17
  prose introduction) — first implementation iteration of the
  capstone after r19's planning. No services deployed yet; the
  goal is to land the scaffolding cleanly so r21+ can fill in
  the actual implementation.

  **What r20 ships:**

  - `_docs/17-capstone.md` — §17 prose covering the data-mesh
    conceptual background (what is it, the four principles per
    Dehghani, why it maps to Kubernetes), architecture
    overview with embedded diagram, the five services table,
    platform components table, profile setup recipe, and a
    preview of the r21–r30 iteration plan. ~280 lines
  - `assets/diagrams/17-capstone-data-mesh.svg` — three-tier
    architecture diagram (clients, mesh, platform) showing
    all five services with Istio sidecars, the GraphQL
    federation gateway, and the eight platform components
    (Strimzi, Apicurio, OpenMetadata, Postgres, KEDA,
    Prefect, observability stack, istiod). Protocol legend
    distinguishes REST (solid blue), gRPC (dashed green),
    GraphQL (dotted orange), Kafka (solid red), and OTLP
    (dotted purple). 1200×760 viewBox — larger than the
    other diagrams because the capstone has more components
    to show
  - `assets/diagrams/17-capstone-data-mesh.excalidraw` —
    minimal Excalidraw source stub (three lane backgrounds
    + labels + a note pointing at the SVG as authoritative).
    Designed as a starting point for further editing in
    Excalidraw rather than a complete reproduction of the SVG
  - `examples/17-capstone/README.md` — operational entry
    point that becomes the §17 example page via the sync
    script
  - `examples/17-capstone/charts/capstone/Chart.yaml` —
    helm umbrella chart definition with no dependencies yet
    (dependencies arrive incrementally per the
    comment-documented iteration schedule)
  - `examples/17-capstone/charts/capstone/values.yaml` —
    feature flags for every platform component and every
    service. Resource defaults sized for the 24 GB / 16 CPU
    profile. Globals section configures the OTLP endpoint,
    Apicurio endpoint, Kafka bootstrap, and Postgres
    connection target consistently for all subcharts
  - `examples/17-capstone/scripts/setup-capstone-profile.sh`
    — creates (or replaces) the `capstone` minikube profile.
    Pre-flight checks for minikube + podman in PATH and the
    inotify-limits tweak; warns (interactively) if other
    minikube profiles are running and competing for RAM.
    Idempotent — re-running on an existing healthy profile
    just switches kubectl context
  - `examples/17-capstone/scripts/teardown.sh` — stops the
    profile (preserving state) or deletes it entirely with
    `--remove-profile`
  - Placeholder `.gitkeep` files in `proto/`, `postman/`,
    `demos/`, `services/` — directories that get filled in
    r21+

  **Verification status for r20 deliverables**:
  - `examples/17-capstone/scripts/setup-capstone-profile.sh`
    runs on Fedora 44 → **unverified until user reports back**
  - `examples/17-capstone/scripts/teardown.sh` runs on Fedora
    44 → **unverified until user reports back**
  - §17 prose renders cleanly via Jekyll → **unverified until
    deployed-preview review**
  - Architecture diagram renders in Jekyll → **unverified
    until deployed-preview review**

  Adds approximately 4 verification rows to Section B (pending
  user confirmation of the setup script execution and the
  rendered §17 page).

  **What r20 deliberately does NOT include:**
  - Any Containerfiles, Python source, or proto files
  - Working helm subcharts (only the umbrella chart's
    `Chart.yaml` + `values.yaml`)
  - Strimzi/KEDA/Istio operator installations (deferred to
    r21+ where they're first needed)
  - Postman collection (r29)
  - Demo scripts (r25+)
  - Updates to `_docs/16-examples.md` to add §17 to the "what's
    NOT an example" list — §17 *is* an example, just a big
    one. The §17 example page will appear in the §16 hub
    automatically once the user runs `./scripts/sync-example-pages.sh`

  **Notes for r21:**
  - Establish the per-service skeleton pattern with
    order-service: Containerfile (UBI 9-based per
    CONTRIBUTING.md), pyproject.toml with pinned versions,
    FastAPI app structure, helm subchart, health probes,
    Postgres schema migration approach
  - Every subsequent service (r22) follows the same pattern,
    so r21's prose includes the "this is the template every
    service follows" framing
  - Consider whether to write a `scripts/create-service.sh`
    scaffold script in r21 to make r22's work mechanical

  **Open question for the user (resolve before r21):**

  The CloudNativePG operator is the default choice for the
  shared Postgres cluster per the r19 decisions. Confirm or
  override: any preference for a different Postgres operator
  (Zalando, Crunchy Data, bitnami chart)? Default proceeds
  with CloudNativePG.

  Verified row count holds at **107** (no §17 work has been
  verified yet — the scaffolding doesn't actually do anything
  testable beyond the profile creation).
