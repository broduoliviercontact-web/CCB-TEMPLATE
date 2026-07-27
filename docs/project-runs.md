# Persistent workflow runs — C1

`ccb workflow start NAME TARGET` materializes a local, immutable snapshot of a declarative workflow in `.ccb/runs/`. It creates `run.conf`, a bounded project context copy, and one directory per declared step. The run starts pending and its first step is ready.

C1 does not execute agents, models, prompts, providers, network requests, Git actions, or context progression. `status`, `inspect`, `resume`, and `complete-step` are reserved for later C sub-lots and fail explicitly.
