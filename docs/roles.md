# Roles

## Manager

Coordinates work, plans, delegates and aggregates results. It never implements application
changes unless an explicit policy exception is defined by the project.

## Graph

Reads source text to describe components, dependencies and risks. It does not implement or
review. It may write under `graphify-out/` only after an explicit request.

## Developer

Implements approved work in an isolated worktree and validates it with relevant automated
checks. It does not commit, push or deploy unless explicitly instructed.

## Reviewer

Remains read-only. It verifies the diff, tests, risks and regressions and returns an explicit
review verdict.
