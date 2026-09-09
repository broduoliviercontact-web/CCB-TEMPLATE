#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-v2-telemetry.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# aiohttp is required by the token proxy and by the test harness.
PYTHON3=$(command -v python3 2>/dev/null || true)
[ -n "$PYTHON3" ] || fail 'python3 is required for the telemetry test'
if ! "$PYTHON3" -c 'import aiohttp' >/dev/null 2>&1; then
  # The token-proxy requires aiohttp, and so does this test's fake upstream.
  # We deliberately do not auto-install: the user already controls the
  # environment via the official CCB prerequisites (Python 3.10+ with
  # tomllib/tomli, aiohttp, cryptography). When aiohttp is missing, skip
  # the proxy-based sections with an explicit SKIPPED marker and run the
  # remaining aggregate / validation sections.
  SKIP_PROXY=1
else
  SKIP_PROXY=0
fi

sh -n "$ROOT/scripts/v2/metrics.sh" || fail 'metrics.sh has syntax errors'
"$PYTHON3" -m py_compile "$ROOT/scripts/v2/metrics_aggregate.py" \
  || fail 'metrics_aggregate.py has syntax errors'

PROJ=$WORK/proj
mkdir -p "$PROJ/.ccb/token-monitor" \
         "$PROJ/.ccb/tasks/A" "$PROJ/.ccb/tasks/B" "$PROJ/.ccb/tasks/C"
printf '# TASK PACKET\nTask id: A\nComplexity: simple\n\n' >"$PROJ/.ccb/tasks/A/task.md"
printf '# TASK PACKET\nTask id: B\nComplexity: normal\n\n' >"$PROJ/.ccb/tasks/B/task.md"
printf '# TASK PACKET\nTask id: C\nComplexity: simple\n\n' >"$PROJ/.ccb/tasks/C/task.md"
: >"$PROJ/.ccb/token-monitor/active-task"
printf '{}\n' >"$PROJ/.ccb/token-monitor/active-task"
: >"$PROJ/.ccb/token-monitor/outcomes.jsonl"
: >"$PROJ/.ccb/token-monitor/usage.jsonl"

# ---------------------------------------------------------------------------
# 1. REAL proxy attribution: spin up the production token-proxy.py against a
#    localhost fake upstream (aiohttp). Make a real POST /v1/messages.
# ---------------------------------------------------------------------------

if [ "$SKIP_PROXY" -eq 0 ]; then
  # Activate task A (initial=simple, current=simple).
  "$ROOT/ccb-template" task activate "$PROJ" A >/dev/null

  # Run the harness: it starts proxy + fake upstream, makes one call, exits.
  "$PYTHON3" "$ROOT/tests/_proxy_attr_harness.py" \
    "$PROJ/.ccb/token-monitor/active-task" \
    "$PROJ/.ccb/token-monitor/usage.jsonl" \
    "$ROOT/assets/token-proxy.py" || fail 'harness could not start the real proxy'

  # Validate the usage.jsonl line via Python json.loads (exact JSON structure).
  "$PYTHON3" - "$PROJ/.ccb/token-monitor/usage.jsonl" <<'PY' || fail 'real proxy produced no attributed line'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
assert lines, "no usage event"
event = lines[-1]
expected = {"task_id": "A", "initial_complexity": "simple",
            "current_complexity": "simple", "complexity": "simple",
            "input_tokens": 123, "output_tokens": 45}
for key, value in expected.items():
    assert event.get(key) == value, f"field {key!r}: got {event.get(key)!r}, expected {value!r}"
PY

  # -------------------------------------------------------------------------
  # 2. REAL unscoped proxy request: deactivate, then send a second call.
  # -------------------------------------------------------------------------
  "$ROOT/ccb-template" task deactivate "$PROJ" A >/dev/null

  "$PYTHON3" "$ROOT/tests/_proxy_attr_harness.py" \
    "$PROJ/.ccb/token-monitor/active-task" \
    "$PROJ/.ccb/token-monitor/usage.jsonl" \
    "$ROOT/assets/token-proxy.py" || fail 'harness could not restart for unscoped test'

  "$PYTHON3" - "$PROJ/.ccb/token-monitor/usage.jsonl" <<'PY' || fail 'unscoped event missing or attributed'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
event = lines[-1]
assert event.get("input_tokens") == 123, event
assert event.get("output_tokens") == 45, event
assert "task_id" not in event, f"unscoped event must not carry task_id: {event}"
assert "initial_complexity" not in event, event
assert "current_complexity" not in event, event
PY

  # -------------------------------------------------------------------------
  # Post-escalation attribution through the real proxy: lifecycle is driven
  # exclusively by public CLI calls. The active-task file is NEVER edited by
  # the test; the escalation outcome must update it on its own.
  # -------------------------------------------------------------------------
  : >"$PROJ/.ccb/token-monitor/usage.jsonl"
  # Reset any prior active-task so step "Before escalation" is observable.
  : >"$PROJ/.ccb/token-monitor/active-task"
printf '{}\n' >"$PROJ/.ccb/token-monitor/active-task"
  # Step 1: activate C (initial=simple, current=simple).
  "$ROOT/ccb-template" task activate "$PROJ" C >/dev/null
  "$PYTHON3" - "$PROJ/.ccb/token-monitor/active-task" <<'PY' || fail 'Before escalation: active-task not as expected'
import json, sys
from pathlib import Path
with Path(sys.argv[1]).open(encoding="utf-8") as source:
    document = json.load(source)
assert document["task_id"] == "C", document
assert document["initial_complexity"] == "simple", document
assert document["current_complexity"] == "simple", document
PY
  # Step 2: only the public outcome command runs.
  "$ROOT/ccb-template" task outcome "$PROJ" C \
    --status needs_fix --tests fail --review findings --escalated true --rework 1 >/dev/null
  # Step 3: needs_fix keeps C active. Verify current_complexity is now normal.
  "$PYTHON3" - "$PROJ/.ccb/token-monitor/active-task" <<'PY' || fail 'After escalation: active-task not updated'
import json, sys
from pathlib import Path
with Path(sys.argv[1]).open(encoding="utf-8") as source:
    document = json.load(source)
assert document["task_id"] == "C", document
assert document["initial_complexity"] == "simple", document
assert document["current_complexity"] == "normal", document
PY
  # Step 4: real proxy request. No manual edit of active-task between.
  "$PYTHON3" "$ROOT/tests/_proxy_attr_harness.py" \
    "$PROJ/.ccb/token-monitor/active-task" \
    "$PROJ/.ccb/token-monitor/usage.jsonl" \
    "$ROOT/assets/token-proxy.py" || fail 'harness could not start for post-escalation'
  "$PYTHON3" - "$PROJ/.ccb/token-monitor/usage.jsonl" <<'PY' || fail 'post-escalation proxy event incorrect'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
event = lines[-1]
assert event["task_id"] == "C", event
assert event["initial_complexity"] == "simple", event
assert event["current_complexity"] == "normal", event
assert event["complexity"] == "normal", event
assert event["input_tokens"] == 123, event
assert event["output_tokens"] == 45, event
PY
  # Step 5: needs_fix did NOT clear active-task.
  "$PYTHON3" - "$PROJ/.ccb/token-monitor/active-task" <<'PY' || fail 'needs_fix must not deactivate'
import json, sys
from pathlib import Path
with Path(sys.argv[1]).open(encoding="utf-8") as source:
    document = json.load(source)
assert document["task_id"] == "C", document
PY
  # Step 6: final accepted outcome deactivates the task.
  "$ROOT/ccb-template" task outcome "$PROJ" C \
    --status accepted --tests pass --review pass --escalated true --rework 1 >/dev/null
  "$PYTHON3" - "$PROJ/.ccb/token-monitor/active-task" <<'PY' || fail 'Final outcome: active-task should be cleared'
import json, sys
from pathlib import Path
with Path(sys.argv[1]).open(encoding="utf-8") as source:
    document = json.load(source)
assert document == {}, f"active-task should be empty, got: {document}"
PY
  # Step 7: a real proxy request after deactivation must be unscoped.
  "$PYTHON3" "$ROOT/tests/_proxy_attr_harness.py" \
    "$PROJ/.ccb/token-monitor/active-task" \
    "$PROJ/.ccb/token-monitor/usage.jsonl" \
    "$ROOT/assets/token-proxy.py" || fail 'harness could not start post-deactivation'
  "$PYTHON3" - "$PROJ/.ccb/token-monitor/usage.jsonl" <<'PY' || fail 'post-deactivation event should be unscoped'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
event = lines[-1]
assert "task_id" not in event, f"event must be unscoped: {event}"
assert event.get("input_tokens") == 123, event
assert event.get("output_tokens") == 45, event
PY
else
  printf '[SKIPPED] aiohttp not installed; proxy-based sections skipped\n'
fi

# ---------------------------------------------------------------------------
# 3. Exact metric assertions: deterministic fixture.
# ---------------------------------------------------------------------------

# Reset state for the aggregate section (independent of the proxy sections).
: >"$PROJ/.ccb/token-monitor/usage.jsonl"
"$ROOT/ccb-template" task deactivate "$PROJ" A >/dev/null 2>&1 || true

# Replace usage.jsonl with deterministic, hand-built attributed events.
cat >"$PROJ/.ccb/token-monitor/usage.jsonl" <<'EOF'
{"timestamp":"2026-09-09T10:00:00Z","agent":"developer","model":"kimi-k2.7-code:cloud","input_tokens":1000,"output_tokens":200,"duration_ms":1000,"task_id":"A","initial_complexity":"simple","current_complexity":"simple"}
{"timestamp":"2026-09-09T11:00:00Z","agent":"developer","model":"kimi-k2.7-code:cloud","input_tokens":3000,"output_tokens":500,"duration_ms":2000,"task_id":"B","initial_complexity":"normal","current_complexity":"normal"}
{"timestamp":"2026-09-09T11:30:00Z","agent":"developer","model":"kimi-k2.7-code:cloud","input_tokens":4000,"output_tokens":500,"duration_ms":2000,"task_id":"C","initial_complexity":"simple","current_complexity":"normal"}
EOF

# Replace outcomes.jsonl with three exact outcomes:
#   A: simple, accepted, escalated=false
#   B: normal, accepted, escalated=false
#   C: simple -> normal, needs_fix then accepted, escalated=true
cat >"$PROJ/.ccb/token-monitor/outcomes.jsonl" <<'EOF'
{"task_id":"A","initial_complexity":"simple","current_complexity":"simple","status":"accepted","tests":"pass","review":"skipped","escalated":"false","rework_count":0,"timestamp":"2026-09-09T10:01:00Z"}
{"task_id":"B","initial_complexity":"normal","current_complexity":"normal","status":"accepted","tests":"pass","review":"pass","escalated":"false","rework_count":0,"timestamp":"2026-09-09T11:01:00Z"}
{"task_id":"C","initial_complexity":"simple","current_complexity":"normal","status":"needs_fix","tests":"fail","review":"findings","escalated":"true","rework_count":1,"timestamp":"2026-09-09T11:31:00Z"}
{"task_id":"C","initial_complexity":"simple","current_complexity":"normal","status":"accepted","tests":"pass","review":"pass","escalated":"true","rework_count":1,"timestamp":"2026-09-09T11:40:00Z"}
EOF

# Compute the expected metrics in pure Python and assert they match exactly.
"$PYTHON3" - "$ROOT/ccb-template" "$PROJ" <<'PY'
import re, subprocess, sys

bin_path, proj = sys.argv[1], sys.argv[2]
def run(cmd):
    return subprocess.run([bin_path] + cmd, cwd=proj, capture_output=True, text=True, check=False).stdout

# tasks = latest-outcome per task_id. Inputs:
#   A accepted (simple)
#   B accepted (normal)
#   C accepted (simple -> normal)
# Expected:
#   SIMPLE accepted tasks: A (C was escalated, so initial=simple but the latest
#     outcome is accepted; both A and C have initial_complexity=simple)
#   SIMPLE accepted tokens: A (1000+200) = 1200
#   NORMAL accepted tasks: B
#   NORMAL accepted tokens: B (3000+500) = 3500
out_tasks = run(["monitor", "tasks", proj])

def find_metric_block(text, header):
    out = []
    capture = False
    for line in text.splitlines():
        if line.startswith(header):
            capture = True
            continue
        if capture and re.match(r"^  [A-Z]+:$", line):
            break
        if capture:
            out.append(line)
    return "\n".join(out)

# tokens_per_accepted_task exact:
#   SIMPLE accepted tasks: A (initial=simple) and C (initial=simple,
#     latest outcome=accepted)
#   SIMPLE accepted tokens: 1200 + 4500 = 5700 / 2 = 2850
#   NORMAL accepted tasks: B (initial=normal)
#   NORMAL accepted tokens: 3500 / 1 = 3500
simple_block = find_metric_block(out_tasks, "  SIMPLE:")
normal_block = find_metric_block(out_tasks, "  NORMAL:")

assert "tokens_per_accepted_task: 2,850" in simple_block, simple_block
assert "tokens_per_accepted_task: 3,500" in normal_block, normal_block

# acceptance_rate exact (SIMPLE has 2 tasks total: A accepted + C accepted -> 100%).
assert "acceptance_rate:    100.0%" in simple_block, simple_block
assert "acceptance_rate:    100.0%" in normal_block, normal_block

# escalation_rate exact: 1 SIMPLE task with escalated=true (C) out of 2
# SIMPLE tasks total (A and C) -> 50.0%.
assert "escalation_rate:    50.0%" in simple_block, simple_block

# NORMAL has no escalated task (B is not escalated) -> escalation_rate is not
# printed for NORMAL.
assert "escalation_rate:" not in normal_block, normal_block

# Latest-outcome exact: only the last outcome per task_id is counted.
# Outcomes: A accepted, B accepted, C accepted (last) -> accepted = 3, needs_fix = 0.
# Per-complexity:
#   SIMPLE: A accepted + C accepted (initial=simple) = 2 accepted, 0 needs_fix.
#   NORMAL: B accepted = 1 accepted, 0 needs_fix.
assert "outcomes: 2  accepted: 2  needs_fix: 0" in simple_block, simple_block
assert "outcomes: 1  accepted: 1  needs_fix: 0" in normal_block, normal_block

# rework_rate: SIMPLE has 1 task with rework_count=1 (C) out of 2 = 50.0%
# NORMAL has 0 with rework out of 1 = 0.0%
assert "rework_rate:        50.0%" in simple_block, simple_block
assert "rework_rate:        0.0%" in normal_block, normal_block

print("metric assertions OK")
PY

# ---------------------------------------------------------------------------
# 4. Privacy / enums / malformed lines / JSON parseability.
# ---------------------------------------------------------------------------

# Invalid enum rejection.
if "$ROOT/ccb-template" task outcome "$PROJ" A --status maybe >/dev/null 2>&1; then
  fail 'invalid status must be rejected'
fi
if "$ROOT/ccb-template" task outcome "$PROJ" A --tests success >/dev/null 2>&1; then
  fail 'invalid tests must be rejected'
fi
if "$ROOT/ccb-template" task outcome "$PROJ" A --review ok >/dev/null 2>&1; then
  fail 'invalid review must be rejected'
fi
if "$ROOT/ccb-template" task outcome "$PROJ" A --escalated yes >/dev/null 2>&1; then
  fail 'invalid escalated must be rejected'
fi
if "$ROOT/ccb-template" task outcome "$PROJ" A --rework -1 >/dev/null 2>&1; then
  fail 'invalid rework must be rejected'
fi
if "$ROOT/ccb-template" task outcome "$PROJ" "../escape" --status accepted >/dev/null 2>&1; then
  fail 'traversal task id must be rejected'
fi

# Malformed JSONL ignored without crash.
printf 'not-json\n' >>"$PROJ/.ccb/token-monitor/usage.jsonl"
"$ROOT/ccb-template" monitor tasks "$PROJ" >/dev/null || fail 'aggregate must tolerate malformed lines'

# Every line of outcomes.jsonl parses with json.loads.
"$PYTHON3" - "$PROJ/.ccb/token-monitor/outcomes.jsonl" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    json.loads(line)
PY

# Privacy: no prompt, response, code, packet, secrets in outcomes.
privacy=$(cat "$PROJ/.ccb/token-monitor/outcomes.jsonl")
case "$privacy" in
  *'as discussed'*|*'src/login.ts'*|*'TASK PACKET'*|*'DELIVERY DELTA'*|*'AKIA'*|*'BEGIN PRIVATE KEY'*|*'Bearer '*)
    fail 'outcome file leaks forbidden content' ;;
esac

echo '[OK] V2 telemetry tests passed'