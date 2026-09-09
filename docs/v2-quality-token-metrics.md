# V2 Token and Quality Metrics

This is the observational layer. It links each token-monitored call to a
TASK PACKET when one exists, and stores a small outcome line per task. It
never touches prompts, responses, code, packets or secrets.

## Data collected

Per-call event appended to `.ccb/token-monitor/usage.jsonl` by the existing
`token-proxy.py`:

- `timestamp` (ISO UTC)
- `agent` (manager / graph / developer / reviewer)
- `model`
- `input_tokens`
- `output_tokens`
- `duration_ms`
- `task_id` (when the agent process forwarded it via the `X-CCB-Task-ID`
  request header; absent otherwise → unscoped)
- `complexity` (when forwarded via `X-CCB-Task-Complexity`; absent otherwise)

Per-task outcome line appended to `.ccb/token-monitor/outcomes.jsonl` via
`./ccb-template task outcome ...`:

- `task_id`
- `complexity`
- `status` (accepted / needs_fix / failed / abandoned)
- `tests` (pass / fail / unknown)
- `review` (pass / findings / skipped)
- `escalated` (true / false)
- `rework_count` (integer)
- `timestamp`

## Data never collected

- prompt contents
- response contents
- code, diffs, briefs
- TASK PACKET or DELIVERY DELTA contents
- any secret

The existing token-proxy guarantees already cover this; nothing new is added
that could capture more than numeric/id metadata.

## Commands

```sh
# Per-task report
./ccb-template monitor task TARGET TASK_ID

# Aggregate report across all tasks (per complexity + outcome metrics)
./ccb-template monitor tasks TARGET

# Record an outcome
./ccb-template task outcome TARGET TASK_ID \
  --status accepted|needs_fix|failed|abandoned \
  --tests pass|fail|unknown \
  --review pass|findings|skipped \
  --escalated true|false \
  --rework N
```

## Metrics formulas

| Metric | Formula |
| --- | --- |
| `tokens_per_accepted_task` | sum(input+output) for events with `task_id` matching accepted tasks / count(accepted tasks) |
| `acceptance_rate` | accepted / (tasks with outcomes) |
| `rework_rate` | tasks with `rework_count > 0` / (tasks with outcomes) |
| `reviewer_findings_rate` | tasks where `review=findings` / tasks where `review in (pass, findings)` |
| `escalation_rate` | tasks where `escalated=true` and complexity=simple / tasks with complexity=simple |

Division by zero is handled: when the denominator is 0, the metric is not
printed (no fake zero).

## Limits

- The proxy forwards whatever `X-CCB-Task-ID` / `X-CCB-Task-Complexity`
  headers it sees. Existing projects without those headers keep working
  unchanged; their events are simply unscoped and stay out of per-task
  metrics.
- Outcome is recorded explicitly by the user via `task outcome`. There is no
  silent automatic outcome inference; a SIMPLE escalation flag is recorded
  only when the user signals it.
- No token hard limit, no auto-skip, no model routing. Pure observation.