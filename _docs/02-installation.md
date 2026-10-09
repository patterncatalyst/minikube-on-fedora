---
title: Installation
order: 2
description: Install minikube, kubectl, helm, and the supporting toolbox on Fedora 44.
duration: 20 minutes
---

This section installs the tools you'll use to drive minikube and
work with the cluster it spins up: **minikube** itself, **kubectl**,
**helm**, and a handful of supporting utilities (`httpie`, `yq`,
`hey`, `stern`, `kubectx`/`kubens`, and `krew`).

The mix of install paths reflects what's actually in Fedora 44's
repos in mid-2026: `helm` and `httpie` are packaged and install
cleanly via `dnf`; `minikube` and `kubectl` aren't packaged and
install from their upstream RPM/binary; the rest install via a
mix of upstream binaries, `go install`, and `krew` (the kubectl
plugin manager). **Where Fedora has a current package, this
tutorial uses it.**

If you already have any of these installed at a recent version,
skip those steps — re-running an install is harmless but slow.

## Install minikube

`minikube` isn't currently packaged in Fedora's standard repos.
The cleanest install path is the upstream RPM via `dnf`, so
future updates pick up like any other dnf-tracked package:

```bash
sudo dnf install -y https://github.com/kubernetes/minikube/releases/download/v1.38.1/minikube-1.38.1-0.x86_64.rpm
```

This installs the pinned release, v1.38.1, as `/usr/bin/minikube`. Confirm:

```bash
minikube version
```

You should see output mentioning a default Kubernetes version
that minikube targets — that's the *cluster* version, distinct
from your `kubectl` client version. minikube v1.38.1 defaults to
launching Kubernetes 1.35.x clusters; §3 pins v1.35.1 explicitly.

### Why not the upstream `curl ... && sudo install` path?

You'll see `curl -LO ... && sudo install ...` instructions in
the minikube quickstart. They work, but install minikube to
`/usr/local/bin/` outside of dnf's view, so future updates
require re-running the curl. The RPM-through-dnf path above
keeps minikube under dnf's management — `sudo dnf upgrade` picks
it up alongside everything else.

## Install kubectl

If you already have `kubectl` installed at a recent version
(1.34.x or 1.35.x), skip this step:

```bash
kubectl version --client=true
```

The Kubernetes version skew policy guarantees a client one minor
version behind or ahead of the server works — so a kubectl 1.35.x
client is compatible with minikube's default 1.35.x cluster (and
with any 1.34.x or 1.36.x cluster you might spin up via
`--kubernetes-version`).

If kubectl isn't installed, install the upstream binary (kubectl
is not currently in Fedora 44's standard repos). Pin it to the
newest v1.35.x patch, which matches the cluster version §3 starts.
Find that patch (v1.35.9 at the time of writing; `jq` is also used
by the demo scripts):

```bash
sudo dnf install -y jq
KUBECTL_VERSION=$(curl -s "https://api.github.com/repos/kubernetes/kubernetes/releases?per_page=100" \
  | jq -r '.[].tag_name' | grep -E '^v1\.35\.[0-9]+$' | head -1)
echo "$KUBECTL_VERSION"
```

Then download and install it:

```bash
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl
```

Confirm:

```bash
kubectl version --client=true
```

### `minikube kubectl` is also a thing

minikube ships its own kubectl invocable as `minikube kubectl --
...`, automatically version-matched to the cluster. It's fine
for occasional use, but standalone `kubectl` is shorter to type,
integrates with shell completion (covered in §10), and is what
every other Kubernetes guide assumes. This tutorial uses
standalone `kubectl` throughout.

## Install helm

`helm` is packaged in Fedora 44's standard repos at version 4.x:

```bash
sudo dnf install -y helm
helm version --short
```

You should see `v4.1.x+`. Helm 4 was released in late 2025 and is
the current stable line. The Helm-3-format charts that every
public chart on Artifact Hub still ships in (Bitnami, Istio,
KEDA, etc.) work unchanged on Helm 4 — chart authoring and
consumer-side commands (`install`, `upgrade`, `rollback`,
`uninstall`) behave the same. §9 covers helm in depth and notes
the small handful of places to watch for v3 vs. v4 differences.

## Install supporting tools

These make day-to-day Kubernetes work easier. You can install
them all now (recommended; it's a few minutes total) or wait
until specific sections introduce them.

### httpie — friendlier `curl`

Packaged in Fedora 44 repos:

```bash
sudo dnf install -y httpie
http --version
```

### yq — YAML query and transform

mikefarah's `yq` (Go binary, jq-like syntax) is packaged in
Fedora 44 repos at v4.x:

```bash
sudo dnf install -y yq
yq --version
```

You should see `yq (https://github.com/mikefarah/yq/) version v4.x`.

A historical note worth knowing: in earlier Fedora versions the
`yq` package was the unrelated Python tool `python-yq`, which has
different syntax. Older guides will tell you to grab mikefarah's
binary from upstream to avoid that confusion. On Fedora 44 the
`dnf install` is now the right path — Fedora packages mikefarah's
`yq` directly.

### hey — HTTP load generator

Used heavily in §12 (KEDA HTTP-driven scaling). If you don't
have it (`hey --help` failing), install via Go:

```bash
sudo dnf install -y golang
go install github.com/rakyll/hey@v0.1.5
```

The binary lands in `~/go/bin/hey`. If `~/go/bin/` isn't already
on your `PATH`, add it now (one-time):

```bash
echo 'export PATH="$HOME/go/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### kubectl plugins via krew

`krew` is the kubectl plugin manager. Many useful kubectl
extensions ship as krew plugins rather than as standalone
binaries — including `stern`, `kubectx`, and `kubens`, none of
which are packaged in Fedora's repos.

Install krew first (pinned to v0.5.0):

```bash
( set -x; cd "$(mktemp -d)" && \
  OS="$(uname | tr '[:upper:]' '[:lower:]')" && \
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/arm.*$/arm/')" && \
  KREW="krew-${OS}_${ARCH}" && \
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/download/v0.5.0/${KREW}.tar.gz" && \
  tar zxvf "${KREW}.tar.gz" && \
  ./"${KREW}" install krew )
```

Then add krew to your `PATH` (one-time):

```bash
echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Now use krew to install `stern`, `kubectx`, and `kubens`:

```bash
kubectl krew install stern ctx ns
```

`ctx` and `ns` are krew's names for what the standalone scripts
call `kubectx` and `kubens`. They install as `kubectl ctx` and
`kubectl ns` rather than top-level binaries — slightly more
typing, but discoverable via `kubectl plugin list`.

Confirm:

```bash
kubectl plugin list | grep -E 'stern|ctx|ns'
```

You should see three lines, one per plugin.

## Verify everything

Re-run the audit script — every tool should now report
a path and a version:

```bash
./scripts/audit-fedora-prereqs.sh | grep -A1 '=== currently installed'
```

Every line should show a path rather than `(not installed)`.

For a quick "are the headliners all working" check:

```bash
minikube version | head -1 && kubectl version --client=true | head -1 && helm version --short
```

Three single-line version reports, no errors — you're ready for
§3.

[On to §3: Starting minikube →]({{ "/docs/03-starting-minikube/" | relative_url }})
