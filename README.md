# Minikube Tutorial on Fedora

A hands-on tutorial for installing and using
[minikube](https://minikube.sigs.k8s.io/) on Fedora 44 with
`kubectl` and `helm`, plus reference material for
[Istio](https://istio.io/) and (optionally) [KEDA](https://keda.sh/)
with the HTTP add-on.

The published tutorial lives at:
**<https://patterncatalyst.github.io/minikube-on-fedora/>**

---

## What this tutorial teaches

A developer who works on Fedora with Podman, podman-compose, and
Podman Desktop will, by the end:

- Install minikube on Fedora 44 from standard repositories where
  possible
- Start a local Kubernetes cluster with the podman driver
  (rootless, containerd runtime)
- Deploy applications imperatively with `kubectl` and
  declaratively with helm charts (using public charts and
  authoring a small one)
- Expose services, manage persistent volumes, run multiple
  clusters via profiles, and use minikube's addons
- Use the Istio service mesh and KEDA event-driven autoscaling
  on a local cluster as a reference for applying them elsewhere

Sections §11 (Istio) and §12 (KEDA) are skippable for readers
who only want the core minikube workflow.

## Audience

**Primary**: a working developer on Fedora 44 with paragraph-level
familiarity with Kubernetes concepts (Pod, Deployment, Service)
who wants a single coherent reference for getting work done on a
local cluster.

**Secondary**: developers on Fedora derivatives (RHEL, Rocky, Alma);
developers on macOS who occasionally need local Kubernetes
(advisory notes only, not a tested platform); readers learning
helm/Istio/KEDA who want a low-friction local environment.

**Not for**: complete Kubernetes newcomers (read the upstream
"Learn Kubernetes Basics" walkthrough first), production cluster
operators, or Windows users (WSL not tested).

## Project layout

```
.
├── _config.yml                       ← Jekyll site config
├── _docs/                            ← Tutorial sections (00-outline.md, 01-prerequisites.md, …, 16-examples.md)
├── _example_pages/                   ← Per-example Jekyll pages (generated from examples/*/README.md)
├── _includes/, _layouts/             ← HTML wrappers
├── _plans/
│   ├── reconciliation-plan.md        ← Audit trail: what's verified vs. unverified
│   └── prd-reconciliation.md         ← What shipped vs. what was planned, with rationale
├── assets/
│   ├── css/site.css
│   ├── diagrams/                     ← Paired .svg (rendered) + .excalidraw (editable)
│   └── screenshots/                  ← Reference screenshots (Kiali, Strimzi, etc.)
├── examples/                         ← Runnable code per tutorial section
│   └── NN-name/
│       ├── README.md                 ← Narrated walkthrough (source of truth)
│       ├── demo.sh                   ← Strict end-to-end script (also serves as test)
│       ├── cleanup.sh                ← Explicit teardown (where applicable)
│       └── manifests/, values/, …    ← Manifests, helm values, source code
├── onboarding/                       ← Repo orientation for new contributors
│   ├── README.md                     ← Onboarding navigation hub
│   ├── GETTING-STARTED.md            ← Skeleton setup instructions
│   ├── LESSONS-LEARNED.md            ← Hard-won empirical guidance
│   └── STARTING-WITH-CLAUDE.md       ← How to work with Claude on this project
├── scripts/
│   ├── lib/_helpers.sh
│   ├── test-all-examples.sh          ← Aggregator across every example
│   ├── test-NN-name.sh               ← (optional) maintainer test wrappers
│   ├── sync-example-pages.sh         ← Regenerates _example_pages/ from examples/*/README.md
│   ├── check-cross-references.sh    ← Validates internal Jekyll links
│   └── editorial-audit.sh            ← Advisory greps for known problem patterns
├── PRD.md                            ← Product requirements doc
├── CONTRIBUTING.md
├── LICENSE
└── README.md                         ← (you are here)
```

`examples/` is excluded from the published Jekyll site via
`_config.yml` (`exclude: examples/`). The runnable code lives in
the repo only; the **published narrative for each example** is
generated as a Jekyll page under `_example_pages/` and rendered
at `/examples/NN-name/` on the site.

## Getting started

New to the repo? Start with **[`onboarding/`](onboarding/)** — it
has the orientation docs for working on this project:

- **[`onboarding/GETTING-STARTED.md`](onboarding/GETTING-STARTED.md)**
  — initial setup; how to run the site and the examples locally
- **[`onboarding/LESSONS-LEARNED.md`](onboarding/LESSONS-LEARNED.md)**
  — empirical guidance from building this tutorial; pitfalls,
  conventions, what works
- **[`onboarding/STARTING-WITH-CLAUDE.md`](onboarding/STARTING-WITH-CLAUDE.md)**
  — how the human-AI collaboration was structured; useful if
  you're continuing or replicating the working pattern

## Running the site locally

The site is a Jekyll project. To build and view it locally:

```bash
bundle install
bundle exec jekyll serve --baseurl ""
```

Open <http://localhost:4000/>. The `--baseurl ""` override
makes URLs resolve from the root during local development;
production uses the `/minikube-on-fedora` prefix.

If `bundle install` fails on Fedora with native extension
errors, install the build deps once:

```bash
sudo dnf install -y ruby ruby-devel @development-tools
```

## Running the examples

Each tutorial section that includes runnable code has a matching
directory under `examples/`. To run one:

```bash
cd examples/06-deploy-nginx-kubectl   # or whichever
./demo.sh
```

To run every example and tally results:

```bash
./scripts/test-all-examples.sh
```

The aggregator does not fail-fast — it runs every example even
if earlier ones fail, then reports pass/fail per script at the
end.

The published per-example pages at `/examples/NN-name/` are
generated from the `README.md` of each `examples/NN-name/`
directory. To regenerate them after editing a README:

```bash
./scripts/sync-example-pages.sh
```

Commit the regenerated `_example_pages/*.md` files alongside
the README change.

## Quality checks

Two audit scripts maintain ongoing quality on documentation:

```bash
./scripts/check-cross-references.sh   # validates internal Jekyll links resolve
./scripts/editorial-audit.sh          # advisory greps for known problem patterns
```

The first exits non-zero if any link is broken (useful in CI);
the second is advisory only — it surfaces "we" voice, stale
TODOs, kramdown-collision patterns, `{% raw %}`-wrapped URLs,
and duplicate shell flags within a single command.

## Verification status

Honest accounting of what's been tested vs. what's claimed
lives in
[`_plans/reconciliation-plan.md`](_plans/reconciliation-plan.md).
Default status for any new claim is `unverified`; promotion to
`verified` requires a real test run by a human on Fedora 44.

As of project close-out, **107 facts are verified**.

What shipped vs. what was originally planned — including the
five major divergences (macOS dropped, UBI instead of
Hummingbird, vendor-neutral relaxed for §13, "we" voice not
strictly avoided, Podman not version-pinned) — is documented in
[`_plans/prd-reconciliation.md`](_plans/prd-reconciliation.md).

## Contributing

This started as a personal/team reference. Issues and pull
requests are welcome at
[github.com/patterncatalyst/minikube-on-fedora](https://github.com/patterncatalyst/minikube-on-fedora).

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the conventions
used in this repo (UBI base images, `127.0.0.1` not
`localhost`, idempotent demo scripts with cleanup traps,
diagnostic dumps on failure, single-line shell commands for
zsh paste safety, etc.).

## License

Apache License, Version 2.0. See [`LICENSE`](LICENSE).

The 2023 predecessor of this tutorial lives at
[github.com/patterncatalyst/minikube](https://github.com/patterncatalyst/minikube)
for historical reference; it covers Kubernetes 1.22 and the
docker / containerd driver path, which are stale for current
work.
