---
title: Examples
order: 16
description: Index of all runnable examples in the tutorial. Each example has its own dedicated page and a runnable demo.sh script in the repo.
duration: varies
---

Every tutorial section that introduces a runnable workload has a
matching directory under `examples/` in the repo, with a narrated
walkthrough (`README.md`), an end-to-end demo script (`demo.sh`),
and the manifests/values/source needed to run it.

This page is the index. Each example below links to a dedicated
page rendered from its README, plus a direct link to the source
directory on GitHub so you can clone, copy, or fork it on its own.

## How to run an example

Each example is self-contained and idempotent. The basic shape is
always:

```bash
cd examples/NN-name
./demo.sh
```

`demo.sh` includes pre-flight checks (correct minikube profile,
required tools in PATH, kernel limits sufficient where applicable)
and a cleanup trap so re-runs are safe. If anything fails, the
script exits non-zero with a diagnostic dump of relevant Pod
state, recent events, and logs.

To run **every** example and tally pass/fail:

```bash
./scripts/test-all-examples.sh
```

The aggregator does not fail-fast — it runs every example even
when earlier ones fail, then reports pass/fail per script at the
end.

## All examples

The list below is generated from `_example_pages/*.md` and sorted
by tutorial-section order. Each example links to its dedicated
page (rendered from the example's `README.md`) and to the source
directory on GitHub.

{% assign sorted = site.example_pages | sort: "order" %}
{% for ex in sorted %}
### {{ ex.title }}

[**Read the walkthrough →**]({{ ex.url | relative_url }})

Source: [`{{ ex.example_dir }}/`](https://github.com/patterncatalyst/minikube-on-fedora/tree/main/{{ ex.example_dir }})

{% if ex.description %}{{ ex.description }}{% endif %}

{% endfor %}

## Verification status

The examples are the canonical record of "what's been tested vs.
what's claimed". Each example's verification status against
Fedora 44 is tracked in
[`_plans/reconciliation-plan.md`](https://github.com/patterncatalyst/minikube-on-fedora/blob/main/_plans/reconciliation-plan.md)
(viewable in the repo). The default status for any new claim is
`unverified`; promotion to `verified` requires a real test run by
a human on Fedora 44.

As of project close-out (r17), the count of verified rows stood
at **107**.

## What's NOT an example

Some tutorial sections introduce concepts or commands without
ever bundling a runnable example:

- **§1** Prerequisites — reads the host state, doesn't deploy
- **§2** Tooling install — installs binaries, doesn't deploy
- **§5** Addons + dashboard — uses `minikube addons` commands;
  exploratory, no canonical demo
- **§10** Editor/shell/terminal — installs k9s, kubectx, etc.;
  no Kubernetes workload to demo
- **§13** Alternatives to minikube — comparative prose only
- **§14** FAQ + cleanup recipes — recipes you copy-paste as
  needed, not a single linear demo
- **§15** Where to go next — pointers, not a runnable thing

Those sections are valuable in the linear tutorial flow but
don't have a corresponding `examples/NN-name/` directory.

[← Back to §15: Where to go next]({{ "/docs/15-where-to-go-next/" | relative_url }})
