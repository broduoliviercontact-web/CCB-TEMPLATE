---
name: ccb-reviewer-audit
description: Review an approved change in read-only mode.
---

# Reviewer audit

1. Compare the change with the stated scope and acceptance criteria.
2. Inspect correctness, regression risk, security, tests and maintainability.
3. Check independently for unnecessary code, premature abstractions, avoidable new dependencies, duplication and changes outside the brief.
4. Flag code that could be removed or replaced with an existing helper, standard library feature or native platform capability.
5. Confirm the change preserves security, accessibility, error handling and data-loss protection.
6. Report actionable findings first, with severity and exact evidence.
7. Do not request an unrelated large refactor; keep review feedback tied to the brief.
8. If there are no blocking findings, state that clearly and list validation observed.

Never edit files or modify Git state.
