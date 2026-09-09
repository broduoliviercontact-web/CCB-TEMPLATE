# V2 Context Packet

The Context Packet is the compact state passed between agents instead of the
full conversation history. Source of truth for code, diff, tests and Git
state is the real repository; the packet is a pointer to that state.

## Objects

- **TASK PACKET** (`.ccb/tasks/<id>/task.md`) — stable task state:
  complexity, goal, scope, acceptance, constraints, known context.
- **DELIVERY DELTA** (`.ccb/tasks/<id>/delivery.md`) — implementation result:
  changed files, validation, summary, notes.

The task id is derived from the brief filename by default
(`brief-2026-09-09-fix-login.md` → `brief-2026-09-09-fix-login`) and can be
overridden with `--id`.

## Lifecycle

```
brief (manager reads)
   ↓
TASK PACKET (manager creates via ./ccb-template task create)
   ↓
implementation (developer)
   ↓
DELIVERY DELTA (developer writes via ./ccb-template task delivery)
   ↓
reviewer (./ccb-template task review-input → TASK PACKET + DELIVERY + git diff)
```

The packet is rewritten in place when needed. No `task-v1.md`,
`task-v2.md`, ...; Git already tracks history.

## Rules

- Omit any field that does not materially help the next agent.
- Never include the full diff, full file contents, full logs or full Graph
  reports. Reference the local file or command instead.
- The reviewer reads `git diff` directly. The DELIVERY DELTA only names the
  changed files.
- The packet is local on disk, validated against path traversal and
  symlinks.

## CLI

```sh
./ccb-template task create        TARGET BRIEF_FILE [--complexity simple|normal|complex] [--id TASK_ID]
./ccb-template task delivery      TARGET TASK_ID [--changed fileA,fileB] [--validation "cmd -> result"] [--summary TEXT] [--notes TEXT]
./ccb-template task show         TARGET TASK_ID
./ccb-template task review-input  TARGET TASK_ID
```

`task delivery` derives `changed` from `git diff --name-only HEAD` when not
given explicitly, so the developer does not retype it.