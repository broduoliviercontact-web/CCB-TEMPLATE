# Declarative workflows

`.ccb/workflows.conf` describes ordered agent-role sequences. Use `ccb workflows`, `ccb workflow show`, `ccb workflow plan`, and `ccb workflow validate` to inspect them. `workflow start`, `resume`, and `complete-step` manage local run records, but execution remains disabled: no agent or provider is launched, and no network or Git operation is performed.

Workflows resolve roles from `agents.conf` and models from `models.conf`; they do not redefine either. Projects created before this capability remain readable but are not changed automatically.

Run state and literal context transfer are documented in [project runs](project-runs.md). There is no automatic C2-to-C3 migration.

`workflow execute-step` is the D1 single-step entry point. It requires an explicitly resumed step and supports only a loopback Ollama endpoint; `complete-step` remains the manual publication action.

D2 adds `workflow run`, a bounded sequential loop over those same internal operations. It supports an explicit run ID or `--latest`, stops at the first error, performs no retry, and resumes from persisted checkpoints without double execution. There is no parallelism, remote provider, background process, Git operation, source-project mutation, or interpretation of model output.
