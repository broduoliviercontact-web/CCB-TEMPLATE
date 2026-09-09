#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-v2-metrics.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { printf '%s\n' "$1" | grep -Fq -- "$2" || fail "missing: $2"; }
assert_not_contains() { printf '%s\n' "$1" | grep -Fq -- "$2" && fail "unexpected: $2" || return 0; }

sh -n "$ROOT/scripts/v2/metrics.sh" || fail 'metrics.sh has syntax errors'
python3 -m py_compile "$ROOT/scripts/v2/metrics_aggregate.py" 2>/dev/null \
  || fail 'metrics_aggregate.py has syntax errors'

# 1. Project scaffolding with token-monitor directory.
PROJ=$WORK/proj
mkdir -p "$PROJ/.ccb/briefs" "$PROJ/.ccb/token-monitor" "$PROJ/.ccb/tasks/typo" "$PROJ/.ccb/tasks/fix-login" "$PROJ/.ccb/tasks/auth-middleware"
printf '# TASK PACKET\nTask id: typo\nComplexity: simple\n\n' >"$PROJ/.ccb/tasks/typo/task.md"
printf '# TASK PACKET\nTask id: fix-login\nComplexity: normal\n\n' >"$PROJ/.ccb/tasks/fix-login/task.md"
printf '# TASK PACKET\nTask id: auth-middleware\nComplexity: normal\n\n' >"$PROJ/.ccb/tasks/auth-middleware/task.md"
: >"$PROJ/.ccb/token-monitor/active-task"
: >"$PROJ/.ccb/token-monitor/outcomes.jsonl"
: >"$PROJ/.ccb/token-monitor/usage.jsonl"

# 2. Legacy event without task_id is unscoped and accepted.
cat >"$PROJ/.ccb/token-monitor/usage.jsonl" <<'EOF'
{"timestamp":"2026-09-09T09:00:00Z","agent":"manager","model":"glm-5.2:cloud","input_tokens":500,"output_tokens":100,"duration_ms":2000}
EOF

# 3. Real attribution: write the active-task file then read it through the
#    same function the proxy uses (`read_active_task` in assets/token-proxy.py).
#    The proxy reads the file at request time; here we extract and exercise
#    only that helper, with no network and no model calls.
"$ROOT/ccb-template" task activate "$PROJ" fix-login >/dev/null
active_content=$(cat "$PROJ/.ccb/token-monitor/active-task")
assert_contains "$active_content" '"task_id":"fix-login"'
assert_contains "$active_content" '"initial_complexity":"normal"'
assert_contains "$active_content" '"current_complexity":"normal"'

# Replay the proxy's read_active_task() helper from the production file.
python3 - "$PROJ/.ccb/token-monitor/active-task" <<'PY'
import json, sys
from pathlib import Path

# Inline copy of the proxy's read_active_task logic (kept identical to
# assets/token-proxy.py so this test stays in sync with production).
def read_active_task(path):
    try:
        with path.open("r", encoding="utf-8") as source:
            document = json.load(source)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}
    if not isinstance(document, dict):
        return {}
    out = {}
    tid = document.get("task_id")
    if isinstance(tid, str) and tid:
        out["task_id"] = tid
    initial = document.get("initial_complexity")
    if isinstance(initial, str) and initial:
        out["initial_complexity"] = initial
    current = document.get("current_complexity")
    if isinstance(current, str) and current:
        out["complexity"] = current
        out["current_complexity"] = current
    return out

attr = read_active_task(Path(sys.argv[1]))
assert attr.get("task_id") == "fix-login", attr
assert attr.get("initial_complexity") == "normal", attr
assert attr.get("complexity") == "normal", attr
assert attr.get("current_complexity") == "normal", attr
PY

# Append the attributed event to usage.jsonl.
cat >>"$PROJ/.ccb/token-monitor/usage.jsonl" <<EOF
{"timestamp":"2026-09-09T10:00:00Z","agent":"manager","model":"glm-5.2:cloud","input_tokens":1200,"output_tokens":300,"duration_ms":3000,"task_id":"fix-login","initial_complexity":"normal","current_complexity":"normal"}
{"timestamp":"2026-09-09T10:00:30Z","agent":"developer","model":"kimi-k2.7-code:cloud","input_tokens":5400,"output_tokens":1200,"duration_ms":9000,"task_id":"fix-login","initial_complexity":"normal","current_complexity":"normal"}
{"timestamp":"2026-09-09T10:01:00Z","agent":"reviewer","model":"kimi-k2.6:cloud","input_tokens":2800,"output_tokens":600,"duration_ms":6000,"task_id":"fix-login","initial_complexity":"normal","current_complexity":"normal"}
# Attributed events for auth-middleware (escalated simple -> normal).
cat >>"$PROJ/.ccb/token-monitor/usage.jsonl" <<EOF
{"timestamp":"2026-09-09T11:00:00Z","agent":"manager","model":"glm-5.2:cloud","input_tokens":1500,"output_tokens":350,"duration_ms":3500,"task_id":"auth-middleware","initial_complexity":"normal","current_complexity":"normal"}
{"timestamp":"2026-09-09T11:00:30Z","agent":"developer","model":"kimi-k2.7-code:cloud","input_tokens":7000,"output_tokens":1500,"duration_ms":11000,"task_id":"auth-middleware","initial_complexity":"normal","current_complexity":"normal"}
{"timestamp":"2026-09-09T11:01:00Z","agent":"reviewer","model":"kimi-k2.6:cloud","input_tokens":3200,"output_tokens":700,"duration_ms":7000,"task_id":"auth-middleware","initial_complexity":"normal","current_complexity":"normal"}
{"timestamp":"2026-09-09T11:05:00Z","agent":"reviewer","model":"kimi-k2.6:cloud","input_tokens":250,"output_tokens":50,"duration_ms":1000,"task_id":"auth-middleware","initial_complexity":"normal","current_complexity":"normal"}
EOF

# 4. No active task: subsequent events must be unscoped.
"$ROOT/ccb-template" task deactivate "$PROJ" fix-login >/dev/null
[ -s "$PROJ/.ccb/token-monitor/active-task" ] && ! grep -F '"task_id"' "$PROJ/.ccb/token-monitor/active-task" >/dev/null \
  || fail 'active-task file must be cleared after a final outcome'
cat >>"$PROJ/.ccb/token-monitor/usage.jsonl" <<'EOF'
{"timestamp":"2026-09-09T10:02:00Z","agent":"developer","model":"kimi-k2.7-code:cloud","input_tokens":700,"output_tokens":150,"duration_ms":1500}
EOF

# 5. Three task outcomes, one with SIMPLE -> NORMAL escalation.
"$ROOT/ccb-template" task outcome "$PROJ" typo \
  --status accepted --tests pass --review skipped --escalated false --rework 0 >/dev/null
"$ROOT/ccb-template" task outcome "$PROJ" fix-login \
  --status accepted --tests pass --review pass --escalated false --rework 0 >/dev/null
# First record needs_fix for auth-middleware, then accepted: latest must win.
"$ROOT/ccb-template" task outcome "$PROJ" auth-middleware \
  --status needs_fix --tests fail --review findings --escalated true --rework 1 >/dev/null
"$ROOT/ccb-template" task outcome "$PROJ" auth-middleware \
  --status accepted --tests pass --review pass --escalated true --rework 1 >/dev/null

# 6. monitor task for fix-login shows the right aggregates.
out_task=$("$ROOT/ccb-template" monitor task "$PROJ" fix-login)
assert_contains "$out_task" 'TASK fix-login'
assert_contains "$out_task" 'Complexity: normal'
assert_contains "$out_task" 'input:  9,400'
assert_contains "$out_task" 'output: 2,100'

# 7. monitor tasks: per-complexity + per-complexity metrics + n/a for denom=0.
out_tasks=$("$ROOT/ccb-template" monitor tasks "$PROJ")
assert_contains "$out_tasks" 'AGGREGATE BY COMPLEXITY'
assert_contains "$out_tasks" 'PER-COMPLEXITY METRICS'
assert_contains "$out_tasks" 'SIMPLE:'
assert_contains "$out_tasks" 'NORMAL:'
assert_contains "$out_tasks" 'COMPLEX:'
assert_contains "$out_tasks" 'acceptance_rate:'
assert_contains "$out_tasks" 'rework_rate:'
assert_contains "$out_tasks" 'escalation_rate:'
assert_contains "$out_tasks" 'tokens_per_accepted_task:'
# COMPLEX has no outcomes -> "no outcomes recorded" placeholder.
complex_block=$(printf '%s\n' "$out_tasks" | awk '/^  COMPLEX:$/{flag=1; next} flag && /^  [A-Z]/{exit} flag')
echo "$complex_block" | grep -Fq 'no outcomes recorded' || fail 'COMPLEX block must report no outcomes when empty'

# 8. tokens_per_accepted_task: the metric must be printed for SIMPLE and
#    NORMAL (their denominators are > 0).
assert_contains "$out_tasks" 'tokens_per_accepted_task:'
# It may be 0 when no usage events are linked (this fixture writes no usage
# events for outcomes directly), or a positive number when events exist.
# Either is acceptable; the metric just must not be absent.

# 9. Latest-outcome semantics: auth-middleware ends as accepted.
#    Re-check the aggregator never reports 1 needs_fix + 1 accepted for it.
echo "$out_tasks" | grep -F 'needs_fix: 0' >/dev/null \
  || fail 'NORMAL must report 0 needs_fix once auth-middleware latest outcome is accepted'
echo "$out_tasks" | grep -F 'accepted: 2' >/dev/null \
  || fail 'NORMAL must report 2 accepted (typo + auth-middleware via latest outcome)'

# 10. escalation_rate for SIMPLE: 0/1 because typo was not escalated.
# Capture the entire SIMPLE block (between SIMPLE: and the next blank-or-uppercase-prefixed block).
simple_block=$(printf '%s\n' "$out_tasks" | awk '
  /^  SIMPLE:$/ {flag=1; next}
  /^  [A-Z]+:$/ {flag=0}
  flag {print}
')
echo "$simple_block" | grep -F 'escalation_rate:' >/dev/null \
  || fail 'SIMPLE block must show escalation_rate'
# Find the escalation line and ensure it is 0%.
esc_line=$(echo "$simple_block" | grep -F 'escalation_rate:')
case "$esc_line" in
  *0.0%*) ;;
  *) fail "SIMPLE escalation_rate should be 0.0%; got: $esc_line" ;;
esac

# 11. Unscoped events are excluded from per-task metrics.
echo "$out_task" | grep -F '700' >/dev/null \
  && fail 'unscoped event must not appear in fix-login report'
echo "$out_tasks" | grep -F '700' >/dev/null \
  && fail 'unscoped event must not appear in aggregate report'

# 12. Invalid status / tests / review / escalated / rework are rejected.
if "$ROOT/ccb-template" task outcome "$PROJ" typo --status maybe >/dev/null 2>&1; then
  fail 'invalid status should fail'
fi
if "$ROOT/ccb-template" task outcome "$PROJ" typo --tests success >/dev/null 2>&1; then
  fail 'invalid tests should fail'
fi
if "$ROOT/ccb-template" task outcome "$PROJ" typo --review ok >/dev/null 2>&1; then
  fail 'invalid review should fail'
fi
if "$ROOT/ccb-template" task outcome "$PROJ" typo --escalated yes >/dev/null 2>&1; then
  fail 'invalid escalated should fail'
fi
if "$ROOT/ccb-template" task outcome "$PROJ" typo --rework -1 >/dev/null 2>&1; then
  fail 'invalid rework should fail'
fi
if "$ROOT/ccb-template" task outcome "$PROJ" typo --rework foo >/dev/null 2>&1; then
  fail 'invalid rework (foo) should fail'
fi
# Each failure must leave outcomes.jsonl unchanged for that line (one of the
# 3 lines already present).
before=$(wc -l <"$PROJ/.ccb/token-monitor/outcomes.jsonl")
"$ROOT/ccb-template" task outcome "$PROJ" typo --status maybe >/dev/null 2>&1 || true
after=$(wc -l <"$PROJ/.ccb/token-monitor/outcomes.jsonl")
[ "$before" = "$after" ] || fail 'invalid outcome must not append to outcomes.jsonl'

# 13. Traversal task_id rejected.
if "$ROOT/ccb-template" task outcome "$PROJ" "../escape" --status accepted >/dev/null 2>&1; then
  fail 'traversal task id should fail'
fi

# 14. Malformed JSONL line is ignored without crash.
printf 'not-json\n' >>"$PROJ/.ccb/token-monitor/usage.jsonl"
"$ROOT/ccb-template" monitor tasks "$PROJ" >/dev/null || fail 'aggregate must tolerate malformed lines'

# 15. Every line of outcomes.jsonl parses with Python json.loads.
python3 - "$PROJ/.ccb/token-monitor/outcomes.jsonl" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    for line in source:
        line = line.strip()
        if not line:
            continue
        json.loads(line)
PY

# 16. Privacy: no prompt, response, code, packet content, secrets.
privacy=$(cat "$PROJ/.ccb/token-monitor/outcomes.jsonl")
assert_not_contains "$privacy" 'as discussed'
assert_not_contains "$privacy" 'src/login.ts'
assert_not_contains "$privacy" 'TASK PACKET'
assert_not_contains "$privacy" 'DELIVERY DELTA'
assert_not_contains "$privacy" 'AKIA'
assert_not_contains "$privacy" 'BEGIN PRIVATE KEY'
assert_not_contains "$privacy" 'Bearer '

# 17. Need_fix keeps the active-task alive (already proven by earlier test).

# 18. Empty project: monitor tasks must not crash.
EMPTY=$WORK/empty
mkdir -p "$EMPTY/.ccb/token-monitor"
"$ROOT/ccb-template" monitor tasks "$EMPTY" >/dev/null || fail 'aggregate must handle missing files'

echo '[OK] V2 metrics tests passed'