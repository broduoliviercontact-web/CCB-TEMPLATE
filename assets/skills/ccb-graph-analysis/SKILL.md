---
name: ccb-graph-analysis
description: Inspect a codebase read-only and report the affected architecture.
---

# Graph analysis

1. Locate relevant entry points, callers, dependencies and tests.
2. Trace the smallest evidence-backed path through the affected components.
3. Report impact, constraints and uncertainties with file references.
4. Read the real flow before proposing architecture changes.
5. Look for reusable components, existing mechanisms and native platform features before suggesting new code.
6. Prefer a local extension of the current architecture; propose a new abstraction only when several real uses justify it.
7. Name dependencies and impacts without expanding the plan beyond the brief.
8. Do not edit files, review a proposed patch or generate graph output unless explicitly asked.
