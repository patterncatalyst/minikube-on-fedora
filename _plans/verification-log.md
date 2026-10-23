---
title: "Verification log"
layout: plan
---

Verification-status narration removed from reader-facing chapters (site chrome shows reader content only; banked here, plans collection output:false).

## 16-examples (Verification status section)

## Verification status

The examples are the canonical record of "what's been tested vs.
what's claimed". Each example's verification status against
Fedora 44 is tracked in
[`_plans/reconciliation-plan.md`](https://github.com/patterncatalyst/minikube-on-fedora/blob/main/_plans/reconciliation-plan.md)
(viewable in the repo). The default status for any new claim is
`unverified`; promotion to `verified` requires a real test run by
a human on Fedora 44.

As of project close-out (r17), the count of verified rows stood
at **107**. Those runs predate the move to Docker Engine and
published NodePorts, so treat the count as historical until the
examples are re-verified on the current stack.


