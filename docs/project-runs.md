# Persistent workflow runs — C3

`ccb workflow start NAME TARGET` materializes a local workflow snapshot in `.ccb/runs/`. `workflow status` and `workflow inspect` are read-only; every run-oriented command accepts an explicit run ID, while inspection, resume, and completion also accept `--latest`.

`workflow resume` changes the current `ready` or `blocked` step to `in-progress`. The caller then replaces the initial `result.md` template with an explicit result whose single status remains `pending`. Results are limited to 256 KiB. `workflow complete-step` validates that file, changes its status to `completed`, marks the current step complete, and activates the next step. The completed result is copied literally into the next `input.md`; it is never interpreted as Markdown, shell, or a command. A transferred input is limited to 512 KiB.

The state progression is `pending/ready → in-progress → completed`, with `blocked` resumable and terminal runs `completed` or `cancelled`. Between steps, a run is `in-progress` while its next step is `ready`.

Completion prepares every affected file first, keeps backups inside a private `.ccb-transaction.*` directory, then publishes the current `step.conf`, current `result.md`, next `input.md`, next `step.conf`, and `run.conf` in that order. Each replacement uses a same-directory temporary plus `mv`. A failure triggers logical multi-file rollback and validation before transaction cleanup. POSIX filesystems provide atomic replacement per file, not one atomic operation spanning all files; an unrecoverable process or storage failure can therefore still require manual inspection. Fail points are reserved for automated tests.

`ccb config TARGET` reports run counts and latest status without reading Markdown. Doctor checks state, timestamps, results, transmission, symlinks, and transaction residue; `--strict` turns warnings into failure.

There is no C2-to-C3 migration. No workflow command launches an agent or provider, accesses the network, invokes Git, or executes stored content.
