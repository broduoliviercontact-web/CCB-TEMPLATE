# Persistent workflow runs — C3

`ccb workflow start NAME TARGET` materializes a local workflow snapshot in `.ccb/runs/`. `workflow status` and `workflow inspect` are read-only; every run-oriented command accepts an explicit run ID, while inspection, resume, and completion also accept `--latest`.

`workflow resume` changes the current `ready` or `blocked` step to `in-progress`. The caller then replaces the initial `result.md` template with an explicit result whose single status remains `pending`. Results are limited to 256 KiB. `workflow complete-step` validates that file, changes its status to `completed`, marks the current step complete, and activates the next step. The completed result is copied literally into the next `input.md`; it is never interpreted as Markdown, shell, or a command. A transferred input is limited to 512 KiB.

The state progression is `pending/ready → in-progress → completed`, with `blocked` resumable and terminal runs `completed` or `cancelled`. Between steps, a run is `in-progress` while its next step is `ready`.

Completion prepares every affected file first, keeps backups inside a private `.ccb-transaction.*` directory, then publishes the current `step.conf`, current `result.md`, next `input.md`, next `step.conf`, and `run.conf` in that order. Each replacement uses a same-directory temporary plus `mv`. A failure triggers logical multi-file rollback and validation before transaction cleanup. POSIX filesystems provide atomic replacement per file, not one atomic operation spanning all files; an unrecoverable process or storage failure can therefore still require manual inspection. Fail points are reserved for automated tests.

`ccb config TARGET` reports run counts and latest status without reading Markdown. Doctor checks state, timestamps, results, transmission, symlinks, and transaction residue; `--strict` turns warnings into failure.

There is no C2-to-C3 migration. Progression commands do not launch a provider, access the network, invoke Git, or execute stored content; D1 execution is the narrowly scoped local exception described below.

## D1 local execution

After `workflow resume`, `workflow execute-step RUN_ID TARGET` (or `--latest`) may execute exactly the current step through Ollama at `127.0.0.1:11434`. It reads only the run's `context.md`, current `input.md`, and current `step.conf` snapshot. The bounded prompt is at most 1 MiB; the opaque response is at most 256 KiB and is atomically wrapped as a pending `result.md`. `execution.conf` records a bounded status without storing the prompt or HTTP response.

A per-run directory lock prevents concurrent execution. Doctor reports residual locks but never removes them. Provider failures leave run and step state unchanged and keep the prior result. There are no automatic retries, completion, workflow loops, project traversal, remote providers, shell execution, Git operations, or project writes. Test-provider hooks work only when `CCB_TEST_MODE=1`.
