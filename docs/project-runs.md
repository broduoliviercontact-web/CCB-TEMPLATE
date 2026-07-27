# Persistent workflow runs — C1

`ccb workflow start NAME TARGET` materializes a local, immutable snapshot of a declarative workflow in `.ccb/runs/`. It creates `run.conf`, a bounded project context copy, and one directory per declared step. The run starts pending and its first step is ready.

C2 adds read-only `workflow status RUN_ID TARGET`, `workflow inspect RUN_ID TARGET`, and `--latest`. They validate the run directory and snapshot structure without modifying it. `resume` and `complete-step` remain unavailable. No command executes agents, models, prompts, providers, network requests, Git actions, or context progression.
