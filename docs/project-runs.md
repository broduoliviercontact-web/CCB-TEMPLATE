# Persistent workflow runs — D3

`ccb workflow start NAME TARGET` materializes a local workflow snapshot in `.ccb/runs/`. `workflow status` and `workflow inspect` are read-only; every run-oriented command accepts an explicit run ID, while inspection, resume, and completion also accept `--latest`.

`workflow resume` changes the current `ready` or `blocked` step to `in-progress`. The caller then replaces the initial `result.md` template with an explicit result whose single status remains `pending`. Results are limited to 256 KiB. `workflow complete-step` validates that file, changes its status to `completed`, marks the current step complete, and activates the next step. The completed result is copied literally into the next `input.md`; it is never interpreted as Markdown, shell, or a command. A transferred input is limited to 512 KiB.

The state progression is `pending/ready → in-progress → completed`, with `blocked` resumable and terminal runs `completed` or `cancelled`. Between steps, a run is `in-progress` while its next step is `ready`.

Completion prepares every affected file first, keeps backups inside a private `.ccb-transaction.*` directory, then publishes the current `step.conf`, current `result.md`, next `input.md`, next `step.conf`, and `run.conf` in that order. Each replacement uses a same-directory temporary plus `mv`. A failure triggers logical multi-file rollback and validation before transaction cleanup. POSIX filesystems provide atomic replacement per file, not one atomic operation spanning all files; an unrecoverable process or storage failure can therefore still require manual inspection. Fail points are reserved for automated tests.

`workflow retry-step RUN_ID TARGET` and `workflow retry-step --latest TARGET` explicitly prepare the next attempt after a failed execution. The previous bounded metadata is archived as `attempts/NNN.conf`; prompts, responses, Markdown, provider details beyond the short error code, and secrets are never archived. Retry is manual only and the hard limit is three attempts per step.

`workflow cancel RUN_ID TARGET` and `workflow cancel --latest TARGET` terminate a pending, in-progress, or blocked run without deleting history. A current `pending` or `ready` step becomes `skipped`; an `in-progress` step becomes `blocked` to preserve its checkpoint; a blocked step remains blocked. A cancelled run cannot be resumed, executed, completed, retried, or automated. Active orchestration cannot yet be stopped cooperatively and must finish or release its lock before cancellation.

`workflow history RUN_ID TARGET` and `workflow history --latest TARGET` reconstruct a deterministic timeline from `run.conf`, `step.conf`, `execution.conf`, `attempts/NNN.conf`, and `orchestration.conf`. It creates no journal and never reads or prints Markdown bodies. Events are ordered by timestamp and a documented stable event priority. Because retry preparation has no dedicated persistent timestamp, its event uses the corresponding archived failure completion timestamp.

`ccb config TARGET` reports D3 reliability and observability counts without reading Markdown. Doctor validates run state, timestamps, results, transmission, retry archives, cancellation, orchestration, symlinks, locks, and transaction residue; `--strict` turns warnings into failure. Neither command repairs state or contacts a provider.

There is no migration for existing runs without retry archives or orchestration metadata. Progression and observability commands do not launch a provider, access the network, invoke Git, or execute stored content; D1 execution is the narrowly scoped local exception described below. V1.8.0 continues to accept V1.7.0 and V1.7.1 run metadata.

## D1 local execution

After `workflow resume`, `workflow execute-step RUN_ID TARGET` (or `--latest`) may execute exactly the current step through Ollama at `http://127.0.0.1:11434` or `http://localhost:11434`. All other endpoints are rejected. Connection and total timeouts are 5 and 120 seconds, redirects and proxies are disabled, and no retry is attempted. The command reads only the run's `context.md`, current `input.md`, and current `step.conf` snapshot. The bounded prompt is at most 1 MiB; the opaque response is at most 256 KiB and is atomically wrapped as a pending `result.md`. `execution.conf` records a bounded status without storing the prompt or HTTP response.

`workflow run RUN_ID TARGET` and `workflow run --latest TARGET` automate the existing `resume`, `execute-step`, and `complete-step` operations in strict sequence. The run directory is reloaded and validated before every decision. A successful execution is never repeated: an explicit pending result goes directly to completion, while a failed `execution.conf` stops with automatic retry disabled. The action limit is `step_count * 3 + 3`.

`orchestration.conf` is an atomically written, strictly parsed checkpoint containing only bounded metadata. `.ccb-orchestration-lock` excludes another automation and the three manual mutators, while status, inspect, config, and Doctor remain read-only. Each action keeps its existing atomicity; D2 is not one global transaction. A failure preserves completed steps and resumes from disk on a later invocation. Test-only fail points require `CCB_TEST_MODE=1`.

A per-run execution lock prevents concurrent provider calls. Doctor reports residual locks but never removes them. Provider failures leave run and step state unchanged and keep the prior result. The single-step command performs no automatic retry or completion; D2 supplies the separate bounded sequential loop. There is no project traversal, remote provider, shell execution, Git operation, or project write. Test-provider hooks work only when `CCB_TEST_MODE=1`.

`workflow status` reports current execution, retry availability, archive count, and cancellation state. `workflow inspect` reports bounded per-step attempt, archive, execution, cancellation, and orchestration metadata. Neither prints the prompt, context, input, result body, raw provider response, full error, or secrets.
