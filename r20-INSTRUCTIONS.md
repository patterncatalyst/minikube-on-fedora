# r20 — apply instructions

First implementation iteration of the §17 capstone. Ships the
skeleton: directory tree, helm umbrella chart scaffolding,
profile setup scripts, architecture diagram, §17 prose. No
services deployed yet; r21+ fills in the implementation.

## Prerequisite: r19 PRD merge

I noticed your uploaded `PRD.md` doesn't include the §17
capstone section that r19 was supposed to merge in. If you've
already done that merge in your working copy: skip this step.
Otherwise, do it before r20:

```bash
# If you still have the r19 tarball:
cd ~/Dev/minikube-on-fedora
tar -xzf ~/Downloads/minikube-on-fedora_r19.tar.gz   # if not already extracted
$EDITOR _plans/PRD-r19-capstone-section.md PRD.md
# append §17 capstone section to end of PRD.md, then:
rm _plans/PRD-r19-capstone-section.md
```

And the r19 reconciliation entry, if not already merged:

```bash
$EDITOR _plans/reconciliation-plan-r19-addition.md _plans/reconciliation-plan.md
# splice r19 entry to Section D, replace "Project state (post-r18): closed"
# language with "Project state (post-r19): capstone planning underway", then:
rm _plans/reconciliation-plan-r19-addition.md
```

Don't commit yet — r20's changes go into the same commit.

## Apply r20

```bash
cd ~/Dev/minikube-on-fedora && tar -xzf ~/Downloads/minikube-on-fedora_r20.tar.gz
```

Adds:
- `_docs/17-capstone.md` (§17 prose with embedded diagram)
- `assets/diagrams/17-capstone-data-mesh.svg`
- `assets/diagrams/17-capstone-data-mesh.excalidraw`
- `examples/17-capstone/README.md`
- `examples/17-capstone/charts/capstone/Chart.yaml`
- `examples/17-capstone/charts/capstone/values.yaml`
- `examples/17-capstone/scripts/setup-capstone-profile.sh`
- `examples/17-capstone/scripts/teardown.sh`
- `examples/17-capstone/{proto,postman,demos,services}/.gitkeep`
- `_plans/reconciliation-plan-r20-addition.md` (merge into Section D)
- `r20-INSTRUCTIONS.md` (this file)

## Merge the reconciliation entry

```bash
$EDITOR _plans/reconciliation-plan-r20-addition.md _plans/reconciliation-plan.md
# Splice into Section D after the r19 entry, then:
rm _plans/reconciliation-plan-r20-addition.md
```

## Update §16 footer to link forward to §17

Open `_docs/16-examples.md` and find the bottom — it currently
ends with `[← Back to §15: Where to go next](...)`. Add a
forward link above it:

```markdown
[On to §17: Capstone — A data mesh on minikube →]({{ "/docs/17-capstone/" | relative_url }})
[← Back to §15: Where to go next]({{ "/docs/15-where-to-go-next/" | relative_url }})
```

## Regenerate example pages

The new `examples/17-capstone/README.md` will become the §17
example page when the sync runs:

```bash
./scripts/sync-example-pages.sh
```

You should see a new entry: `OK   examples/17-capstone/README.md
→ _example_pages/17-capstone.md (title: §17 Capstone — Data mesh
on minikube)` — or similar depending on the first H1's exact
wording.

## Audit, review, commit

```bash
./scripts/check-cross-references.sh    # should be clean
./scripts/editorial-audit.sh           # advisory; expect "we" voice findings only

git status
git diff --stat
git diff _docs/17-capstone.md          # spot-check the prose
git diff _docs/16-examples.md          # confirm forward link added
git add -A
git commit -m "feat(r19+r20): §17 capstone — PRD addition + skeleton (prose, diagram, helm scaffolding, profile scripts)"
git push
sleep 5 && gh run watch
```

## Verify the deployed site

After CI passes, visit:

- `https://patterncatalyst.github.io/minikube-on-fedora/docs/17-capstone/`
  — the new §17 page. Should show:
   - Full site chrome (header, breadcrumbs, footer)
   - Section number badge "17"
   - Title "Capstone: a data mesh on minikube"
   - Architecture diagram embedded after the "Architecture
     overview" section, rendered crisply
   - All the conceptual sections (data mesh, four principles,
     why Kubernetes, services table, platform table) with
     proper heading hierarchy
- `https://patterncatalyst.github.io/minikube-on-fedora/examples/17-capstone/`
  — the example page generated from
  `examples/17-capstone/README.md`. Should show with the
  same site chrome
- `https://patterncatalyst.github.io/minikube-on-fedora/docs/16-examples/`
  — the §16 hub should now include §17 in its listing

## Optional: actually run the profile setup

If you want to confirm the setup script works on your machine
before r21 lands (recommended), run it:

```bash
cd examples/17-capstone
./scripts/setup-capstone-profile.sh
```

This will:
1. Check that `minikube` and `podman` are in PATH (should be from §2)
2. Check the inotify-limits tweak from §1 is applied
3. Warn if other minikube profiles are running (recommend stopping them)
4. Start the `capstone` profile with 24 GB / 16 CPU / 80 GB disk
5. Switch kubectl context to `capstone`
6. Create the `capstone` namespace

Expected duration: 60-120 seconds (first time it pulls the
kicbase image). Successful output ends with the "Capstone
profile is ready" banner and the cluster's `kubectl get nodes`
showing one Ready node.

To tear down after testing:

```bash
./scripts/teardown.sh                    # stop, keep state
# OR
./scripts/teardown.sh --remove-profile   # delete entirely
```

If this works, paste me the output (or just "setup passed") and
I'll promote the two relevant rows to `verified (Fedora 44)`
in r21's reconciliation update.

## Open question to resolve before r21

The Postgres operator. r19 didn't explicitly pick one; the
default I'm proceeding with for r21+ is **CloudNativePG**
(maintained, modern, CNCF Sandbox project, gives us a clean
`Cluster` CR + automated backups). Alternatives:

- Zalando postgres-operator
- Crunchy Data PGO
- Bitnami's `postgresql-ha` helm chart (operator-free)

If you have a preference, say so. Otherwise r21 proceeds with
CloudNativePG.

## What's next

Once r20 is committed and the §17 page renders correctly, **r21**
ships the order-service prototype: Containerfile (UBI 9 base),
Python source (FastAPI + REST endpoints), helm subchart, smoke
tests, Postgres schema. r21's prose adds an "## Implementation:
order-service" subsection to §17.

After r21 lands cleanly, **r22** parallelizes the same pattern
across inventory, payment, shipping, and notification services.

By r25 you'll have the full Kafka event chain firing; by r27,
observability lit up; by r30, project close-out for the second
time (this time with the capstone in scope).
