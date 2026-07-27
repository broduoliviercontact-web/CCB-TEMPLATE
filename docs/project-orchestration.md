# Sequential workflow automation

Run a snapshot with `./scripts/ccb.sh workflow run RUN_ID TARGET` or select the newest valid run with `--latest`. D2 repeatedly reloads and validates the run, resumes a ready step, executes an initial result, completes an explicit pending result, and continues until the run is completed.

The decision table is intentionally small: ready means resume; in-progress plus the initial result means execute; in-progress plus an explicit pending result means complete; completed is idempotent; blocked, cancelled, failed execution, running execution, or inconsistent data stops immediately. A retry prepared manually by `workflow retry-step` may continue through the same execution path. Automatic retries and parallel execution remain disabled.

`orchestration.conf` stores version, sequential mode, bounded status, timestamps, progress, action count, and a short error code. It never stores prompts, inputs, context, results, or provider responses. `.ccb-orchestration-lock` prevents concurrent automation and manual mutation. Status, Inspect, Config, and Doctor remain available.

Each resume, execution, and completion retains its own atomic-write or rollback guarantee. There is no global multi-step transaction: completed steps are durable checkpoints. Caught interruptions mark the session interrupted and release the lock; an uncatchable process stop can leave a lock for Doctor to report. Test hooks `after-resume`, `after-execute`, `after-complete`, `before-next-step`, and `before-success` are accepted only with `CCB_TEST_MODE=1`.

D2 uses loopback Ollama only. It performs no provider fallback, network access to remote hosts, shell interpretation of stored data, modification of project sources, or Git command. VERSION remains 1.7.0 and older runs need no migration.

`workflow cancel` refuses an active orchestration lock. D3 does not implement cooperative stop: once automation is no longer active, cancellation preserves `orchestration.conf` as `interrupted` with a bounded `cancelled-by-user` error. The run and current step are updated transactionally while execution results and archived attempts remain byte-identical.
