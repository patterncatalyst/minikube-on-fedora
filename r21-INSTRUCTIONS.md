# r21 — apply instructions

The capstone walking skeleton: order-service end-to-end against
operator-managed Postgres. First *runnable* capstone iteration.

Assumes r20 has been applied (the §17 page, diagram, profile
scripts, and umbrella chart skeleton). If you haven't applied
r20 yet, do that first.

## Extract

```bash
cd ~/Dev/minikube-on-fedora && tar -xzf ~/Downloads/minikube-on-fedora_r21.tar.gz
```

Adds:
- `_plans/capstone-decisions.md` (new — the decision log)
- `_plans/reconciliation-plan-r21-addition.md` (splice into Section D)
- `_docs/17-capstone-r21-prose-insert.md` (splice into §17 prose)
- `examples/17-capstone/scripts/setup-postgres-operator.sh`
- `examples/17-capstone/charts/capstone/charts/postgres/` (Cluster CR subchart)
- `examples/17-capstone/charts/capstone/charts/order-service/` (service subchart)
- `examples/17-capstone/services/order-service/` (Poetry + FastAPI + Containerfile + tests)
- `examples/17-capstone/demos/smoke-order.sh`
- `r21-INSTRUCTIONS.md` (this file)

## Merge the two splice files

### §17 prose

```bash
$EDITOR _docs/17-capstone-r21-prose-insert.md _docs/17-capstone.md
# Insert the "## Implementation: order-service (the template)" section
# immediately BEFORE the "## What §17 delivers vs what's coming" heading.
rm _docs/17-capstone-r21-prose-insert.md
```

### Reconciliation entry

```bash
$EDITOR _plans/reconciliation-plan-r21-addition.md _plans/reconciliation-plan.md
# Append the r21 entry to Section D after the r20 entry.
rm _plans/reconciliation-plan-r21-addition.md
```

## Generate the Poetry lockfile (recommended)

For reproducible builds, generate and commit the lockfile:

```bash
cd examples/17-capstone/services/order-service
poetry lock
cd -
```

(If you don't have Poetry: `pipx install poetry`. The
Containerfile works without a committed lock via a glob, but
committing it pins versions.)

## Run the unit tests locally (fast feedback, no cluster needed)

```bash
cd examples/17-capstone/services/order-service
poetry install
poetry run pytest -v
cd -
```

Expect 4 passing tests (health, place+fetch, list, 404).

## The end-to-end smoke test (the actual verification)

This requires the capstone profile running and the CloudNativePG
operator installed.

```bash
cd examples/17-capstone

# 1. Profile (from r20 — skip if already running)
./scripts/setup-capstone-profile.sh

# 2. Install the CloudNativePG operator (cluster-wide — see the prose)
./scripts/setup-postgres-operator.sh

# 3. Run the walking-skeleton smoke test
./demos/smoke-order.sh
```

What the smoke test does:
1. Builds `order-service:v1` into the capstone profile via
   `minikube image build`
2. Deploys the Postgres `Cluster` CR; waits for the operator to
   provision a Ready primary
3. Deploys order-service; waits for it to be Available
4. Port-forwards, then: asserts `/health`, asserts `/healthz`
   (Postgres reachable), POSTs an order, GETs it back by id,
   confirms it's in the list
5. Queries Postgres directly (`psql` in the primary pod) to
   confirm the row persisted in `orders.orders`
6. Cleans up order-service on exit (leaves Postgres up for fast
   re-runs; pass `--purge-db` to tear it down too)

Expected ending: `✓ SUCCESS — order-service walking skeleton
verified`.

## If the smoke test passes

Paste me the output (or just "smoke passed") and I'll:
- Promote the relevant rows to `verified (Fedora 44)` in r22's
  reconciliation update
- Ship **r22**: the other four services (inventory, payment,
  shipping, notification) as parallel repetitions of the
  order-service template

## If something fails

Most likely failure points and fixes:

- **CloudNativePG PVC doesn't bind** (the flagged risk): the
  `Cluster` CR's PVC may need an explicit `storageClass`. Check
  `kubectl get pvc -n capstone` and `kubectl describe pvc ...`.
  If it's pending, we add `storageClass: standard` to the
  postgres subchart values — quick r21a
- **Image build fails on Poetry export**: if `poetry export`
  isn't found, the plugin pin in the Containerfile
  (`poetry-plugin-export`) may need adjusting for your Poetry
  version — paste the build error
- **`ubi9/python-312:latest` pull fails**: confirm the exact
  tag; Red Hat occasionally changes published tags. We pin to a
  specific digest in r21a if needed
- **readiness probe never passes**: order-service can't reach
  Postgres. Check the CNPG secret name matches
  (`kubectl get secret -n capstone | grep postgres`) and that
  the `-rw` service exists

Paste the failing output and I'll ship the fix-up.

## Commit

After the smoke test passes (or after you've reviewed the static
artifacts if you want to commit before running):

```bash
git add -A
git commit -m "feat(r21): capstone walking skeleton — order-service + CloudNativePG + decision log"
git push
sleep 5 && gh run watch
```

Note: the site build only renders the §17 prose changes; the
service code and charts live under `examples/` which is excluded
from the published site. CI green just confirms the prose
renders.

## Don't forget

The `_config.yml` exclude list should already have
`examples/` (it does per your uploaded config). The new
`examples/17-capstone/services/` and `charts/` content is
therefore repo-only, not published — correct.
