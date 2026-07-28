# Migrating from V1.8.0 to V2

V1.8.0 grew into a separate orchestration runtime: its local `./ccb`, workflow snapshots,
provider router and direct Ollama execution duplicated responsibilities that belong to the
official CCB. V2 corrects that boundary by generating configuration and letting the official
global `ccb` manage Claude Code panes.

The V1 files have been removed from the V2 branch. `./ccb` no longer exists here: `ccb` always
means the official global binary. The complete V1.8.0 engine remains available from the
`v1.8.0` tag for historical reference and existing V1 projects.

The migration keeps the useful role boundaries, policy and shared and private memories as V2
assets. The removed surface includes the local wrapper, V1 CLI, provider router, direct Ollama
runtime, model presets, workflow snapshots, profiles, skills, prompts, manuals and their tests.

## Migrate an existing V1 project

1. Stop work and back up the complete existing `.ccb` directory outside the project.
2. Preserve any V1 runs, histories and custom memories; V2 does not delete them automatically.
3. Review which project constraints belong in the V2 shared and role memories.
4. Install V2 into a clean target path with `install.sh`; it refuses to overwrite an existing
   `.ccb/ccb.config`.
5. Compare the generated `.ccb/ccb.config`, then validate it with `ccb config validate`.
6. Start the official workspace with `ccb` only after validation succeeds.

There is no automatic conversion of old runs, no automatic deletion and no automatic push or
deployment.
