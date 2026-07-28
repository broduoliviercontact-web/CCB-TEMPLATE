# Migration V2

## Lot 1 — completed

Lot 1 added a parallel bootstrap for the official
[Claude Code Bridge](https://github.com/SeemSeam/claude_codex_bridge). It does not start CCB,
Claude Code, tmux or a model. The legacy V1 CLI remains temporarily untouched.

`install.sh` checks the official global CCB version, local prerequisites and the five selected
Ollama Cloud models. It then creates the official `.ccb/ccb.config`, shared memory, role
memories and policy through atomic writes. Existing memories are preserved and an existing
`ccb.config` is a conflict.

The V2 configuration contains only the literal Ollama compatibility marker `ollama` and the
loopback endpoint. It never writes a bearer token or another user credential.

The official configuration is validated against CCB 8.4.3.

## Lot 2 — in progress

Lot 2 documents the official architecture and adds a separate V2 CI validation path while the V1
runtime remains temporarily available.
