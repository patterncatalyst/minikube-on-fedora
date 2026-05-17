# Minikube Tutorial on Fedora

A hands-on tutorial for installing and using [minikube][minikube] on
Fedora 44 with `kubectl` and `helm`, plus reference material for
[Istio][istio] and (optionally) [KEDA][keda] with the HTTP add-on.

The published tutorial lives at:
**https://patterncatalyst.github.io/minikube-on-fedora/**

[minikube]: https://minikube.sigs.k8s.io/
[istio]: https://istio.io/
[keda]: https://keda.sh/

---

## What this tutorial teaches

A developer who works on Fedora with Podman, podman-compose, and
Podman Desktop will, by the end:

- Install minikube on Fedora 44 from standard repositories where
  possible
- Start a local Kubernetes cluster with the podman driver
- Deploy applications imperatively with `kubectl` and declaratively
  with helm charts (using public charts and authoring a small one)
- Expose services, manage persistent volumes, run multiple
  clusters via profiles, and use minikube's addons
- Use the Istio service mesh and KEDA HTTP-driven autoscaling on a
  local cluster as a reference for applying them elsewhere

Sections 11 (Istio) and 12 (KEDA) are skippable for readers who
only want the core minikube workflow.

## Audience

Primary: a working developer on Fedora 44 with paragraph-level
familiarity with Kubernetes concepts (Pod, Deployment, Service)
who wants a single coherent reference for getting work done on a
local cluster.

Secondary: developers on Fedora derivatives (RHEL, Rocky, Alma),
developers on macOS who occasionally need local Kubernetes
(advisory notes only, not a tested platform), and readers learning
helm/istio/KEDA who want a low-friction local environment.

Not for: complete Kubernetes newcomers (read the upstream "Learn
Kubernetes Basics" walkthrough first), production cluster
operators, or Windows users (WSL not tested).

## Repository layout

```
.
├── _config.yml                  ← Jekyll site config
├── _docs/                       ← Tutorial sections (00-outline.md, 01-prerequisites.md, …)
├── _plans/
│   └── reconciliation-plan.md   ← Audit trail: what's verified vs. unverified
├── _includes/, _layouts/        ← HTML wrappers
├── assets/
│   ├── css/site.css
│   └── diagrams/                ← Paired .svg (rendered) + .excalidraw (editable)
├── examples/                    ← Runnable code per tutorial section
│   └── NN-name/
│       ├── README.md            ← Narrated walkthrough
│       ├── demo.sh              ← Strict end-to-end script (also serves as test)
│       └── *.yaml               ← Manifests, helm values, etc.
├── scripts/
│   ├── lib/_helpers.sh
│   ├── test-all-examples.sh     ← Aggregator across every example
│   └── test-NN-name.sh          ← (optional) maintainer test wrappers
├── PRD.md                       ← Product requirements doc
├── LESSONS-LEARNED.md           ← Hard-won empirical guidance
├── GETTING-STARTED.md           ← Skeleton setup instructions (carryover)
└── STARTING-WITH-CLAUDE.md      ← How to work with Claude on this project
```

`examples/` is excluded from the published site by `_config.yml`
(`exclude: examples/`) — it lives in the repo as runnable code,
not as web content.

## Running the site locally

The site is a Jekyll project. To build and view it locally:

```bash
bundle install
bundle exec jekyll serve --baseurl ""
```

Open http://localhost:4000/ — `--baseurl ""` overrides the
production `/minikube-on-fedora` prefix so URLs resolve from the
root during dev.

If `bundle install` fails on Fedora with native extension errors,
install the build deps once:

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

The aggregator does not fail-fast — it runs every example even if
earlier ones fail, then reports pass/fail per script at the end.

## Verification status

Honest accounting of what's been tested vs. what's claimed lives
in [`_plans/reconciliation-plan.md`][plan]. Default status for any
new claim is `unverified`; promotion to `verified` requires a real
test run by a human.

[plan]: ./_plans/reconciliation-plan.md

## Contributing

This started as a personal/team reference. Issues and pull
requests are welcome at
[github.com/patterncatalyst/minikube-on-fedora][repo].

[repo]: https://github.com/patterncatalyst/minikube-on-fedora

## License

Apache License, Version 2.0. See [`LICENSE`](./LICENSE).

The 2023 predecessor of this tutorial lives at
[github.com/patterncatalyst/minikube][old-repo] for historical
reference; it covers Kubernetes 1.22 and the docker / containerd
driver path, which are stale for current work.

[old-repo]: https://github.com/patterncatalyst/minikube
