# V2 Reviewer Diff-First

The reviewer follows a strict **diff-first** discipline. It reads the
implementation evidence first (scope, diff, validation, developer notes) and
only expands context when a concrete reason in the diff requires it.

This keeps the reviewer token usage predictable and small without lowering
review quality.

## Workflow

```
Scope -> Diff -> Validation -> Targeted expansion -> Findings
```

1. **Scope** — read the acceptance criteria. Reject anything outside the brief.
2. **Diff** — read the changed files first. Look for correctness, regressions,
   security, logic errors, accidental changes, insufficient tests and
   maintainability issues introduced by the diff.
3. **Validation** — read the commands the developer already ran. Do not rerun
   large suites when a focused check already exists.
4. **Targeted expansion** — read code outside the diff only when the diff
   raises a precise question (ambiguous contract, modified interface, direct
   dependency, security/auth touched, indirect test behaviour, concrete
   regression risk). Stop as soon as enough evidence exists.
5. **Findings** — report only actionable findings ordered by severity:
   `BLOCKER`, `HIGH`, `MEDIUM`, `LOW`. Each finding should include severity,
   file and line, problem, consequence and expected fix.

## Boundaries

- The reviewer **never** calls Graph automatically. If a real architectural
  ambiguity surfaces, the reviewer reports it to the manager.
- The reviewer remains read-only: no edits, no Git operations.
- SIMPLE tasks do **not** call the reviewer by default. Diff-First applies to
  NORMAL, COMPLEX, and SIMPLE tasks escalated to NORMAL.
- Each context expansion must answer one explicit question. No "explore to be
  sure".

## End-to-end example

### Developer handoff

```markdown
DEVELOPER HANDOFF

Changed:
- src/login/form.tsx
- src/login/form.test.tsx

Validation:
- pnpm test src/login -> PASS
- pnpm lint src/login -> PASS

Diff summary:
- Persist the email field across the password-reset navigation by reading it
  from the existing draft store instead of the form local state.

Notes:
- The draft store already supports TTL; no new dependency was added.
- A follow-up could reuse the same draft store for the locale selector.
```

### Reviewer input contract

The reviewer treats the same block as the starting point, extended with the
scope:

```markdown
REVIEW INPUT

Scope:
- Remember the email after the password reset redirect.

Acceptance criteria:
- The login form pre-fills the email after a successful reset.
- Existing form validation behaviour is unchanged.

Changed files:
- src/login/form.tsx
- src/login/form.test.tsx

Diff:
- (compact summary produced by the developer)

Validation:
- pnpm test src/login -> PASS
- pnpm lint src/login -> PASS

Developer notes:
- Draft store already supports TTL; no new dependency was added.
```

### Reviewer findings

```markdown
FINDINGS

No BLOCKER, HIGH or MEDIUM finding.

LOW:
- src/login/form.tsx L42 - the draft store key is hard-coded. If a second form
  ever needs the same behaviour, prefer a per-form key.
  Consequence: minor coupling between the form and the store name.
  Expected fix: pass the key as a prop or read it from a shared constant.
```

The reviewer expanded only into the changed file (and, if needed, the draft
store contract) — never into the whole frontend.