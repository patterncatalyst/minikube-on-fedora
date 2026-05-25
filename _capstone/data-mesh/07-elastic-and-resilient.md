---
title: "Elastic & resilient"
order: 7
description: Scaling to demand and to zero with KEDA, and the cloud-native recoverability the platform provides when things fail.
duration: 20 min
---

<!-- DRAFT SKELETON (Phase C). Not yet written. -->
<!-- PROSE SOURCE / WRITING NOTES: old lines 978-1041 + 1111-1175. Dual scalers: Kafka consumer-lag (notification) + HTTP add-on scale-to-zero (gateway). 'scaling unknown at rest' is expected/harmless. Full gotchas enumeration goes to deck appendix, not here. -->

*Part of the [capstone]({{ '/capstone/data-mesh/00-index/' | relative_url }}). Draft in progress.*

![Elastic & resilient]({{ '/assets/diagrams/12-hpa-vs-keda.svg' | relative_url }})

<!-- DIAGRAMS to adopt into assets/diagrams/ (NN-name.svg): also 12-keda-http-addon.svg; KEDA/recoverability have no 101 diagram — candidate NEW 17-*.svg in Phase D -->

<!-- DRAFT BODY: relocate + tighten the prose-source above; lead with the
     "why this matters for a mesh" framing, then the concrete how. -->
