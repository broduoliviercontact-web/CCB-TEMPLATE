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
2. Do not run V2 directly over a V1 project without inspection.
3. Generate V2 in a separate temporary target; it refuses to overwrite an existing
   `.ccb/ccb.config`.
4. Compare the generated policy and memories with the V1 project.
5. Copy only useful, reviewed context manually into the V2 memories.
6. Preserve old runs and histories outside the new `.ccb` directory.
7. Validate the generated configuration with `ccb config validate` before starting CCB.

There is no automatic conversion of old runs, no automatic deletion and no automatic push or
deployment.
