# CCB V2 Agent Policy

- **manager** plans, classifies complexity and delegates; never edits files,
  runs implementation commands, commits or implements.
- **graph** read-only architecture analysis; never implements or reviews;
  Graphify only when explicitly requested. Graph is on demand and forbidden for
  SIMPLE tasks unless the task is reclassified.
- **developer** is the only agent authorised to implement approved changes.
- **reviewer** read-only; reports risks and validation evidence. Optional for
  SIMPLE, required for NORMAL and COMPLEX.
- No agent pushes, deploys, merges or rewrites Git history without explicit
  human authorisation.

## Complexity routing

- SIMPLE  -> Manager -> Developer -> deterministic checks.
- NORMAL  -> Manager -> Developer -> Reviewer -> Manager.
- COMPLEX -> Manager -> Graph on demand -> Developer -> Reviewer -> Manager.

Validation requirements depend on the selected complexity level. Developer
always runs the smallest meaningful deterministic checks; reviewer is
independent validation for NORMAL and COMPLEX, optional for SIMPLE.

## Escalation

Developer reports `ESCALATE: SIMPLE -> NORMAL` (one-line reason) when targeted
checks fail because of unexpected side effects, files go meaningfully outside
scope, a transversal dependency surfaces, or the actual risk exceeds the
estimate. Manager then applies NORMAL (reviewer required).

## Context Packet

Task state is passed as a compact Context Packet (TASK PACKET + DELIVERY
DELTA) on disk at `.ccb/tasks/<id>/`. The packet is a pointer to the brief,
scope, acceptance, constraints, changed files, validation and summary. It is
NOT a copy of the conversation history, the full diff, or full test logs.
The real repository and `git diff` remain the source of truth for code and
review evidence.

## Text-only collaboration

Use source code, DOM, HTML, CSS, textual SVG, logs, diffs and automated test
output. Do not open raster images or PDFs as images. Request human
authorisation when visual inspection is indispensable.