# Migration V2

## Lot 1 — completed

Lot 1 added a parallel bootstrap for the official
[Claude Code Bridge](https://github.com/SeemSeam/claude_codex_bridge). It does not start CCB,
Claude Code, tmux or a model.

`install.sh` checks the official global CCB version, local prerequisites and the five selected
Ollama Cloud models. It then creates the official `.ccb/ccb.config`, shared memory, role
memories and policy through atomic writes. Existing memories are preserved and an existing
`ccb.config` is a conflict.

The V2 configuration contains only the literal Ollama compatibility marker `ollama` and the
loopback endpoint. It never writes a bearer token or another user credential.

The official configuration is validated against CCB 8.4.3.

## Lot 2 — completed

Lot 2 documents the official architecture and validates the V2 bootstrap in CI without Cloud
tests.

## Lot 3A — completed

Lot 3A removed the local `./ccb` wrapper, all V1 runtime scripts, direct Ollama execution,
home-grown workflow snapshots, V1 model and project presets, their dedicated tests and their CI
steps. The V2 branch now exposes only `install.sh`, `scripts/v2/` and the official global `ccb`
workflow. V1.8.0 remains preserved by the `v1.8.0` tag.

## Lot 3B — completed

Lot 3B removes remaining V1-only manuals, prompts, profiles, skills, examples and generated
analysis artifacts. It adds a no-network clean-tree test so the V2 branch remains limited to the
official bootstrap and assets it actually installs.

## Lot 3C — completed

Lot 3C prepares the 2.0.0 release metadata, release checks and clean-clone validation. The branch
is ready for review, push and a pull request, but none of those actions is automatic.
