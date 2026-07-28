#!/bin/sh
# Read-only diagnostics for the CCB template and compatible bootstrap projects.
set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/model-lib.sh"
. "$SCRIPT_DIR/project-profile-lib.sh"
. "$SCRIPT_DIR/project-config-lib.sh"
. "$SCRIPT_DIR/project-skills-lib.sh"
. "$SCRIPT_DIR/project-agents-lib.sh"
. "$SCRIPT_DIR/project-workflows-lib.sh"
. "$SCRIPT_DIR/project-runs-lib.sh"
. "$SCRIPT_DIR/runtime/runtime-lib.sh"
. "$SCRIPT_DIR/project-execution-lib.sh"
. "$SCRIPT_DIR/project-orchestration-lib.sh"

strict=0
no_ollama=0
format=text
target=
ok_count=0 warn_count=0 fail_count=0 skip_count=0

usage() {
  cat >&2 <<'EOF'
usage: ccb.sh doctor [TARGET] [OPTIONS]

Read-only diagnostics for this template, and optionally a bootstrapped project.

Options:
  --strict          Treat WARN results as an exit status 1
  --no-ollama       Skip local Ollama checks
  --format text     Use stable plain-text output (the only supported format)
  -h, --help        Show this help
EOF
  exit "${1:-2}"
}

emit() {
  status=$1 id=$2 message=$3
  printf '[%s] %s — %s\n' "$status" "$id" "$message"
  case "$status" in OK) ok_count=$((ok_count + 1));; WARN) warn_count=$((warn_count + 1));; FAIL) fail_count=$((fail_count + 1));; SKIP) skip_count=$((skip_count + 1));; esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage 0;; --strict) strict=1;; --no-ollama) no_ollama=1;;
    --format) shift; [ "$#" -gt 0 ] || usage 2; format=$1; [ "$format" = text ] || { echo "error: unsupported format: $format" >&2; exit 2; };;
    -*) echo "error: unknown option: $1" >&2; usage 2;;
    *) [ -z "$target" ] || { echo 'error: only one TARGET is accepted' >&2; usage 2; }; target=$1;;
  esac
  shift
done

printf 'CCB Doctor\n'
if [ -n "$target" ]; then
  template_version=
  if [ ! -d "$target" ] || [ -L "$target" ]; then echo 'error: TARGET must be a real directory' >&2; exit 2; fi
  target=$(CDPATH= cd "$target" && pwd) || exit 2
  printf 'Target: %s\n' "$target"
else
  printf 'Target: template-only\n'
fi

for tool in sh sed grep awk mktemp mv chmod mkdir rm basename dirname; do
  if command -v "$tool" >/dev/null 2>&1; then emit OK "shell.$tool" available; else emit FAIL "shell.$tool" missing; fi
done

if [ -f "$TEMPLATE_ROOT/VERSION" ] && [ "$(cat "$TEMPLATE_ROOT/VERSION")" = 1.8.0 ]; then emit OK template.version 1.8.0; else emit FAIL template.version 'expected 1.8.0'; fi
for script in scripts/ccb.sh scripts/project-init.sh scripts/project-config.sh scripts/project-agents.sh scripts/project-workflows.sh scripts/project-runs.sh scripts/project-execution-lib.sh scripts/project-orchestration-lib.sh scripts/provider-router.sh scripts/runtime/provider-ollama.sh scripts/project-upgrade.sh scripts/validate-ccb.sh; do
  if [ -x "$TEMPLATE_ROOT/$script" ]; then emit OK "template.$script" executable; else emit FAIL "template.$script" missing-or-not-executable; fi
  if [ -f "$TEMPLATE_ROOT/$script" ] && sh -n "$TEMPLATE_ROOT/$script" >/dev/null 2>&1; then emit OK "syntax.$script" valid; else emit FAIL "syntax.$script" invalid; fi
done
for profile in generic web node python audio; do
  if project_profile_parse "$TEMPLATE_ROOT/project-profiles/$profile.conf" && [ "$PROJECT_PROFILE_ID" = "$profile" ]; then emit OK "template.profile.$profile" valid; else emit FAIL "template.profile.$profile" invalid; fi
done
for file in docs/project-bootstrap.md docs/project-skills.md docs/project-runs.md docs/project-execution.md docs/project-orchestration.md docs/project-upgrade.md docs/ponytail.md docs/doctor.md docs/v1.6.0.md docs/v1.6.1.md tests/test-doctor.sh tests/test-project-retry.sh tests/test-project-cancel.sh tests/test-project-history.sh tests/test-project-execution.sh tests/test-project-orchestration.sh tests/test-project-upgrade.sh .github/workflows/validate.yml; do
  [ -s "$TEMPLATE_ROOT/$file" ] && emit OK "template.$file" present || emit FAIL "template.$file" missing
done
if command -v git >/dev/null 2>&1; then
  emit OK git.command available
  if [ -z "$target" ] && git -C "$TEMPLATE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -n "$(git -C "$TEMPLATE_ROOT" status --porcelain 2>/dev/null)" ]; then emit WARN git.template working-tree-dirty; else emit OK git.template working-tree-clean; fi
  else emit SKIP git.template not-a-repository; fi
else emit WARN git.command unavailable; fi

file_mode() {
  mode=$(stat -f '%Lp' "$1" 2>/dev/null) || mode=
  case "$mode" in [0-7][0-7][0-7]) printf '%s\n' "$mode"; return 0;; esac
  stat -c '%a' "$1" 2>/dev/null || return 1
}
check_managed_file() {
  path=$1 id=$2
  if [ "$id" = project.skills_conf ] && [ ! -e "$path" ] && [ ! -L "$path" ] && grep -Fqx 'CCB_TEMPLATE_VERSION=1.6.0' "$target/.ccb/project.conf" 2>/dev/null; then emit WARN "$id" legacy-not-configured
  elif [ "$id" = project.agents_conf ] && [ ! -e "$path" ] && [ ! -L "$path" ] && { grep -Fqx 'CCB_TEMPLATE_VERSION=1.6.0' "$target/.ccb/project.conf" 2>/dev/null || grep -Fqx 'CCB_TEMPLATE_VERSION=1.6.1' "$target/.ccb/project.conf" 2>/dev/null; }; then emit WARN "$id" legacy-not-configured
  elif [ -L "$path" ]; then emit FAIL "$id" symbolic-link
  elif [ ! -f "$path" ]; then emit FAIL "$id" missing-or-not-regular
  elif [ ! -r "$path" ]; then emit WARN "$id" unreadable
  else
    emit OK "$id" present
    mode=$(file_mode "$path") || mode=
    if [ -z "$mode" ]; then emit SKIP "$id.permissions" stat-unavailable
    elif [ "$mode" = 644 ]; then emit OK "$id.permissions" 644
    else emit WARN "$id.permissions" "$mode"; fi
  fi
}

doctor_check_workflow_runs() {
  runs_dir="$target/.ccb/runs"
  if [ ! -e "$runs_dir" ] && [ ! -L "$runs_dir" ]; then emit OK project.runs absent; return; fi
  if [ ! -d "$runs_dir" ] || [ -L "$runs_dir" ]; then emit WARN project.runs unsafe; return; fi
  emit OK project.runs present
  residual=$(find "$runs_dir" \( -name '.ccb-transaction.*' -o -name '.ccb-retry-transaction.*' -o -name '*.old' -o -name '*.new' -o -name '.ccb-publish.*' -o -name '.retry-publish.*' -o -name '.ccb-backup*' \) -print -quit)
  [ -z "$residual" ] && emit OK project.runs.transactions clean || emit WARN project.runs.transactions residual
  unsafe_entry=$(find "$runs_dir" \( -type l -o \( ! -type f ! -type d \) \) -print -quit)
  [ -z "$unsafe_entry" ] && emit OK project.runs.entries regular || emit WARN project.runs.entries unsafe
  execution_lock=$(find "$runs_dir" -name '.ccb-execution-lock' -print -quit)
  execution_residual=$(find "$runs_dir" \( -name '.result.md.execution-*' -o -name '.execution.conf.tmp.*' -o -name '*.prompt.tmp' -o -name '*.response.tmp' \) -print -quit)
  [ -z "$execution_residual" ] && emit OK project.runs.execution_files clean || emit WARN project.runs.execution_files residual
  found=0; running_execution=0
  for run_dir in "$runs_dir"/*; do
    [ -e "$run_dir" ] || [ -L "$run_dir" ] || continue
    case "$(basename "$run_dir")" in .ccb-transaction.*) continue;; esac
    found=1; run_name=$(basename "$run_dir")
    if [ ! -d "$run_dir" ] || [ -L "$run_dir" ] || ! run_parse_conf "$run_dir/run.conf"; then emit WARN "project.run.$run_name" invalid-or-unsafe; continue; fi
    run_status=$RUN_STATUS; run_current=$RUN_CURRENT; run_count=$RUN_COUNT; run_completed=$RUN_COMPLETED
    state_ok=1
    project_run_execution_history_summary "$run_dir" || state_ok=0
    automation_file="$run_dir/orchestration.conf"; automation_lock="$run_dir/.ccb-orchestration-lock"
    automation_status=none
    orchestration_residual=$(find "$run_dir" -maxdepth 2 \( -name '.orchestration.conf.tmp.*' -o -name '.ccb-orchestration-*' \) ! -name '.ccb-orchestration-lock' -print -quit)
    [ -z "$orchestration_residual" ] || state_ok=0
    if [ -e "$automation_file" ] || [ -L "$automation_file" ]; then
      if project_orchestration_parse_conf "$automation_file"; then
        automation_status=$ORCHESTRATION_STATUS
        automation_done=$(project_orchestration_count_completed "$run_dir" "$run_count" 2>/dev/null) || state_ok=0
        [ "$ORCHESTRATION_STEP_COUNT" = "$run_count" ] && [ "$ORCHESTRATION_CURRENT" = "$run_current" ] && [ "$ORCHESTRATION_STEPS_COMPLETED" = "${automation_done:-0}" ] || state_ok=0
        [ "$ORCHESTRATION_ACTIONS" -le $((run_count * 3 + 3)) ] || state_ok=0
        if [ "$automation_status" = succeeded ]; then [ "$run_status" = completed ] || state_ok=0; fi
        if [ "$run_status" = cancelled ]; then
          [ "$automation_status" = interrupted ] && [ "$ORCHESTRATION_ERROR" = cancelled-by-user ] && [ -n "$ORCHESTRATION_COMPLETED" ] || state_ok=0
        fi
      else state_ok=0
      fi
    fi
    if [ -e "$automation_lock" ] || [ -L "$automation_lock" ]; then
      [ -d "$automation_lock" ] && [ ! -L "$automation_lock" ] && [ "$automation_status" = running ] || state_ok=0
    elif [ "$automation_status" = running ]; then state_ok=0
    fi
    case "$run_status" in completed|cancelled) [ -n "$run_completed" ] || state_ok=0;; *) [ -z "$run_completed" ] || state_ok=0;; esac
    previous_dir=; previous_status=
    i=1
    while [ "$i" -le "$run_count" ]; do
      step_matches=$(find "$run_dir" -maxdepth 1 -type d -name "$(printf '%02d' "$i")-*" -print)
      if [ "$(printf '%s\n' "$step_matches" | sed '/^$/d' | wc -l | tr -d ' ')" != 1 ]; then state_ok=0; i=$((i + 1)); continue; fi
      doctor_step_dir=$step_matches
      if ! run_step_parse "$doctor_step_dir/step.conf"; then state_ok=0; i=$((i + 1)); continue; fi
      step_status=$STEP_STATUS
      case "$step_status" in
        in-progress) [ -n "$STEP_STARTED" ] && [ -z "$STEP_COMPLETED" ] || state_ok=0;;
        completed) [ -n "$STEP_STARTED" ] && [ -n "$STEP_COMPLETED" ] || state_ok=0;;
        ready|pending) [ -z "$STEP_STARTED" ] && [ -z "$STEP_COMPLETED" ] || state_ok=0;;
        blocked) [ -n "$STEP_STARTED" ] && [ -z "$STEP_COMPLETED" ] || state_ok=0;;
        skipped)
          if [ "$run_status" = cancelled ] && [ "$i" -eq "$run_current" ]; then
            [ -z "$STEP_STARTED" ] && [ -z "$STEP_COMPLETED" ] || state_ok=0
          else
            [ -n "$STEP_COMPLETED" ] || state_ok=0
          fi;;
      esac
      result_file="$doctor_step_dir/result.md"
      if [ "$step_status" = completed ]; then project_run_validate_completed_result "$result_file" || state_ok=0
      else
        [ -f "$result_file" ] && [ ! -L "$result_file" ] && [ "$(grep -c '^Status: pending$' "$result_file" 2>/dev/null)" = 1 ] && [ "$(grep -c '^Status: ' "$result_file" 2>/dev/null)" = 1 ] || state_ok=0
      fi
      execution_file="$doctor_step_dir/execution.conf"
      if [ -e "$execution_file" ] || [ -L "$execution_file" ]; then
        if project_execution_parse_conf "$execution_file" && [ "$EXECUTION_PROVIDER" = "$STEP_PROVIDER" ] && [ "$EXECUTION_MODEL" = "$STEP_MODEL" ]; then
          if [ "$EXECUTION_STATUS" = succeeded ]; then project_execution_result_is_template "$result_file" && state_ok=0
          elif [ "$EXECUTION_STATUS" = running ]; then
            if [ "$execution_lock" = "$run_dir/.ccb-execution-lock" ] && [ -d "$execution_lock" ] && [ ! -L "$execution_lock" ]; then running_execution=1; else state_ok=0; fi
          fi
        else state_ok=0
        fi
      fi
      if [ "$i" -gt 1 ] && [ "$previous_status" = completed ] && [ "$step_status" != pending ]; then
        transmission_scratch=$(mktemp "${TMPDIR:-/tmp}/ccb-doctor-transmission.XXXXXX") || { state_ok=0; transmission_scratch=; }
        if [ -n "$transmission_scratch" ]; then
          project_run_validate_transmission "$doctor_step_dir/input.md" "$(basename "$previous_dir")" "$previous_dir/result.md" "$transmission_scratch" || state_ok=0
          rm -f "$transmission_scratch"
        fi
      fi
      previous_dir=$doctor_step_dir; previous_status=$step_status
      i=$((i + 1))
    done
    current_dir=$(find "$run_dir" -maxdepth 1 -type d -name "$(printf '%02d' "$run_current")-*" -print)
    if [ -n "$current_dir" ] && run_step_parse "$current_dir/step.conf"; then
      case "$run_status:$STEP_STATUS" in pending:pending|pending:ready|in-progress:in-progress|in-progress:ready|blocked:blocked|completed:completed|completed:skipped|cancelled:skipped|cancelled:blocked) :;; *) state_ok=0;; esac
    else state_ok=0
    fi
    [ "$state_ok" -eq 1 ] && emit OK "project.run.$run_name" valid || emit WARN "project.run.$run_name" inconsistent
  done
  if [ -z "$execution_lock" ]; then emit OK project.runs.execution_locks clean
  elif [ "$running_execution" -eq 1 ] && [ -d "$execution_lock" ] && [ ! -L "$execution_lock" ]; then emit OK project.runs.execution_locks active
  else emit WARN project.runs.execution_locks residual
  fi
  [ "$found" -eq 1 ] || emit OK project.runs empty
}

if [ -n "$target" ]; then
  legacy_project=0
  if [ ! -e "$target/.ccb/project.conf" ] && [ -f "$target/.ccb/AGENT_POLICY.md" ]; then legacy_project=1; fi
  if [ "$legacy_project" -eq 1 ]; then
    emit SKIP project.bootstrap legacy-installation
  elif [ -L "$target/.ccb" ] || [ ! -d "$target/.ccb" ]; then emit FAIL project.ccb missing-or-unsafe; else emit OK project.ccb directory; fi
  if [ "$legacy_project" -eq 0 ]; then
    if [ -L "$target/.ccb/context" ] || [ ! -d "$target/.ccb/context" ]; then emit FAIL project.context_dir missing-or-unsafe; else emit OK project.context_dir directory; fi
    check_managed_file "$target/.ccb/project.conf" project.project_conf
    check_managed_file "$target/.ccb/models.conf" project.models_conf
    check_managed_file "$target/.ccb/skills.conf" project.skills_conf
    check_managed_file "$target/.ccb/agents.conf" project.agents_conf
    check_managed_file "$target/.ccb/workflows.conf" project.workflows_conf
    check_managed_file "$target/.ccb/context/project.md" project.context
    check_managed_file "$target/AGENTS.md" project.agents
    if project_conf_parse "$target/.ccb/project.conf"; then
    profile=$PROJECT_PROFILE
    project_version=$(awk -F= '$1=="CCB_PROJECT_VERSION" {print $2}' "$target/.ccb/project.conf")
    template_version=$(awk -F= '$1=="CCB_TEMPLATE_VERSION" {print $2}' "$target/.ccb/project.conf")
    if project_profile_parse "$TEMPLATE_ROOT/project-profiles/$profile.conf" && [ "$PROJECT_PROFILE_ID" = "$profile" ]; then emit OK project.profile "$profile"; else emit FAIL project.profile unsupported; fi
    [ "$project_version" = 1 ] && emit OK project.version 1 || emit FAIL project.version unsupported
    if [ "$template_version" = "$(cat "$TEMPLATE_ROOT/VERSION")" ]; then emit OK project.template_version "$template_version"; elif [ "$template_version" = 1.7.0 ] || [ "$template_version" = 1.7.1 ]; then emit OK project.template_version legacy-compatible; elif [ "$template_version" = 1.6.0 ] || [ "$template_version" = 1.6.1 ]; then emit WARN project.template_version upgrade-available; else emit FAIL project.template_version incompatible; fi
    grep -Fq "Project: $PROJECT_NAME" "$target/.ccb/context/project.md" 2>/dev/null && emit OK project.context_name present || emit WARN project.context_name missing
    grep -Fq "Profile: $profile" "$target/.ccb/context/project.md" 2>/dev/null && emit OK project.context_profile present || emit WARN project.context_profile missing
    else emit FAIL project.project_conf invalid; fi
    if project_models_parse "$target/.ccb/models.conf"; then
    emit OK project.provider "$PROJECT_MODEL_PROVIDER"
    emit OK project.models_format "$PROJECT_MODEL_FORMAT"
    for role in manager graph graphiste developer reviewer fallback; do
      case "$role" in manager) model_value=$PROJECT_MODEL_MANAGER;; graph) model_value=$PROJECT_MODEL_GRAPH;; graphiste) model_value=$PROJECT_MODEL_GRAPHISTE;; developer) model_value=$PROJECT_MODEL_DEVELOPER;; reviewer) model_value=$PROJECT_MODEL_REVIEWER;; fallback) model_value=$PROJECT_MODEL_FALLBACK;; esac
      emit OK "project.model.$role" "$model_value"
    done
    else emit FAIL project.models_conf invalid; fi
    if project_skills_parse "$target/.ccb/skills.conf"; then
      emit OK project.ponytail_mode "$PROJECT_SKILL_PONYTAIL_MODE"
      grep -Fq '.ccb/skills.conf' "$target/AGENTS.md" 2>/dev/null && grep -Fq '## Ponytail' "$target/AGENTS.md" 2>/dev/null && grep -Fq "Mode: $PROJECT_SKILL_PONYTAIL_MODE" "$target/AGENTS.md" 2>/dev/null && emit OK project.ponytail_guidance present || emit FAIL project.ponytail_guidance missing
      grep -Fq '## Skills' "$target/.ccb/context/project.md" 2>/dev/null && emit OK project.skills_context present || emit WARN project.skills_context missing
    else
      if [ "$template_version" = 1.6.0 ]; then emit WARN project.upgrade 'run: ccb.sh upgrade TARGET --yes'; else emit FAIL project.skills_conf invalid; fi
    fi
    if project_agents_parse "$target/.ccb/agents.conf"; then
      emit OK project.agents_conf valid
      emit OK project.agent_models valid
      emit OK project.agent_access declarative-only
      grep -Fq '## Agent roles' "$target/.ccb/context/project.md" 2>/dev/null && emit OK project.agent_context present || emit WARN project.agent_context missing
    elif [ "$template_version" = 1.6.0 ] || [ "$template_version" = 1.6.1 ]; then
      emit WARN project.agents_conf legacy-not-configured
    else emit FAIL project.agents_conf invalid; fi
    if project_workflows_parse "$target/.ccb/workflows.conf"; then emit OK project.workflows_conf valid; emit OK project.workflow_execution available; doctor_check_workflow_runs; elif [ "$template_version" = 1.7.0 ] || [ "$template_version" = 1.7.1 ]; then emit WARN project.workflows_conf not-configured; else emit WARN project.workflows_conf legacy-not-configured; fi
    grep -Fq '.ccb/context/project.md' "$target/AGENTS.md" 2>/dev/null && grep -Fq '.ccb/models.conf' "$target/AGENTS.md" 2>/dev/null && emit OK project.agents_guidance present || emit WARN project.agents_guidance incomplete
  fi
  if command -v git >/dev/null 2>&1; then
    if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      [ -z "$(git -C "$target" status --porcelain 2>/dev/null)" ] && emit OK git.project working-tree-clean || emit WARN git.project working-tree-dirty
    else emit SKIP git.project not-a-repository; fi
  fi
fi

if [ "$no_ollama" -eq 1 ]; then
  emit SKIP ollama disabled
elif ! command -v ollama >/dev/null 2>&1; then
  emit WARN ollama.command not-found
elif ! ollama --version >/dev/null 2>&1; then
  emit WARN ollama.command version-failed
else
  emit OK ollama.command available
  if [ -n "$target" ] && [ "${legacy_project:-0}" -eq 0 ] && project_models_parse "$target/.ccb/models.conf"; then
    local_models=$(ollama list 2>/dev/null | awk 'NR>1 {print $1}')
    if [ -z "$local_models" ]; then emit WARN ollama.models unavailable-or-empty
    else
      for configured in "$PROJECT_MODEL_MANAGER" "$PROJECT_MODEL_GRAPH" "$PROJECT_MODEL_GRAPHISTE" "$PROJECT_MODEL_DEVELOPER" "$PROJECT_MODEL_REVIEWER" "$PROJECT_MODEL_FALLBACK"; do printf '%s\n' "$local_models" | grep -Fqx "$configured" && emit OK "ollama.model.$configured" installed || emit WARN "ollama.model.$configured" not-installed; done
    fi
  else emit SKIP ollama.models no-project; fi
fi

printf 'Summary: OK=%s WARN=%s FAIL=%s SKIP=%s\n' "$ok_count" "$warn_count" "$fail_count" "$skip_count"
[ "$fail_count" -eq 0 ] || exit 1
[ "$strict" -eq 0 ] || [ "$warn_count" -eq 0 ] || exit 1
exit 0
