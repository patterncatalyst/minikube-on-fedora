---
title: Editor, shell, terminal
order: 10
description: Practical tooling for fast feedback when editing manifests, running kubectl, and navigating the cluster.
duration: 20 minutes
---

§1 through §9 are about Kubernetes. This section is about the
tools you use to work with Kubernetes — the editor for manifests,
the shell for commands, the conveniences that make 1000 kubectl
invocations feel like 100.

**None of what's below is required for the examples in this
tutorial to work.** The examples have been written to copy-paste
directly. But by §6 you've probably noticed that typing `kubectl
get deployment nginx -n default -o yaml` for the fifteenth time
gets old; by §11 (Istio) it gets very old.

The goal here: enough productivity wins that the rest of your k8s
work feels natural rather than tedious.

## Editor: Pulsar

This tutorial's manifests were written and tested in **Pulsar**
— the community-maintained successor to Atom, which GitHub
discontinued in 2022 after the Microsoft acquisition. A group of
contributors forked the editor and continues to ship it under the
Pulsar name. Cross-platform (Linux, macOS, Windows), open source,
fast keyboard-driven workflow, plugin-friendly. The official
Fedora `.rpm` is at [pulsar-edit.dev](https://pulsar-edit.dev/).

Out of the box, Pulsar gives you what matters for editing
Kubernetes manifests:

- **YAML syntax highlighting** — `apiVersion`, `kind`, list/map
  structure all visually distinct
- **Bracket and indentation matching** — YAML indentation is
  load-bearing, and a misaligned space wastes hours. Pulsar
  shows the indent guides
- **Fuzzy file finder** (Ctrl-T) — type `dep<enter>` to jump to
  `deployment.yaml` from anywhere in the project
- **Multi-pane editing** for side-by-side manifests (e.g., the
  Deployment in one pane, the Service in another)
- **Project-wide search** — useful when you've forgotten which
  example uses a particular pattern
- **Git integration** — see what's changed before
  `git diff`-ing in the terminal

For schema-aware editing (red-underlining unknown fields,
autocomplete for `spec.containers[]` and friends), check Pulsar's
package registry for bindings to `yaml-language-server`. Pointing
the language server at the Kubernetes JSON Schema URL gives you
IDE-grade validation inside a lightweight editor.

### If Pulsar isn't your thing

This tutorial doesn't depend on the editor — manifests are plain
YAML; the editor doesn't talk to the cluster. Use whatever you
like:

- **VS Code** with Microsoft's official Kubernetes extension —
  most popular by far; deep schema awareness; integrated kubectl
  panel that shows cluster state alongside the editor. If you
  want a single tool that does everything, this is it
- **Neovim** with `yaml-language-server` (via Mason or LSP-zero)
  — terminal-native, fast, mature ecosystem; popular among
  k8s practitioners who already live in vim
- **IntelliJ family** (IDEA, GoLand, PyCharm, CLion, …) with
  JetBrains' Kubernetes plugin — same schema awareness as
  VS Code in a heavier IDE
- **nano / vi / vim** out of the box — works fine for one-off
  edits; less convenient when you're hopping between multiple
  manifest files in a single example directory

The §6-§9 demos all run identically regardless of which editor
opened the manifests.

## Shell: zsh

The §1 prerequisites assumed a POSIX-style shell. The `demo.sh`
scripts and helpers under `scripts/lib/` all start with
`#!/usr/bin/env bash`, so they run under bash regardless of your
interactive shell.

For *interactive* k8s work, **zsh** has a few advantages worth
the switch:

- Tab completion is more powerful and more configurable than
  bash's — completing pod names, label keys, resource fields
- `kubectl`, `helm`, and `minikube` ship with first-class zsh
  completion
- The `oh-my-zsh` framework ([ohmyz.sh](https://ohmyz.sh/))
  packages a kubectl plugin, prompt themes that show your
  current cluster context, and a hundred quality-of-life
  features

Fedora 44's default for new users is bash. Install and switch
to zsh:

```bash
sudo dnf install -y zsh
chsh -s "$(which zsh)"
```

Log out and back in. New terminal sessions launch zsh; the
`demo.sh` scripts keep working unchanged (they exec their own
bash).

If you'd rather stick with bash, everything below still works —
substitute `bash` for `zsh` in the completion `source` lines,
and use `complete -F` instead of `compdef` for the aliases.

## Tab completion — the single biggest win

If you do nothing else in this section, do this. Tab completion
turns `kubectl get pod nginx-pv-864c5dfd8b-zvpwn` into `kubectl
get pod nginx-pv<TAB>` and lets the shell fill in the rest.

Add to `~/.zshrc`:

```zsh
# kubectl / helm / minikube tab completion
source <(kubectl completion zsh)
source <(helm completion zsh)
source <(minikube completion zsh)
```

For bash, the equivalent in `~/.bashrc`:

```bash
source <(kubectl completion bash)
source <(helm completion bash)
source <(minikube completion bash)
```

Reload (`source ~/.zshrc`) and try:

```
kubectl get po<TAB>
```

You'll see `pod  podsecuritypolicies  poddisruptionbudgets …`.
Completion also covers resource names — `kubectl describe pod
<TAB>` lists the actual Pods in your current namespace.

## Aliases: the k= shortcut family

The de facto convention among k8s practitioners is `alias
k=kubectl`. Three keystrokes per command saved; small-sounding
until you've run kubectl a few hundred times.

If you're not normally an alias user (some good reasons not to:
aliases hide from teammates pairing on your terminal, scripts
can't assume them, they make screenshots in tutorials harder to
follow), the conventional set is still worth knowing because it
appears in blog posts, talks, and others' shell history.

A curated starter set for `~/.zshrc`:

```zsh
# kubectl shortcuts
alias k=kubectl
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'
alias kgn='kubectl get nodes'
alias kga='kubectl get all'
alias kd='kubectl describe'
alias kdp='kubectl describe pod'
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias kx='kubectl exec -it'

# helm shortcut
alias h=helm

# Tell completion to handle k and h as aliases for kubectl/helm.
# zsh-specific; the bash equivalent is `complete -F`.
compdef __start_kubectl k
compdef __start_helm h
```

After `source ~/.zshrc`:

```
k g<TAB>
```

… completes to `get`, just like `kubectl`. Tab completion follows
the alias because of the `compdef` lines.

Two variants worth knowing:

- **`kgp -w`** — kubectl's watch flag re-renders Pod state as it
  changes. `kgp -w` is the fastest way to see a Deployment roll
  out
- **oh-my-zsh's `kubectl` plugin** — a turn-key alias set far
  larger than the above. Enable in `~/.zshrc` via `plugins=(...
  kubectl ...)`. The trade-off: more aliases to remember vs.
  copying the curated short list

## kubectl built-ins worth knowing

Two kubectl subcommands that aren't in §6-§9 but earn their
keep:

- **`kubectl edit <resource>`** — opens the live object in your
  `$EDITOR` (set this to `pulsar -w` or your preference). Save
  and the change is applied to the cluster. Useful for one-off
  tweaks; less safe than `apply` from a versioned file but
  faster for exploration
- **`kubectl explain <resource>.<field>`** — schema lookup. Forgot
  what `spec.template.spec.affinity` accepts? `kubectl explain
  deployment.spec.template.spec.affinity` lists the subfields
  with descriptions. Faster than the official docs when you
  already know the resource name

## Context and namespace switching: kubectx, kubens

§2 installed these as krew plugins (`kubectl ctx`, `kubectl ns`).
The fast access pattern:

```bash
kubectl ctx              # list contexts; current marked
kubectl ctx minikube     # switch context
kubectl ns               # list namespaces; current marked
kubectl ns kube-system   # switch default namespace
```

If you live in a single minikube cluster these matter less; the
moment you're toggling between minikube and a remote cluster —
or between `default` and `kube-system` — the gain is obvious.

## Streaming logs from multiple Pods: stern

Also installed in §2:

```bash
stern -l app=nginx-helm
```

Tails logs from every Pod matching the label, color-coded by
Pod name. More useful than `kubectl logs -f <pod>` specifically
for Deployments where you want all replicas' output interleaved.

## k9s — curses UI for the cluster

`kubectl get pods` over and over feels like driving by reading
the speedometer. **k9s** is the dashboard.

A curses-style terminal UI: navigate Kubernetes resources with
arrow keys and short letter commands, see live updates as state
changes, drill into Pods to view logs / shell in / view the
manifest inline.

Install from Fedora:

```bash
sudo dnf install -y k9s
```

Or grab the latest release from [k9scli.io](https://k9scli.io/).

Launch:

```bash
k9s
```

`?` shows keyboard shortcuts. `:pod<enter>` lists Pods. Press
`l` on a Pod to tail its logs; `s` to open a shell in it; `d`
to describe. `:svc<enter>` switches to Services, `:deploy<enter>`
to Deployments. `q` quits.

k9s is the single most-recommended optional tool here. Not
because the examples need it, but because once you have it
running in a second terminal pane while you `kubectl apply` in
another, debugging gets noticeably faster.

## Keeping multiple things open

A productive minikube session commonly has several long-running
things side by side:

- `kubectl port-forward …` (one terminal, locked to the
  port-forward)
- `k9s` (one terminal, full-screen TUI)
- An interactive shell for running kubectl commands
- A `stern` log stream (one terminal, scrolling)

Three approaches to keeping these organized:

- **Terminal tabs** in whichever GUI terminal emulator you use
  (GNOME Terminal, Kitty, Alacritty, Konsole, …). Simple,
  visual, works everywhere
- **tmux** — the venerable terminal multiplexer. Detach and
  re-attach across SSH sessions, define window layouts, scroll
  back through buffers. Install via `sudo dnf install -y tmux`
- **zellij** — modern alternative to tmux with friendlier
  defaults (the keybindings are discoverable rather than
  cryptic). Check [zellij.dev](https://zellij.dev/)

This tutorial doesn't depend on terminal multiplexing — each
demo runs in one terminal — but you'll find yourself wanting it
as the parallelism grows in §11 onwards.

## Putting it together

A productive minikube-on-Fedora workflow:

1. **Pulsar** (or your editor) open on the manifest files
2. **zsh** with kubectl/helm/minikube tab completion and the
   alias set above
3. **k9s** in a second terminal showing live cluster state
4. The current `examples/NN-*/demo.sh` running in a third
   terminal

None of these are required for the examples in §1-§9 to work,
and none are part of the reconciliation plan (this section is
reference material). But the §6-§9 demos all become much more
pleasant to run with this setup — and the §11 Istio work, with
its handful of long-running watch processes, almost requires
it.

[On to §11: Istio →]({{ "/docs/11-istio/" | relative_url }})
