#!/bin/sh
# Token and quality metrics helpers.
#
# Reads .ccb/token-monitor/usage.jsonl and .ccb/token-monitor/outcomes.jsonl
# (both append-only JSONL) and aggregates per task and per complexity level.
#
# All JSONL parsing is delegated to a small Python stdlib helper. This
# avoids hand-rolled awk parsers that previously had to deal with quotes,
# braces and trailing commas.

v2_metrics_dir() {
  printf '%s/.ccb/token-monitor\n' "$1"
}

v2_metrics_outcome_path() {
  printf '%s/.ccb/token-monitor/outcomes.jsonl\n' "$1"
}

v2_metrics_active_task_path() {
  printf '%s/.ccb/token-monitor/active-task\n' "$1"
}

# Locate a Python 3 interpreter; the token proxy and this helper both rely
# on the stdlib only (json, sys).
v2_metrics_python() {
  py=
  if [ -n "${CCB_PYTHON:-}" ]; then
    [ -x "$CCB_PYTHON" ] && py=$CCB_PYTHON
  fi
  if [ -z "$py" ]; then
    py=$(command -v python3 2>/dev/null || true)
  fi
  [ -n "$py" ] || {
    printf 'error: Python 3 is required for metrics aggregation.\n' >&2
    return 1
  }
  "$py" -c 'import json,sys' 2>/dev/null || {
    printf 'error: %s cannot import json+sys from stdlib.\n' "$py" >&2
    return 1
  }
  printf '%s\n' "$py"
}

# Path to the Python aggregator script.
v2_metrics_python_script() {
  printf '%s\n' "$ROOT/scripts/v2/metrics_aggregate.py"
}

# v2_metrics_aggregate <python> <usage_jsonl> <outcomes_jsonl> <query> [args...]
# Query is one of:
#   task <task_id>
#   tasks
# Calls into metrics_aggregate.py and prints the report.
v2_metrics_aggregate() {
  _py=$1 _usage=$2 _outcomes=$3; shift 3
  _script=$(v2_metrics_python_script)
  "$_py" "$_script" "$_usage" "$_outcomes" "$@"
}

# v2_metrics_report_task <target> <task_id>
v2_metrics_report_task() {
  _target=$1 _task=$2
  _dir=$(v2_metrics_dir "$_target")
  _usage=$_dir/usage.jsonl
  _outcomes=$_dir/outcomes.jsonl
  _py=$(v2_metrics_python) || return 1
  v2_metrics_aggregate "$_py" "$_usage" "$_outcomes" task "$_task"
}

# v2_metrics_report_tasks <target>
v2_metrics_report_tasks() {
  _target=$1
  _dir=$(v2_metrics_dir "$_target")
  _usage=$_dir/usage.jsonl
  _outcomes=$_dir/outcomes.jsonl
  _py=$(v2_metrics_python) || return 1
  v2_metrics_aggregate "$_py" "$_usage" "$_outcomes" tasks
}

# Append one outcome line. The line MUST be a valid JSON object produced by
# json.dumps; we never concatenate strings by hand to build it.
v2_metrics_append_outcome() {
  _target=$1 _line=$2
  _dir=$(v2_metrics_dir "$_target")
  [ -d "$_dir" ] && [ ! -L "$_dir" ] || {
    printf 'error: token monitor directory is missing: %s\n' "$_dir" >&2
    return 1
  }
  _out=$(v2_metrics_outcome_path "$_target")
  [ ! -L "$_out" ] || { printf 'error: unsafe outcomes file.\n' >&2; return 1; }
  touch "$_out"
  chmod 600 "$_out" 2>/dev/null || true
  # Validate that the line is JSON before appending.
  _py=$(v2_metrics_python) || return 1
  if ! "$_py" -c "import json,sys; json.loads(sys.argv[1])" "$_line" >/dev/null 2>&1; then
    printf 'error: outcome line is not valid JSON.\n' >&2
    return 1
  fi
  printf '%s\n' "$_line" >>"$_out"
}

# v2_metrics_set_active <target> <task_id> <initial_complexity> <current_complexity>
v2_metrics_set_active() {
  _target=$1 _task=$2 _initial=$3 _current=$4
  _path=$(v2_metrics_active_task_path "$_target")
  [ -e "$_path" ] || [ -L "$_path" ] || {
    printf 'error: active-task file is missing; re-run the template installer.\n' >&2
    return 1
  }
  [ ! -L "$_path" ] || { printf 'error: unsafe active-task file.\n' >&2; return 1; }
  _py=$(v2_metrics_python) || return 1
  # Use Python to build the JSON atomically; this guarantees correct
  # escaping if a task_id ever contains a quote or backslash.
  "$_py" - "$_path" "$_task" "$_initial" "$_current" <<'PY'
import json, sys, os
path, task_id, initial, current = sys.argv[1:5]
document = {"task_id": task_id, "initial_complexity": initial, "current_complexity": current}
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as destination:
    json.dump(document, destination, ensure_ascii=False, separators=(",", ":"))
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY
}

# v2_metrics_clear_active <target>
v2_metrics_clear_active() {
  _target=$1
  _path=$(v2_metrics_active_task_path "$_target")
  [ ! -L "$_path" ] || { printf 'error: unsafe active-task file.\n' >&2; return 1; }
  _py=$(v2_metrics_python) || return 1
  "$_py" - "$_path" <<'PY'
import json, os, sys
path = sys.argv[1]
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as destination:
    json.dump({}, destination, ensure_ascii=False, separators=(",", ":"))
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY
}

# v2_metrics_outcome_final_status <target> <task_id>
# Returns the LAST outcome status for the task_id, or "n/a" if none.
v2_metrics_outcome_final_status() {
  _target=$1 _task=$2
  _path=$(v2_metrics_outcome_path "$_target")
  [ -f "$_path" ] || { printf 'n/a\n'; return 0; }
  _py=$(v2_metrics_python) || return 1
  "$_py" - "$_path" "$_task" <<'PY'
import json, sys
path, task_id = sys.argv[1], sys.argv[2]
last = None
with open(path, encoding="utf-8") as source:
    for line in source:
        line = line.strip()
        if not line:
            continue
        try:
            document = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(document, dict) and document.get("task_id") == task_id:
            last = document.get("status") or "n/a"
print(last if last is not None else "n/a")
PY
}