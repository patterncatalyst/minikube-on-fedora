---
title: Reconciliation plan
description: What in this tutorial is verified, what is in flight, and what needs validation.
---

This document tracks the **gap between what the tutorial claims and
what we have actually verified end-to-end**. It is the single
authoritative list of things to check, fix, or expand before the
tutorial is declared production-ready.

## How to use this document

- When adding new tutorial content that makes a verifiable claim,
  add a row to the appropriate section below as `unverified`.
- When you (or a contributor) actually test a claim, promote the
  row to `verified` (or `verified (Platform)` if cross-platform
  testing is still incomplete).
- When something is being actively debugged, mark it `in flight`
  with a brief note about what's blocking.
- When you decide not to test something in this iteration, mark it
  `out of scope` with the reason.

**Default state for new claims is `unverified`.** Promotion to
`verified` requires a real test, run by a human, with the result
recorded.

## Conventions

- A `verified` row has been run end-to-end on at least one named
  platform with the exact commands shown in the tutorial.
- A row marked `verified (Platform)` has been tested on that
  platform but not yet replicated on others.
- An `in flight` row is being actively worked on; the assigned
  contributor is named where known.
- An `unverified` row is a claim taken from source material that
  has not been re-validated against a current environment.
- An `out of scope` row is something we deliberately decided not
  to verify in this iteration; the reason is given.

## A. (Topic-specific catalog)

> TODO: rename this section to whatever you're cataloging. For a
> Hummingbird-style tutorial it was the image catalog; for a
> different tutorial it might be API endpoints, library versions,
> or supported platforms.

| Status | Claim | Where | How to verify |
|---|---|---|---|
| unverified | (example claim) | §1 | (how someone would test it) |

## B. (Section-specific items)

> TODO: as you write sections, add any unverified claims here.

| Status | Claim | Section | Notes |
|---|---|---|---|

## C. Testing matrix

> The end-to-end tests of each runnable example. This is where the
> reconciliation plan earns its keep — it lets a reviewer see at a
> glance which examples have been confirmed to actually work.

| Status | What | Notes |
|---|---|---|

## D. Open priorities

Roughly priority-ordered list of what to do next.

**Done:**

- ✅ (nothing yet — this is a fresh project)

**Open, priority-ordered:**

1. (TODO: the first thing you should test)
2. (TODO: the second thing)
3. ...
