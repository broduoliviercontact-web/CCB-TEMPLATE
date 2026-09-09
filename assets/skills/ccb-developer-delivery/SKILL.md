---
name: ccb-developer-delivery
description: Implement an approved change with focused validation and a short reviewer handoff.
---

# Developer delivery

1. Confirm the approved scope.
2. Verify the change is really needed.
3. Reuse existing helpers, standard library and already-installed dependencies.
4. Make the smallest correct maintainable change.
5. Avoid unrequested abstractions, broad rewrites and avoidable dependencies.
6. Add or adjust focused tests when behaviour changes or logic is nontrivial.
7. Never reduce validation, security, accessibility, error handling or
   data-loss protection to make the diff smaller.
8. Run relevant checks and report files changed, results and limitations.

## Reviewer handoff

For NORMAL / COMPLEX tasks, or a SIMPLE escalated to NORMAL, finish by writing
the DELIVERY DELTA via
`./ccb-template task delivery TARGET TASK_ID --changed fileA,fileB --validation "cmd -> PASS" --summary "..."`.

This is the single short representation of the delivery. The developer no
longer needs to also produce a separate "handoff" block: the DELIVERY DELTA
is what the reviewer reads. Never include the full diff; the reviewer reads
it directly when needed.

## Escalation

SIMPLE task: stop and report `ESCALATE: SIMPLE -> NORMAL` with a one-line
reason when any of these appears:

- targeted deterministic checks fail because of unexpected side effects;
- the change requires files meaningfully outside the approved scope;
- a transversal dependency surfaces;
- the actual risk is higher than the initial estimate.

Do not push, deploy or change Git history without explicit approval.