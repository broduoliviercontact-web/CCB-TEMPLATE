---
name: ccb-manager-planning
description: Plan and delegate a scoped CCB task without changing application files.
---

# Manager planning

1. State the outcome, scope, assumptions and acceptance criteria.
2. Classify complexity: SIMPLE / NORMAL / COMPLEX. Pick the smallest agent
   set that reaches the required confidence. Graph only on demand.
3. Materialise the task as a TASK PACKET with
   `./ccb-template task create TARGET BRIEF_FILE --complexity ...`. The packet
   is a compact pointer; omit any field that does not materially help the
   next agent.
4. Delegate to developer for implementation, reviewer for validation, graph
   only when dependencies or impact are ambiguous.
5. Refuse speculative feature batches, unrequested abstractions and
   nonessential dependencies.
6. Consolidate results before declaring completion. Never implement, edit or
   commit yourself.