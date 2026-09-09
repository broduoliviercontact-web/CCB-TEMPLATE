---
name: ccb-reviewer-audit
description: Review an approved change in read-only mode using the diff-first discipline.
---

# Reviewer audit (diff-first)

The reviewer's starting context is the Context Packet: TASK PACKET +
DELIVERY DELTA, plus a pointer to `git diff`. The reviewer does NOT receive
the full conversation history. Use `./ccb-template task review-input TARGET
TASK_ID` to obtain the compact starting block.

Start from scope, diff, validation and developer notes. Expand outside the diff
only when a concrete question in the diff requires it.

## Steps

1. **Scope** — read acceptance criteria; reject anything outside the brief.
2. **Diff** — read the diff first. Look for correctness, regressions,
   security, logic errors, accidental changes, missing tests and
   maintainability issues introduced by the diff.
3. **Validation** — read the commands the developer already ran. Do not
   rerun a large suite when a focused check already exists.
4. **Targeted expansion** — read code outside the diff only when a concrete
   question requires it (ambiguous contract, modified interface, direct
   dependency, security/auth touched, indirect test behaviour, concrete
   regression risk). Each expansion answers one question.
5. **Findings** — actionable items ordered `BLOCKER`, `HIGH`, `MEDIUM`, `LOW`,
   with severity + file + line + problem + consequence + expected fix. Say
   explicitly when no blocker remains.

## Boundaries

- Read-only. No edits, no Git operations.
- Never call Graph automatically. Report ambiguity to the manager instead
  of calling Graph from here.
- Do not explore "to be sure". Each expansion must answer a precise
  question; stop as soon as enough evidence exists.

## Reviewer input contract

```markdown
REVIEW INPUT

Scope:
- <one short paragraph>

Acceptance criteria:
- <bullet>

Changed files:
- <path>

Diff:
- <unified diff or compact summary>

Validation:
- <command> -> <result>

Developer notes:
- <one short paragraph>
```

Missing items are requested from the manager, never invented. Full
explanations and examples live in `docs/v2-reviewer-diff-first.md`.