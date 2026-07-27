# Workflow reliability and observability

V1.7.0-D3 keeps reliability explicit. `workflow retry-step RUN_ID TARGET` or `workflow retry-step --latest TARGET` archives the preceding failed metadata in `attempts/NNN.conf` and prepares the next attempt. It never invokes a provider and never retries automatically. The maximum is three attempts per step, and archives contain no prompt, response, Markdown body, token, cookie, or secret.

`workflow cancel RUN_ID TARGET` or `--latest` terminally cancels pending, in-progress, or blocked runs. A ready or pending current step becomes skipped; an in-progress step becomes blocked; an already blocked step remains blocked. Results, inputs, context, execution metadata, retry archives, and completed steps are retained. Cancelled runs cannot mutate again. Active sequential automation cannot be stopped cooperatively in D3 and must release its lock before cancellation.

Retry and cancellation prepare new metadata, validate it, publish each file atomically, and perform logical multi-file rollback on failure. POSIX replacement is atomic per file, not across the complete transaction. Fail-point hooks exist only under `CCB_TEST_MODE=1`.

`workflow history` reconstructs events from existing bounded metadata without storing a separate journal. Supported events are run creation/completion/cancellation, orchestration start/success/failure/interruption, step start/completion, execution success/failure, and retry preparation. Events use timestamp order plus a stable priority. Retry preparation has no dedicated timestamp and therefore shares the archived failure completion timestamp.

Config reports aggregate retry, cancellation, history, and orchestration counts. Doctor validates the same metadata, sequences, timestamps, locks, symlinks, and transaction residue. Both are read-only, never repair runs, never call a provider, and never display full errors or stored Markdown.

Only local loopback Ollama execution exists. Reliability and observability commands perform no remote network request, Git operation, project-source modification, Markdown interpretation, or shell evaluation. Existing D1/D2 runs without attempts or orchestration remain valid and require no migration. VERSION remains 1.7.0.
