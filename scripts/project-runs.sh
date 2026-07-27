#!/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/model-lib.sh"
. "$SCRIPT_DIR/project-config-lib.sh"
. "$SCRIPT_DIR/project-agents-lib.sh"
. "$SCRIPT_DIR/project-workflows-lib.sh"
. "$SCRIPT_DIR/project-runs-lib.sh"
. "$SCRIPT_DIR/runtime/runtime-lib.sh"
. "$SCRIPT_DIR/project-execution-lib.sh"
. "$SCRIPT_DIR/project-orchestration-lib.sh"

usage() {
  echo 'usage: ccb.sh workflow start|status|inspect|resume|execute-step|complete-step|run ...' >&2
  exit "${1:-2}"
}
now() {
  if [ "${CCB_TEST_MODE:-0}" = 1 ] && [ -n "${CCB_TEST_NOW:-}" ]; then
    case "$CCB_TEST_NOW" in ????-??-??T??:??:??[+-]????) printf '%s\n' "$CCB_TEST_NOW"; return 0;; *) return 1;; esac
  fi
  date '+%Y-%m-%dT%H:%M:%S%z'
}
stamp() {
  if [ -n "${CCB_TEST_RUN_TIMESTAMP:-}" ]; then
    stamp_date=${CCB_TEST_RUN_TIMESTAMP%%-*}; stamp_time=${CCB_TEST_RUN_TIMESTAMP#*-}
    case "$stamp_date$stamp_time" in *[!0-9]*) return 1;; esac
    [ "${#stamp_date}" -eq 8 ] && [ "${#stamp_time}" -eq 6 ] || return 1
    printf '%s\n' "$CCB_TEST_RUN_TIMESTAMP"; return 0
  fi
  date '+%Y%m%d-%H%M%S'
}
write_run() {
  file=$1
  temp=$(mktemp "$(dirname "$file")/.run.conf.tmp.XXXXXX") || return 1
  printf 'CCB_RUN_VERSION=1\nCCB_RUN_ID=%s\nCCB_RUN_WORKFLOW=%s\nCCB_RUN_STATUS=%s\nCCB_RUN_CURRENT_STEP=%s\nCCB_RUN_STEP_COUNT=%s\nCCB_RUN_CREATED_AT=%s\nCCB_RUN_UPDATED_AT=%s\nCCB_RUN_COMPLETED_AT=%s\nCCB_RUN_SOURCE_TEMPLATE_VERSION=1.7.0\nCCB_RUN_SOURCE_WORKFLOWS_VERSION=1\nCCB_RUN_SOURCE_AGENTS_VERSION=1\nCCB_RUN_SOURCE_MODELS_VERSION=1\n' \
    "$RUN_ID" "$RUN_WORKFLOW" "$RUN_STATUS" "$RUN_CURRENT" "$RUN_COUNT" \
    "$RUN_CREATED" "$RUN_UPDATED" "$RUN_COMPLETED" >"$temp" &&
    chmod 644 "$temp" && mv "$temp" "$file"
}
load_project() {
  target=$1
  [ -d "$target" ] && [ ! -L "$target" ] || return 1
  target=$(CDPATH= cd "$target" && pwd) || return 1
  project_models_parse "$target/.ccb/models.conf" &&
    project_agents_parse "$target/.ccb/agents.conf" &&
    project_workflows_parse "$target/.ccb/workflows.conf"
}
resolve_run_args() {
  requested=${1:-}; resolved_target=${2:-.}
  [ -n "$requested" ] || return 2
  resolved_target=$(CDPATH= cd "$resolved_target" 2>/dev/null && pwd) || return 1
  runs="$resolved_target/.ccb/runs"
  [ -d "$runs" ] && [ ! -L "$runs" ] || return 1
  if [ "$requested" = --latest ]; then
    resolved_id=$(run_latest_id "$runs") || return 1
  else
    run_id_is_valid "$requested" || return 2
    resolved_id=$requested
  fi
  resolved_dir="$runs/$resolved_id"
  run_validate_directory "$resolved_dir" || return 1
}
current_step_directory() {
  find "$resolved_dir" -maxdepth 1 -type d -name "$(printf '%02d' "$RUN_CURRENT")-*" -print
}

load_execution_summary() {
  execution_step_dir=$1
  EXECUTION_STATUS=none; EXECUTION_PROVIDER=none; EXECUTION_MODEL=none; EXECUTION_ATTEMPT=0
  EXECUTION_STARTED=; EXECUTION_COMPLETED=
  execution_summary_file="$execution_step_dir/execution.conf"
  if [ -e "$execution_summary_file" ] || [ -L "$execution_summary_file" ]; then
    project_execution_parse_conf "$execution_summary_file" || return 1
  fi
}

load_orchestration_summary() {
  ORCHESTRATION_STATUS=none; ORCHESTRATION_MODE=none; ORCHESTRATION_STARTED=; ORCHESTRATION_UPDATED=
  ORCHESTRATION_COMPLETED=; ORCHESTRATION_CURRENT=0; ORCHESTRATION_STEPS_COMPLETED=0
  ORCHESTRATION_STEP_COUNT=$RUN_COUNT; ORCHESTRATION_ACTIONS=0; ORCHESTRATION_ERROR=
  orchestration_summary_file="$resolved_dir/orchestration.conf"
  if [ -e "$orchestration_summary_file" ] || [ -L "$orchestration_summary_file" ]; then
    project_orchestration_parse_conf "$orchestration_summary_file" || return 1
  fi
}

complete_step_restore_all() {
  restored=0
  project_run_transaction_restore "$transaction_dir/current-step.conf.old" "$current_step_file" || restored=1
  project_run_transaction_restore "$transaction_dir/current-result.md.old" "$current_result_file" || restored=1
  if [ "$has_next_step" = 1 ]; then
    project_run_transaction_restore "$transaction_dir/next-input.md.old" "$next_input_file" || restored=1
    project_run_transaction_restore "$transaction_dir/next-step.conf.old" "$next_step_file" || restored=1
  fi
  project_run_transaction_restore "$transaction_dir/run.conf.old" "$run_file" || restored=1
  [ "$restored" -eq 0 ] || return 1
  cmp -s "$transaction_dir/current-step.conf.old" "$current_step_file" &&
    cmp -s "$transaction_dir/current-result.md.old" "$current_result_file" &&
    cmp -s "$transaction_dir/run.conf.old" "$run_file" || return 1
  if [ "$has_next_step" = 1 ]; then
    cmp -s "$transaction_dir/next-input.md.old" "$next_input_file" &&
      cmp -s "$transaction_dir/next-step.conf.old" "$next_step_file" || return 1
  fi
  run_validate_directory "$resolved_dir"
}

complete_step_abort() {
  trap - EXIT HUP INT TERM
  if [ "${transaction_started:-0}" = 1 ]; then
    if complete_step_restore_all && project_run_transaction_cleanup "$transaction_dir" "$resolved_dir"; then
      transaction_dir=
      echo 'error: workflow transaction failed and was rolled back' >&2
      orchestration_finish_on_exit 2>/dev/null || :
      exit 1
    fi
    echo 'error: workflow transaction rollback failed' >&2
    orchestration_finish_on_exit 2>/dev/null || :
    exit 1
  fi
  if [ -n "${transaction_dir:-}" ]; then
    project_run_transaction_cleanup "$transaction_dir" "$resolved_dir" || {
      echo 'error: workflow transaction cleanup failed' >&2
      exit 1
    }
  fi
  orchestration_finish_on_exit 2>/dev/null || :
  exit 1
}

complete_step_trap() {
  complete_step_abort
}

execution_lock_cleanup() {
  [ "${orchestration_internal:-0}" = 1 ] || trap - EXIT HUP INT TERM
  if [ "${execution_lock_created:-0}" = 1 ] && [ -n "${execution_lock_dir:-}" ] &&
    [ "$(dirname "$execution_lock_dir")" = "$resolved_dir" ] &&
    [ "$(basename "$execution_lock_dir")" = .ccb-execution-lock ] &&
    [ -d "$execution_lock_dir" ] && [ ! -L "$execution_lock_dir" ]; then
    [ ! -e "$execution_lock_dir/metadata" ] || { [ -f "$execution_lock_dir/metadata" ] && [ ! -L "$execution_lock_dir/metadata" ] && rm -f "$execution_lock_dir/metadata"; }
    if ! rmdir "$execution_lock_dir" 2>/dev/null; then return 1; fi
  fi
  execution_lock_created=0
}

automation_lock_refuse_manual() {
  [ "${orchestration_internal:-0}" != 1 ] || return 0
  lock="$resolved_dir/.ccb-orchestration-lock"
  if [ -e "$lock" ] || [ -L "$lock" ]; then
    echo 'error: workflow run is controlled by an active automation' >&2
    return 1
  fi
}

orchestration_remove_lock() {
  [ "${orchestration_lock_created:-0}" = 1 ] || return 0
  [ -d "$orchestration_lock_dir" ] && [ ! -L "$orchestration_lock_dir" ] || return 1
  [ ! -e "$orchestration_lock_dir/metadata" ] || { [ -f "$orchestration_lock_dir/metadata" ] && [ ! -L "$orchestration_lock_dir/metadata" ] && rm -f "$orchestration_lock_dir/metadata"; }
  rmdir "$orchestration_lock_dir" || return 1
  orchestration_lock_created=0
}

orchestration_finish_on_exit() {
  [ "${orchestration_active:-0}" = 1 ] || return 0
  trap - EXIT HUP INT TERM
  [ "${execution_lock_created:-0}" = 1 ] && execution_lock_cleanup 2>/dev/null || :
  run_parse_conf "$resolved_dir/run.conf" 2>/dev/null || :
  done_count=$(project_orchestration_count_completed "$resolved_dir" "${RUN_COUNT:-1}" 2>/dev/null || printf '0')
  finished=$(now)
  status=${orchestration_exit_status:-failed}; error=${orchestration_exit_error:-workflow-action-failed}
  project_orchestration_write_conf "$resolved_dir/orchestration.conf" "$status" "$orchestration_started" "$finished" "$finished" "${RUN_CURRENT:-1}" "$done_count" "${RUN_COUNT:-1}" "${orchestration_actions:-0}" "$error" 2>/dev/null || :
  orchestration_remove_lock 2>/dev/null || :
  orchestration_active=0
}

orchestration_arm_traps() {
  trap 'orchestration_finish_on_exit' EXIT
  trap 'orchestration_exit_status=interrupted; orchestration_exit_error=signal; orchestration_finish_on_exit; exit 1' HUP INT TERM
}

workflow_resume_current() {
  step_dir=$(current_step_directory); run_step_parse "$step_dir/step.conf" || return 1
  case "$RUN_STATUS:$STEP_STATUS" in
    in-progress:in-progress) echo '[OK] workflow run already in progress'; return 0;;
    pending:ready|in-progress:ready|blocked:blocked) :;;
    completed:*) echo 'error: workflow run is already completed' >&2; return 1;;
    cancelled:*) echo 'error: cancelled workflow run cannot be resumed' >&2; return 1;;
    *) echo 'error: run state cannot be resumed' >&2; return 1;;
  esac
  ts=$(now); STEP_STATUS=in-progress; [ -n "$STEP_STARTED" ] || STEP_STARTED=$ts
  run_write_step_conf "$step_dir/step.conf" || return 1
  RUN_STATUS=in-progress; RUN_UPDATED=$ts; write_run "$resolved_dir/run.conf" || return 1
  printf '[OK] workflow run resumed\nRun ID: %s\nStatus: in-progress\nCurrent step: %s — %s\nExecution: disabled\n' "$RUN_ID" "$RUN_CURRENT" "$STEP_ROLE"
}

orchestration_internal=0
dispatch() {
command=${1:-}
shift || :
case "$command" in
  start)
    name=${1:-}; target=${2:-.}; [ "$#" -le 2 ] || usage 2
    project_workflow_name_is_safe "$name" || usage 2
    load_project "$target" || { echo 'error: invalid project workflow configuration' >&2; exit 1; }
    project_workflow_details "$name" || exit 1
    runs="$target/.ccb/runs"
    [ ! -e "$runs" ] || { [ -d "$runs" ] && [ ! -L "$runs" ] || { echo 'error: unsafe runs directory' >&2; exit 1; }; }
    [ -d "$runs" ] || mkdir "$runs" || exit 1
    timestamp=$(stamp) || { echo 'error: invalid workflow timestamp' >&2; exit 2; }
    base="$timestamp-$name"; runid=$base; n=2
    while [ -e "$runs/$runid" ] || [ -L "$runs/$runid" ]; do runid="$base-$n"; n=$((n + 1)); done
    tmp=$(mktemp -d "$runs/.${runid}.tmp.XXXXXX") || exit 1
    created=$(now); RUN_ID=$runid; RUN_WORKFLOW=$name; RUN_STATUS=pending; RUN_CURRENT=1
    RUN_COUNT=$(printf '%s' "$PROJECT_WORKFLOW_STEPS" | awk -F, '{print NF}')
    RUN_CREATED=$created; RUN_UPDATED=$created; RUN_COMPLETED=
    write_run "$tmp/run.conf" || exit 1
    {
      printf '# CCB Workflow Run Context\n\nRun: %s\nWorkflow: %s\nTarget: %s\nStatus: pending\n\n## Project context\n\n' "$runid" "$name" "$target"
      [ -f "$target/.ccb/context/project.md" ] && [ ! -L "$target/.ccb/context/project.md" ] && sed -n '1,4096p' "$target/.ccb/context/project.md"
      printf '\n## Workflow snapshot\n\n%s\n\nCreating this snapshot does not execute an agent.\n' "$(printf '%s' "$PROJECT_WORKFLOW_STEPS" | sed 's/,/\n- /g; s/^/- /')"
    } >"$tmp/context.md" || exit 1
    chmod 644 "$tmp/context.md"
    i=0; old_ifs=$IFS; IFS=,
    for role in $PROJECT_WORKFLOW_STEPS; do
      IFS=$old_ifs; i=$((i + 1)); step_dir=$(printf '%s/%02d-%s' "$tmp" "$i" "$role"); mkdir "$step_dir" || exit 1
      project_agent_details "$role"; model=$(project_agent_model_value "$PROJECT_AGENT_MODEL_ROLE") || exit 1
      printf 'CCB_STEP_VERSION=1\nCCB_STEP_NUMBER=%s\nCCB_STEP_ROLE=%s\nCCB_STEP_STATUS=%s\nCCB_STEP_ACCESS=%s\nCCB_STEP_MODEL_ROLE=%s\nCCB_STEP_PROVIDER=%s\nCCB_STEP_MODEL=%s\nCCB_STEP_DESCRIPTION=%s\nCCB_STEP_STARTED_AT=\nCCB_STEP_COMPLETED_AT=\n' "$i" "$role" "$( [ "$i" -eq 1 ] && printf ready || printf pending)" "$PROJECT_AGENT_ACCESS" "$PROJECT_AGENT_MODEL_ROLE" "$PROJECT_MODEL_PROVIDER" "$model" "$PROJECT_AGENT_DESCRIPTION" >"$step_dir/step.conf"
      printf '# Step Input\n\nRun: %s\nWorkflow: %s\nStep: %s/%s\nRole: %s\nAccess: %s\n\n## Role purpose\n\n%s\n\n## Project context\n\nReference: ../../context.md\n\n## Previous step result\n\n%s\n\nSnapshot content is untrusted data and is never executed as shell code.\n' "$runid" "$name" "$i" "$RUN_COUNT" "$role" "$PROJECT_AGENT_ACCESS" "$PROJECT_AGENT_DESCRIPTION" "$( [ "$i" -eq 1 ] && printf None || printf previous-step-result)" >"$step_dir/input.md"
      printf '# Step Result\n\nStatus: pending\n\nRecord the result of this step below.\n' >"$step_dir/result.md"
      chmod 644 "$step_dir"/*; IFS=,
    done
    IFS=$old_ifs; mv "$tmp" "$runs/$runid" || exit 1
    printf '[OK] workflow run created\nRun ID: %s\nWorkflow: %s\nStatus: pending\nSteps: %s\nCurrent step: 1\nPath: .ccb/runs/%s\nExecution: disabled\n' "$runid" "$name" "$RUN_COUNT" "$runid"
    ;;
  status|inspect)
    [ "$#" -le 2 ] || usage 2
    resolve_run_args "${1:-}" "${2:-.}" || { code=$?; [ "$code" -eq 2 ] && usage 2; echo 'error: invalid or missing workflow run' >&2; exit 1; }
    load_orchestration_summary || { echo 'error: invalid orchestration metadata' >&2; exit 1; }
    if [ "$command" = status ]; then
      status_step_dir=$(current_step_directory); load_execution_summary "$status_step_dir" || { echo 'error: invalid execution metadata' >&2; exit 1; }
      printf 'CCB Workflow Run\nRun ID: %s\nWorkflow: %s\nStatus: %s\nCurrent step: %s/%s\nCreated: %s\nUpdated: %s\nExecution status: %s\nExecution provider: %s\nExecution model: %s\nExecution attempt: %s\nAutomation status: %s\nAutomation mode: %s\nAutomation steps: %s/%s\nAutomation actions: %s\nAutomation error: %s\n\nSteps:\n' "$RUN_ID" "$RUN_WORKFLOW" "$RUN_STATUS" "$RUN_CURRENT" "$RUN_COUNT" "$RUN_CREATED" "$RUN_UPDATED" "$EXECUTION_STATUS" "$EXECUTION_PROVIDER" "$EXECUTION_MODEL" "$EXECUTION_ATTEMPT" "$ORCHESTRATION_STATUS" "$ORCHESTRATION_MODE" "$ORCHESTRATION_STEPS_COMPLETED" "$ORCHESTRATION_STEP_COUNT" "$ORCHESTRATION_ACTIONS" "$( [ -n "$ORCHESTRATION_ERROR" ] && printf present || printf none)"
    else
      printf 'Run ID: %s\nPath: .ccb/runs/%s\nWorkflow: %s\nStatus: %s\nCurrent step: %s\nCreated: %s\nUpdated: %s\n' "$RUN_ID" "$RUN_ID" "$RUN_WORKFLOW" "$RUN_STATUS" "$RUN_CURRENT" "$RUN_CREATED" "$RUN_UPDATED"
    fi
    i=1
    while [ "$i" -le "$RUN_COUNT" ]; do
      step_dir=$(find "$resolved_dir" -maxdepth 1 -type d -name "$(printf '%02d' "$i")-*" -print); run_step_parse "$step_dir/step.conf" || exit 1
      if [ "$command" = status ]; then printf '%s. %-12s %s\n' "$i" "$STEP_ROLE" "$STEP_STATUS"
      else
        size=$(wc -c <"$step_dir/result.md" | tr -d ' ')
        printf '\nStep %s\n  Role: %s\n  Status: %s\n  Access: %s\n  Provider: %s\n  Model: %s\n  Input: %s/input.md\n  Result: %s/result.md (%s bytes)\n' "$i" "$STEP_ROLE" "$STEP_STATUS" "$STEP_ACCESS" "$STEP_PROVIDER" "$STEP_MODEL" "$(basename "$step_dir")" "$(basename "$step_dir")" "$size"
        load_execution_summary "$step_dir" || { echo 'error: invalid execution metadata' >&2; exit 1; }
        printf '  Execution\n    Status: %s\n' "$EXECUTION_STATUS"
        if [ "$EXECUTION_STATUS" != none ]; then
          printf '    Provider: %s\n    Model: %s\n    Attempt: %s\n    Started: %s\n    Completed: %s\n    Result: present\n    Result size: %s bytes\n' "$EXECUTION_PROVIDER" "$EXECUTION_MODEL" "$EXECUTION_ATTEMPT" "$EXECUTION_STARTED" "${EXECUTION_COMPLETED:-none}" "$size"
        fi
      fi
      i=$((i + 1))
    done
    if [ "$command" = inspect ]; then
      lock_status=absent; [ ! -e "$resolved_dir/.ccb-orchestration-lock" ] && [ ! -L "$resolved_dir/.ccb-orchestration-lock" ] || lock_status=present
      printf '\nAutomation\n  Status: %s\n  Mode: %s\n  Started: %s\n  Updated: %s\n  Completed: %s\n  Steps completed: %s/%s\n  Actions: %s\n  Error: %s\n  Lock: %s\n' "$ORCHESTRATION_STATUS" "$ORCHESTRATION_MODE" "${ORCHESTRATION_STARTED:-none}" "${ORCHESTRATION_UPDATED:-none}" "${ORCHESTRATION_COMPLETED:-none}" "$ORCHESTRATION_STEPS_COMPLETED" "$ORCHESTRATION_STEP_COUNT" "$ORCHESTRATION_ACTIONS" "$( [ -n "$ORCHESTRATION_ERROR" ] && printf present || printf none)" "$lock_status"
    fi
    ;;
  resume)
    [ "$#" -le 2 ] || usage 2
    resolve_run_args "${1:-}" "${2:-.}" || { code=$?; [ "$code" -eq 2 ] && usage 2; echo 'error: invalid workflow run' >&2; exit 1; }
    automation_lock_refuse_manual || exit 1
    workflow_resume_current || exit 1
    ;;
  execute-step)
    [ "$#" -le 2 ] || usage 2
    resolve_run_args "${1:-}" "${2:-.}" || { code=$?; [ "$code" -eq 2 ] && usage 2; echo 'error: invalid workflow run' >&2; exit 1; }
    automation_lock_refuse_manual || exit 1
    if [ "$orchestration_internal" != 1 ]; then
      trap 'execution_lock_cleanup' EXIT
      trap 'execution_lock_cleanup; exit 1' HUP INT TERM
    fi
    project_execution_run_current || exit 1
    ;;
  complete-step)
    [ "$#" -le 2 ] || usage 2
    resolve_run_args "${1:-}" "${2:-.}" || { code=$?; [ "$code" -eq 2 ] && usage 2; echo 'error: invalid workflow run' >&2; exit 1; }
    automation_lock_refuse_manual || exit 1
    [ "$RUN_STATUS" = in-progress ] || { echo 'error: workflow run is not in progress' >&2; exit 1; }
    step_dir=$(current_step_directory); run_step_parse "$step_dir/step.conf" || exit 1
    [ "$STEP_STATUS" = in-progress ] || { echo 'error: current step is not in progress' >&2; exit 1; }
    current_step_file="$step_dir/step.conf"; current_result_file="$step_dir/result.md"
    current_number=$STEP_NUMBER; current_role=$STEP_ROLE; current_step_name=$(basename "$step_dir")
    project_run_validate_pending_result "$current_result_file" || exit 1
    project_run_test_fail_point_is_valid || exit 1
    case "${CCB_TEST_FINAL_VALIDATION:-}" in ''|corrupt-run-status) :;; *) echo 'error: invalid workflow final-validation test hook' >&2; exit 1;; esac

    has_next_step=0; next_dir=; next_input_file=; next_step_file=; next_name=
    if [ "$RUN_CURRENT" -lt "$RUN_COUNT" ]; then
      has_next_step=1; next=$((RUN_CURRENT + 1))
      next_dir=$(find "$resolved_dir" -maxdepth 1 -type d -name "$(printf '%02d' "$next")-*" -print)
      run_step_parse "$next_dir/step.conf" || exit 1
      [ "$STEP_STATUS" = pending ] || { echo 'error: next step is not pending' >&2; exit 1; }
      next_number=$STEP_NUMBER; next_role=$STEP_ROLE; next_name=$(basename "$next_dir")
      next_input_file="$next_dir/input.md"; next_step_file="$next_dir/step.conf"
    fi

    transaction_dir=; transaction_started=0
    project_run_transaction_create "$resolved_dir" || { echo 'error: cannot create workflow transaction' >&2; exit 1; }
    trap 'complete_step_trap' EXIT HUP INT TERM
    prepared_current_step="$transaction_dir/current-step.conf.new"
    prepared_result_file="$transaction_dir/current-result.md.new"
    prepared_run="$transaction_dir/run.conf.new"
    run_file="$resolved_dir/run.conf"
    project_run_prepare_completed_result "$current_result_file" "$prepared_result_file" || complete_step_abort
    ts=$(now)
    run_step_parse "$current_step_file" || complete_step_abort
    STEP_STATUS=completed; STEP_COMPLETED=$ts
    project_run_write_step_prepared "$prepared_current_step" || complete_step_abort

    if [ "$has_next_step" = 1 ]; then
      prepared_next_input="$transaction_dir/next-input.md.new"
      prepared_next_step="$transaction_dir/next-step.conf.new"
      { sed '/^## Previous step result$/,$d' "$next_input_file"; printf '## Previous step result\n\nSource: ../%s/result.md\n\n----- BEGIN PREVIOUS RESULT -----\n' "$current_step_name"; cat "$prepared_result_file"; printf '%s\n\nNo agent is executed by CCB V1.7.0-C.\n' '----- END PREVIOUS RESULT -----'; } >"$prepared_next_input" || complete_step_abort
      chmod 600 "$prepared_next_input" || complete_step_abort
      run_step_parse "$next_step_file" || complete_step_abort
      STEP_STATUS=ready
      project_run_write_step_prepared "$prepared_next_step" || complete_step_abort
      RUN_CURRENT=$next; RUN_STATUS=in-progress; RUN_COMPLETED=
    else
      RUN_STATUS=completed; RUN_COMPLETED=$ts
    fi
    RUN_UPDATED=$ts
    project_run_write_run_prepared "$prepared_run" || complete_step_abort

    project_run_validate_current_step_prepared "$prepared_current_step" "$current_number" "$current_role" || complete_step_abort
    project_run_validate_completed_result "$prepared_result_file" || complete_step_abort
    if [ "$has_next_step" = 1 ]; then
      project_run_validate_next_step_prepared "$prepared_next_step" "$next_number" "$next_role" || complete_step_abort
      project_run_validate_transmission "$prepared_next_input" "$current_step_name" "$prepared_result_file" "$transaction_dir/transmission.check" || complete_step_abort
      project_run_validate_run_prepared "$prepared_run" "$next" in-progress empty || complete_step_abort
    else
      project_run_validate_run_prepared "$prepared_run" "$RUN_COUNT" completed required || complete_step_abort
    fi

    project_run_transaction_copy "$current_step_file" "$transaction_dir/current-step.conf.old" || complete_step_abort
    project_run_transaction_copy "$current_result_file" "$transaction_dir/current-result.md.old" || complete_step_abort
    if [ "$has_next_step" = 1 ]; then
      project_run_transaction_copy "$next_input_file" "$transaction_dir/next-input.md.old" || complete_step_abort
      project_run_transaction_copy "$next_step_file" "$transaction_dir/next-step.conf.old" || complete_step_abort
    fi
    project_run_transaction_copy "$run_file" "$transaction_dir/run.conf.old" || complete_step_abort
    transaction_started=1

    project_run_test_fail_point before-publish || complete_step_abort
    project_run_transaction_publish "$prepared_current_step" "$current_step_file" || complete_step_abort
    project_run_test_fail_point after-current-step || complete_step_abort
    project_run_transaction_publish "$prepared_result_file" "$current_result_file" || complete_step_abort
    project_run_test_fail_point after-result || complete_step_abort
    if [ "$has_next_step" = 1 ]; then
      project_run_transaction_publish "$prepared_next_input" "$next_input_file" || complete_step_abort
      project_run_test_fail_point after-next-input || complete_step_abort
      project_run_transaction_publish "$prepared_next_step" "$next_step_file" || complete_step_abort
      project_run_test_fail_point after-next-step || complete_step_abort
    fi
    project_run_test_fail_point before-run || complete_step_abort
    project_run_transaction_publish "$prepared_run" "$run_file" || complete_step_abort
    project_run_test_fail_point after-run || complete_step_abort

    if [ "${CCB_TEST_FINAL_VALIDATION:-}" = corrupt-run-status ]; then
      printf 'CCB_TEST_CORRUPTION=1\n' >>"$prepared_run"
      project_run_transaction_publish "$prepared_run" "$run_file" || complete_step_abort
    fi
    run_validate_directory "$resolved_dir" || complete_step_abort
    cmp -s "$prepared_current_step" "$current_step_file" && cmp -s "$prepared_result_file" "$current_result_file" && cmp -s "$prepared_run" "$run_file" || complete_step_abort
    if [ "$has_next_step" = 1 ]; then
      cmp -s "$prepared_next_input" "$next_input_file" && cmp -s "$prepared_next_step" "$next_step_file" || complete_step_abort
      project_run_validate_transmission "$next_input_file" "$current_step_name" "$current_result_file" "$transaction_dir/transmission.final" || complete_step_abort
    fi
    transaction_started=0
    project_run_transaction_cleanup "$transaction_dir" "$resolved_dir" || complete_step_abort
    transaction_dir=; trap - EXIT HUP INT TERM
    if [ "$has_next_step" = 1 ]; then
      printf '[OK] step completed\nRun ID: %s\nCompleted: %s\nNext: %s\nContext transferred: yes\nExecution: disabled\n' "$RUN_ID" "$current_step_name" "$next_name"
    else
      printf '[OK] workflow run completed\nRun ID: %s\nWorkflow: %s\nSteps completed: %s/%s\n' "$RUN_ID" "$RUN_WORKFLOW" "$RUN_COUNT" "$RUN_COUNT"
    fi
    ;;
  run)
    if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
      [ "$#" -eq 1 ] || usage 2
      echo 'usage: ccb.sh workflow run RUN_ID [TARGET] | ccb.sh workflow run --latest [TARGET]'
      return 0
    fi
    [ "$#" -le 2 ] || usage 2
    requested=${1:-}; target=${2:-.}
    resolve_run_args "$requested" "$target" || { code=$?; [ "$code" -eq 2 ] && usage 2; echo 'error: invalid or missing workflow run' >&2; exit 1; }
    orchestration_lock_dir="$resolved_dir/.ccb-orchestration-lock"
    if [ -e "$orchestration_lock_dir" ] || [ -L "$orchestration_lock_dir" ]; then
      if [ -d "$orchestration_lock_dir" ] && [ ! -L "$orchestration_lock_dir" ]; then echo 'error: workflow run automation is already locked' >&2
      else echo 'error: workflow run is controlled by an active automation' >&2; fi
      exit 1
    fi
    case "$RUN_STATUS" in
      completed)
        existing_orchestration=none
        if [ -e "$resolved_dir/orchestration.conf" ] || [ -L "$resolved_dir/orchestration.conf" ]; then
          project_orchestration_parse_conf "$resolved_dir/orchestration.conf" || { echo 'error: invalid orchestration metadata' >&2; exit 1; }
          existing_orchestration=$ORCHESTRATION_STATUS
        fi
        case "$existing_orchestration" in interrupted|failed|running) :;; *) echo '[OK] workflow run already completed'; exit 0;; esac
        ;;
      blocked) echo 'error: blocked workflow run cannot be automated' >&2; exit 1;;
      cancelled) echo 'error: cancelled workflow run cannot be automated' >&2; exit 1;;
      pending|in-progress) :;; *) echo 'error: invalid workflow run' >&2; exit 1;;
    esac
    orchestration_lock_created=0
    if ! mkdir "$orchestration_lock_dir" 2>/dev/null; then echo 'error: workflow run automation is already locked' >&2; exit 1; fi
    orchestration_lock_created=1
    chmod 700 "$orchestration_lock_dir" || { orchestration_remove_lock; exit 1; }
    orchestration_active=1; orchestration_internal=1; orchestration_actions=0
    orchestration_started=$(now); orchestration_exit_status=failed; orchestration_exit_error=workflow-action-failed
    printf 'RUN_ID=%s\nSTARTED_AT=%s\nPID=%s\n' "$RUN_ID" "$orchestration_started" "$$" >"$orchestration_lock_dir/metadata" || { orchestration_finish_on_exit; exit 1; }
    chmod 600 "$orchestration_lock_dir/metadata" || { orchestration_finish_on_exit; exit 1; }
    project_orchestration_fail_point_is_valid || { echo 'error: invalid workflow orchestration test hook' >&2; orchestration_finish_on_exit; exit 1; }
    done_count=$(project_orchestration_count_completed "$resolved_dir" "$RUN_COUNT") || { orchestration_finish_on_exit; exit 1; }
    project_orchestration_write_conf "$resolved_dir/orchestration.conf" running "$orchestration_started" "$orchestration_started" '' "$RUN_CURRENT" "$done_count" "$RUN_COUNT" 0 '' || { orchestration_finish_on_exit; exit 1; }
    orchestration_arm_traps
    printf 'Workflow automation\n===================\n\nRun ID: %s\nWorkflow: %s\nMode: sequential\nSteps: %s\nStarting step: %s\nExecution provider: local Ollama\nAutomatic retries: disabled\n\n' "$RUN_ID" "$RUN_WORKFLOW" "$RUN_COUNT" "$RUN_CURRENT"
    safe_limit=$((RUN_COUNT * 3 + 3))
    while [ "$orchestration_actions" -lt "$safe_limit" ]; do
      run_validate_directory "$resolved_dir" || { orchestration_exit_error=invalid-run; echo 'error: invalid workflow run' >&2; exit 1; }
      case "$RUN_STATUS" in
        completed)
          project_orchestration_test_interrupt before-success || exit 1
          done_count=$(project_orchestration_count_completed "$resolved_dir" "$RUN_COUNT") || exit 1
          finished=$(now)
          project_orchestration_write_conf "$resolved_dir/orchestration.conf" succeeded "$orchestration_started" "$finished" "$finished" "$RUN_COUNT" "$done_count" "$RUN_COUNT" "$orchestration_actions" '' || exit 1
          orchestration_active=0; trap - EXIT HUP INT TERM; orchestration_remove_lock || exit 1
          printf '[OK] workflow automation completed\nRun ID: %s\nStatus: completed\nProgress: %s/%s\nSteps executed: %s\nActions: %s\nExecution mode: sequential\nAutomatic retries: disabled\n' "$RUN_ID" "$done_count" "$RUN_COUNT" "$done_count" "$orchestration_actions"
          return 0;;
        blocked) orchestration_exit_error=blocked-run; echo 'error: blocked workflow run cannot be automated' >&2; exit 1;;
        cancelled) orchestration_exit_error=cancelled-run; echo 'error: cancelled workflow run cannot be automated' >&2; exit 1;;
      esac
      step_dir=$(current_step_directory); run_step_parse "$step_dir/step.conf" || { orchestration_exit_error=invalid-step; exit 1; }
      action=
      if [ "$STEP_STATUS" = ready ]; then action=resume
      elif [ "$STEP_STATUS" = in-progress ]; then
        result_file="$step_dir/result.md"; execution_file="$step_dir/execution.conf"
        if project_execution_result_is_template "$result_file"; then
          if [ -e "$execution_file" ] || [ -L "$execution_file" ]; then
            project_execution_parse_conf "$execution_file" || { orchestration_exit_error=invalid-execution; echo 'error: invalid execution metadata' >&2; exit 1; }
            case "$EXECUTION_STATUS" in
              failed) orchestration_exit_error=previous-execution-failed; echo 'error: workflow step execution previously failed; automatic retry is disabled' >&2; exit 1;;
              running) orchestration_exit_error=execution-running; echo 'error: workflow step execution is already running' >&2; exit 1;;
              succeeded) orchestration_exit_error=invalid-result; echo 'error: successful execution has no explicit result' >&2; exit 1;;
            esac
          fi
          action=execute-step
        elif project_run_validate_pending_result "$result_file"; then action=complete-step
        else orchestration_exit_error=invalid-result; echo 'error: invalid current workflow result' >&2; exit 1
        fi
      else orchestration_exit_error=invalid-state; echo 'error: workflow automation found an incoherent step state' >&2; exit 1
      fi
      orchestration_actions=$((orchestration_actions + 1))
      [ "$orchestration_actions" -le "$safe_limit" ] || { orchestration_exit_error=action-limit; echo 'error: workflow automation exceeded its safe action limit' >&2; exit 1; }
      printf '[%s/%s] %s %s\n' "$RUN_CURRENT" "$RUN_COUNT" "$action" "$STEP_ROLE"
      dispatch "$action" "$RUN_ID" "$resolved_target"
      orchestration_arm_traps
      case "$action" in
        resume) project_orchestration_test_interrupt after-resume || exit 1;;
        execute-step) project_orchestration_test_interrupt after-execute || exit 1;;
        complete-step) project_orchestration_test_interrupt after-complete || exit 1; project_orchestration_test_interrupt before-next-step || exit 1;;
      esac
      run_validate_directory "$resolved_dir" || { orchestration_exit_error=invalid-run; exit 1; }
      done_count=$(project_orchestration_count_completed "$resolved_dir" "$RUN_COUNT") || exit 1
      updated=$(now)
      project_orchestration_write_conf "$resolved_dir/orchestration.conf" running "$orchestration_started" "$updated" '' "$RUN_CURRENT" "$done_count" "$RUN_COUNT" "$orchestration_actions" '' || exit 1
    done
    orchestration_exit_error=action-limit
    echo 'error: workflow automation exceeded its safe action limit' >&2
    exit 1
    ;;
  *) usage 2;;
esac
}

dispatch "$@"
