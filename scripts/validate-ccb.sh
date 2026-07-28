#!/usr/bin/env sh
set -eu

TARGET=${1:-.}
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/profile-lib.sh"
. "$SCRIPT_DIR/model-lib.sh"
. "$SCRIPT_DIR/project-profile-lib.sh"
. "$SCRIPT_DIR/project-skills-lib.sh"
. "$SCRIPT_DIR/project-agents-lib.sh"
PROFILE_ROOT="$TEMPLATE_ROOT/profiles"
ERRORS=0

ok() { echo "[OK] $1"; }
warn() { echo "[WARN] $1"; }
error() { echo "[ERROR] $1" >&2; ERRORS=1; }

if [ ! -d "$TARGET" ]; then
  error "target directory does not exist: $TARGET"
  exit 1
fi
TARGET=$(CDPATH= cd "$TARGET" && pwd)

if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ok "Git repository: $TARGET"
else
  error "target is not a Git repository: $TARGET"
fi

if git -C "$TARGET" rev-parse --verify HEAD >/dev/null 2>&1; then
  ok "initial Git commit exists"
else
  error "initial Git commit is required for developer worktrees"
fi

require_dir() {
  if [ -d "$TARGET/$1" ]; then ok "directory: $1"; else error "missing directory: $1"; fi
}

require_file() {
  if [ -f "$TARGET/$1" ]; then ok "file: $1"; else error "missing file: $1"; fi
}

require_nonempty_file() {
  require_file "$1"
  if [ -s "$TARGET/$1" ]; then ok "non-empty: $1"; else error "empty file: $1"; fi
}

require_template_nonempty_file() {
  if [ -s "$TEMPLATE_ROOT/$1" ]; then
    ok "shared skill: $1"
  else
    error "missing or empty shared skill: $1"
  fi
}

require_template_executable() {
  if [ -x "$TEMPLATE_ROOT/$1" ]; then
    ok "template script: $1"
  else
    error "missing or non-executable template script: $1"
  fi
}

require_ignore() {
  if grep -Fqx "$1" "$TARGET/.gitignore" 2>/dev/null; then
    ok "gitignore: $1"
  else
    error "missing .gitignore entry: $1"
  fi
}

require_dir .ccb
require_file .ccb/AGENT_POLICY.md
require_nonempty_file .ccb/ccb_memory.md
require_nonempty_file .ccb/agents/manager/memory.md
require_nonempty_file .ccb/agents/graph/memory.md
require_nonempty_file .ccb/agents/graphiste/memory.md
require_nonempty_file .ccb/agents/reviewer/memory.md
require_dir graphify-out
require_dir graphiste-out
require_file .gitignore

for skill in \
  skills/shared/ccb-handoff/SKILL.md \
  skills/shared/project-memory/SKILL.md \
  skills/shared/safe-git-boundaries/SKILL.md \
  skills/shared/text-only-policy/SKILL.md; do
  require_template_nonempty_file "$skill"
done

require_template_executable scripts/doctor.sh
require_template_executable scripts/ccb.sh
require_template_executable ccb
require_template_executable scripts/quickstart.sh
require_template_executable scripts/project-init.sh
require_template_executable scripts/project-config.sh
require_template_executable scripts/project-skills.sh
require_template_executable scripts/project-agents.sh
require_template_executable scripts/project-workflows.sh
require_template_executable scripts/project-runs.sh
require_template_executable scripts/project-execution-lib.sh
require_template_executable scripts/project-orchestration-lib.sh
if [ -s "$TEMPLATE_ROOT/scripts/project-runs-lib.sh" ] && sh -n "$TEMPLATE_ROOT/scripts/project-runs-lib.sh"; then ok 'template library: scripts/project-runs-lib.sh'; else error 'invalid runs library'; fi
if [ -s "$TEMPLATE_ROOT/scripts/project-workflows-lib.sh" ] && sh -n "$TEMPLATE_ROOT/scripts/project-workflows-lib.sh"; then ok 'template library: scripts/project-workflows-lib.sh'; else error 'invalid workflows library'; fi
if [ -s "$TEMPLATE_ROOT/scripts/project-agents-lib.sh" ] && sh -n "$TEMPLATE_ROOT/scripts/project-agents-lib.sh"; then ok 'template library: scripts/project-agents-lib.sh'; else error 'invalid agents library'; fi
require_template_executable scripts/project-upgrade.sh
require_template_executable scripts/doctor.sh

for project_test in tests/test-project-init.sh tests/test-project-profiles.sh tests/test-project-models.sh tests/test-project-config.sh tests/test-project-skills.sh tests/test-skills-command.sh tests/test-project-agents.sh tests/test-project-workflows.sh tests/test-project-runs.sh tests/test-project-execution.sh tests/test-project-orchestration.sh tests/test-project-retry.sh tests/test-project-cancel.sh tests/test-project-history.sh tests/test-project-upgrade.sh tests/test-doctor.sh tests/test-v1.7.1-regressions.sh tests/test-v1.8.0-quickstart.sh; do
  require_template_executable "$project_test"
done

for model_script in scripts/model-lib.sh scripts/model-setup.sh; do
  if [ -s "$TEMPLATE_ROOT/$model_script" ] && [ -r "$TEMPLATE_ROOT/$model_script" ]; then ok "template model script: $model_script"; else error "missing model script: $model_script"; fi
done

if [ -s "$TEMPLATE_ROOT/scripts/mascot-lib.sh" ] && [ -r "$TEMPLATE_ROOT/scripts/mascot-lib.sh" ]; then
  ok "template library: scripts/mascot-lib.sh"
else
  error "missing or unreadable template library: scripts/mascot-lib.sh"
fi

for template_file in VERSION profiles/README.md profiles/generic/profile.conf tests/test-profiles.sh tests/test-cli.sh tests/test-project-init.sh tests/test-project-profiles.sh tests/test-project-models.sh tests/test-project-config.sh tests/test-project-skills.sh tests/test-skills-command.sh tests/test-project-agents.sh tests/test-project-orchestration.sh tests/test-project-retry.sh tests/test-project-cancel.sh tests/test-project-history.sh tests/test-project-upgrade.sh tests/test-doctor.sh tests/test-setup-wizard.sh tests/test-models.sh tests/test-v1.7.1-regressions.sh tests/test-v1.8.0-quickstart.sh docs/models.md docs/project-bootstrap.md docs/project-skills.md docs/project-agents.md docs/project-runs.md docs/project-workflows.md docs/project-execution.md docs/project-orchestration.md docs/project-reliability.md docs/project-upgrade.md docs/ponytail.md docs/doctor.md docs/quickstart.md docs/cloud-setup.md docs/troubleshooting.md docs/v1.6.0.md docs/v1.6.1.md docs/v1.7.0.md CHANGELOG.md; do
  if [ -s "$TEMPLATE_ROOT/$template_file" ]; then
    ok "template file: $template_file"
  else
    error "missing or empty template file: $template_file"
  fi
done

if [ "$(cat "$TEMPLATE_ROOT/VERSION")" = 1.8.0 ]; then ok 'template version: 1.8.0'; else error 'template VERSION must be 1.8.0'; fi

for project_profile in generic web node python audio; do
  if project_profile_parse "$TEMPLATE_ROOT/project-profiles/$project_profile.conf" && [ "$PROJECT_PROFILE_ID" = "$project_profile" ]; then
    ok "project bootstrap profile: $project_profile"
  else
    error "invalid project bootstrap profile: $project_profile"
  fi
done

for audited_script in scripts/doctor.sh scripts/model-lib.sh scripts/model-resolve.sh scripts/project-init.sh scripts/project-upgrade.sh scripts/project-config.sh scripts/project-config-lib.sh scripts/project-profile-lib.sh scripts/project-runs.sh scripts/project-runs-lib.sh scripts/project-execution-lib.sh scripts/project-orchestration-lib.sh scripts/provider-router.sh; do
  if awk '
    /^[[:space:]]*#/ { next }
    /(^|[[:space:];])eval([[:space:];]|$)|(^|[[:space:];])source[[:space:]]|(^|[[:space:];])(bash|sh)[[:space:]]+-c|curl[[:space:]]|wget[[:space:]]|sudo[[:space:]]|chmod[[:space:]]+777|mktemp[[:space:]]+-u|rm[[:space:]]+-rf/ { bad=1 }
    END { exit bad ? 1 : 0 }
  ' "$TEMPLATE_ROOT/$audited_script"; then
    ok "safe production script: $audited_script"
  else
    error "unsafe production construction: $audited_script"
  fi
done
if awk '
  /^[[:space:]]*#/ { next }
  /(^|[[:space:];])eval([[:space:];]|$)|(^|[[:space:];])source[[:space:]]|(^|[[:space:];])(bash|sh)[[:space:]]+-c|wget[[:space:]]|sudo[[:space:]]|chmod[[:space:]]+777|mktemp[[:space:]]+-u|rm[[:space:]]+-rf/ { bad=1 }
  END { exit bad ? 1 : 0 }
' "$TEMPLATE_ROOT/scripts/runtime/provider-ollama.sh" &&
  grep -Fq 'http://127.0.0.1:11434' "$TEMPLATE_ROOT/scripts/runtime/provider-ollama.sh" &&
  grep -Fq 'http://localhost:11434' "$TEMPLATE_ROOT/scripts/runtime/provider-ollama.sh" &&
  grep -Fq -- '--max-redirs 0' "$TEMPLATE_ROOT/scripts/runtime/provider-ollama.sh"; then
  ok 'safe local Ollama execution provider'
else
  error 'unsafe local Ollama execution provider'
fi

validate_profiles() {
  if [ ! -d "$PROFILE_ROOT" ]; then error "missing profiles directory"; return; fi
  if [ ! -d "$PROFILE_ROOT/generic" ]; then error "missing generic profile"; fi
  seen_ids=' '
  for profile_dir in "$PROFILE_ROOT"/*; do
    [ -d "$profile_dir" ] || continue
    if [ -L "$profile_dir" ]; then error "profile directory must not be a symlink: $(basename "$profile_dir")"; continue; fi
    if ! profile_parse "$profile_dir/profile.conf"; then error "invalid profile $(basename "$profile_dir"): $PROFILE_PARSE_ERROR"; continue; fi
    if [ "$PROFILE_ID" != "$(basename "$profile_dir")" ]; then error "profile id does not match directory: $PROFILE_ID"; fi
    case "$seen_ids" in *" $PROFILE_ID "*) error "duplicate profile id: $PROFILE_ID";; *) seen_ids="$seen_ids$PROFILE_ID ";; esac
    if [ ! -s "$profile_dir/PROFILE.md" ] || [ ! -s "$profile_dir/$PROFILE_MEMORY_SEED" ]; then error "incomplete profile: $PROFILE_ID"; fi
    case "$PROFILE_SKILLS" in ,*|*,|*,,*) error "invalid PROFILE_SKILLS: $PROFILE_ID";; esac
    old_ifs=$IFS; IFS=,
    for profile_skill in $PROFILE_SKILLS; do
      [ -n "$profile_skill" ] || continue
      if ! profile_id_is_safe "$profile_skill" || [ ! -s "$profile_dir/skills/$profile_skill/SKILL.md" ]; then error "missing or unsafe profile skill: $PROFILE_ID/$profile_skill"; fi
    done
    IFS=$old_ifs
    ok "profile: $PROFILE_ID"
  done
}

validate_profiles

validate_workflow_progression() {
  scenario_root=$(mktemp -d "${TMPDIR:-/tmp}/ccb-validator-runs.XXXXXX") || { error 'cannot create workflow validation directory'; return; }
  scenario_project="$scenario_root/project"; scenario_witness="$scenario_root/witness"
  if ! "$TEMPLATE_ROOT/scripts/ccb.sh" init "$scenario_project" --yes >/dev/null; then error 'workflow scenario init failed'; return; fi
  managed_count=$(find "$scenario_project/.ccb" -type f | wc -l | tr -d ' ')
  managed_count=$((managed_count + 1))
  [ "$managed_count" -eq 7 ] && ok 'project init: seven managed files' || error 'project init must create seven managed files'
  if ! "$TEMPLATE_ROOT/scripts/ccb.sh" workflow start feature "$scenario_project" >/dev/null; then error 'workflow scenario start failed'; return; fi
  scenario_id=$(run_output=$("$TEMPLATE_ROOT/scripts/ccb.sh" workflow status --latest "$scenario_project") && printf '%s\n' "$run_output" | sed -n 's/^Run ID: //p')
  scenario_run="$scenario_project/.ccb/runs/$scenario_id"
  if ! "$TEMPLATE_ROOT/scripts/ccb.sh" workflow resume --latest "$scenario_project" >/dev/null; then error 'workflow scenario resume failed'; return; fi
  scenario_response="$scenario_root/provider-response"
  printf 'Literal $(touch "%s")\n' "$scenario_witness" >"$scenario_response"
  if env CCB_TEST_MODE=1 CCB_OLLAMA_ENDPOINT=http://example.invalid:11434 CCB_TEST_PROVIDER_RESPONSE_FILE="$scenario_response" "$TEMPLATE_ROOT/scripts/ccb.sh" workflow execute-step --latest "$scenario_project" >/dev/null 2>&1; then error 'workflow execute-step accepted remote provider endpoint'; else ok 'workflow execute-step: remote endpoint refused'; fi
  if ! "$TEMPLATE_ROOT/scripts/ccb.sh" workflow retry-step --latest "$scenario_project" >/dev/null; then error 'workflow retry-step preparation failed'; return; fi
  if [ -f "$scenario_run/01-manager/attempts/001.conf" ] &&
    grep -Fqx 'CCB_EXECUTION_ATTEMPT=2' "$scenario_run/01-manager/execution.conf"; then ok 'workflow retry-step: archived attempt and prepared attempt 2'; else error 'workflow retry metadata invalid'; fi
  if env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$scenario_response" "$TEMPLATE_ROOT/scripts/ccb.sh" workflow execute-step --latest "$scenario_project" >/dev/null &&
    grep -Fq 'Literal $(touch "' "$scenario_run/01-manager/result.md" && [ ! -e "$scenario_witness" ]; then ok 'workflow execute-step: local test provider'; else error 'workflow execute-step failed'; fi
  scenario_status=$("$TEMPLATE_ROOT/scripts/ccb.sh" workflow status --latest "$scenario_project")
  printf '%s\n' "$scenario_status" | grep -Fq 'Execution status: succeeded' && ok 'workflow status: execution metadata' || error 'workflow status omitted execution metadata'
  scenario_inspect=$("$TEMPLATE_ROOT/scripts/ccb.sh" workflow inspect --latest "$scenario_project")
  if printf '%s\n' "$scenario_inspect" | grep -Fq 'Status: succeeded' && ! printf '%s\n' "$scenario_inspect" | grep -Fq 'Literal $(touch'; then ok 'workflow inspect: safe execution metadata'; else error 'workflow inspect exposed or omitted execution data'; fi
  "$TEMPLATE_ROOT/scripts/ccb.sh" config "$scenario_project" | grep -Fq 'Runs with succeeded execution: 1' && ok 'workflow config: execution count' || error 'workflow config execution count failed'
  scenario_history_before=$(find "$scenario_run" -type f -exec cksum {} \; | LC_ALL=C sort)
  scenario_history=$("$TEMPLATE_ROOT/scripts/ccb.sh" workflow history "$scenario_id" "$scenario_project")
  scenario_history_after=$(find "$scenario_run" -type f -exec cksum {} \; | LC_ALL=C sort)
  if printf '%s\n' "$scenario_history" | grep -Fq 'Event: retry-prepared' &&
    ! printf '%s\n' "$scenario_history" | grep -Fq 'Literal $(touch' &&
    [ "$scenario_history_before" = "$scenario_history_after" ]; then ok 'workflow history: explicit, safe, and read-only'; else error 'workflow history validation failed'; fi
  scenario_before=$(cksum "$scenario_run/run.conf" "$scenario_run/01-manager/step.conf" "$scenario_run/01-manager/result.md" "$scenario_run/02-developer/input.md" "$scenario_run/02-developer/step.conf")
  if env CCB_TEST_FAIL_POINT=after-result "$TEMPLATE_ROOT/scripts/ccb.sh" workflow complete-step --latest "$scenario_project" >/dev/null 2>&1; then error 'workflow rollback fail point was ignored'
  else
    scenario_after=$(cksum "$scenario_run/run.conf" "$scenario_run/01-manager/step.conf" "$scenario_run/01-manager/result.md" "$scenario_run/02-developer/input.md" "$scenario_run/02-developer/step.conf")
    [ "$scenario_before" = "$scenario_after" ] && ok 'workflow rollback: byte-identical' || error 'workflow rollback changed files'
  fi
  if "$TEMPLATE_ROOT/scripts/ccb.sh" workflow complete-step --latest "$scenario_project" >/dev/null &&
    grep -Fq 'Literal $(touch "' "$scenario_run/02-developer/input.md" &&
    [ ! -e "$scenario_witness" ]; then ok 'workflow context transfer: literal and non-executing'; else error 'workflow literal transfer failed'; fi
  "$TEMPLATE_ROOT/scripts/ccb.sh" workflow status --latest "$scenario_project" >/dev/null && ok 'workflow status: valid' || error 'workflow status failed'
  "$TEMPLATE_ROOT/scripts/ccb.sh" workflow inspect --latest "$scenario_project" >/dev/null && ok 'workflow inspect: valid' || error 'workflow inspect failed'
  "$TEMPLATE_ROOT/scripts/ccb.sh" config "$scenario_project" | grep -Fq 'In-progress runs: 1' && ok 'workflow config: valid' || error 'workflow config failed'
  if env CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$scenario_response" "$TEMPLATE_ROOT/scripts/ccb.sh" workflow run --latest "$scenario_project" >/dev/null &&
    grep -Fqx 'CCB_RUN_STATUS=completed' "$scenario_run/run.conf" &&
    grep -Fqx 'CCB_ORCHESTRATION_STATUS=succeeded' "$scenario_run/orchestration.conf" &&
    [ ! -e "$scenario_run/.ccb-orchestration-lock" ] && [ ! -e "$scenario_witness" ]; then
    ok 'workflow automation: sequential, checkpointed, and non-executing'
  else error 'workflow automation failed'; fi
  "$TEMPLATE_ROOT/scripts/ccb.sh" config "$scenario_project" | grep -Fq 'Runs automated successfully: 1' && ok 'workflow config: automation count' || error 'workflow automation config count failed'
  if ! "$TEMPLATE_ROOT/scripts/ccb.sh" workflow start feature "$scenario_project" >/dev/null; then error 'workflow cancellation scenario start failed'; return; fi
  cancel_id=$(cancel_status=$("$TEMPLATE_ROOT/scripts/ccb.sh" workflow status --latest "$scenario_project") && printf '%s\n' "$cancel_status" | sed -n 's/^Run ID: //p')
  cancel_run="$scenario_project/.ccb/runs/$cancel_id"
  cancel_before=$(cksum "$cancel_run/run.conf" "$cancel_run/01-manager/step.conf")
  if env CCB_TEST_MODE=1 CCB_TEST_CANCEL_FAIL_POINT=after-current-step "$TEMPLATE_ROOT/scripts/ccb.sh" workflow cancel "$cancel_id" "$scenario_project" >/dev/null 2>&1; then error 'workflow cancel rollback fail point ignored'
  else
    cancel_after=$(cksum "$cancel_run/run.conf" "$cancel_run/01-manager/step.conf")
    [ "$cancel_before" = "$cancel_after" ] && ok 'workflow cancel rollback: byte-identical' || error 'workflow cancel rollback changed files'
  fi
  if "$TEMPLATE_ROOT/scripts/ccb.sh" workflow cancel --latest "$scenario_project" >/dev/null &&
    grep -Fqx 'CCB_RUN_STATUS=cancelled' "$cancel_run/run.conf" &&
    grep -Fqx 'CCB_STEP_STATUS=skipped' "$cancel_run/01-manager/step.conf"; then ok 'workflow cancel: terminal transition'; else error 'workflow cancel failed'; fi
  if "$TEMPLATE_ROOT/scripts/ccb.sh" workflow resume "$cancel_id" "$scenario_project" >/dev/null 2>&1; then error 'cancelled workflow resumed'; else ok 'workflow cancel: mutation refused'; fi
  "$TEMPLATE_ROOT/scripts/ccb.sh" workflow history --latest "$scenario_project" >/dev/null && ok 'workflow history: latest' || error 'workflow history latest failed'
  "$TEMPLATE_ROOT/scripts/ccb.sh" workflow status "$cancel_id" "$scenario_project" >/dev/null && "$TEMPLATE_ROOT/scripts/ccb.sh" workflow inspect "$cancel_id" "$scenario_project" >/dev/null && ok 'cancelled workflow status and inspect' || error 'cancelled workflow observability failed'
  scenario_config=$("$TEMPLATE_ROOT/scripts/ccb.sh" config "$scenario_project")
  if printf '%s\n' "$scenario_config" | grep -Fq 'Runs with archived retries: 1' && printf '%s\n' "$scenario_config" | grep -Fq 'Cancelled runs: 1'; then ok 'workflow config: D3 counters'; else error 'workflow config D3 counters failed'; fi
  "$TEMPLATE_ROOT/scripts/ccb.sh" doctor "$scenario_project" --no-ollama --strict >/dev/null && ok 'workflow doctor strict: valid' || error 'workflow doctor strict failed'
  residue=$(find "$scenario_project/.ccb/runs" \( -name '.ccb-transaction.*' -o -name '.ccb-retry-transaction.*' -o -name '*.old' -o -name '*.new' -o -name '.ccb-backup*' -o -name '.ccb-execution-lock' -o -name '.ccb-orchestration-lock' \) -print -quit)
  [ -z "$residue" ] && ok 'workflow transaction residue: none' || error 'workflow transaction residue found'
  find "$scenario_root" -depth -type f -exec rm -f {} \;
  find "$scenario_root" -depth -type l -exec rm -f {} \;
  find "$scenario_root" -depth -type d -exec rmdir {} \;
}

validate_workflow_progression

for d3_suite in tests/test-project-retry.sh tests/test-project-cancel.sh tests/test-project-history.sh tests/test-project-config.sh tests/test-doctor.sh; do
  if "$TEMPLATE_ROOT/$d3_suite" >/dev/null; then ok "D3 functional suite: $d3_suite"; else error "D3 functional suite failed: $d3_suite"; fi
done

for role in manager graph graphiste developer reviewer; do
  if grep -qi "$role" "$TARGET/.ccb/AGENT_POLICY.md"; then
    ok "policy role: $role"
  else
    error "policy missing role: $role"
  fi
done

if grep -Eqi 'TEXT ONLY|text-only' "$TARGET/.ccb/AGENT_POLICY.md"; then
  ok "policy: TEXT ONLY"
else
  error "policy missing TEXT ONLY"
fi

for entry in \
  '.ccb/backups/' \
  '.ccb/ccbd/' \
  '.ccb/workspaces/' \
  '.ccb/agents/*/sessions/' \
  '.ccb/agents/*/provider-state/' \
  'graphify-out/' \
  'graphiste-out/'; do
  require_ignore "$entry"
done

if [ -f "$TARGET/.ccb/active-profile" ]; then
  active_profile=$(cat "$TARGET/.ccb/active-profile")
  if ! profile_id_is_safe "$active_profile" || ! profile_parse "$PROFILE_ROOT/$active_profile/profile.conf"; then
    error "invalid active profile: $active_profile"
  else
    require_file ".ccb/profiles/$active_profile/PROFILE.md"
    old_ifs=$IFS; IFS=,
    for profile_skill in $PROFILE_SKILLS; do
      [ -n "$profile_skill" ] && require_file ".ccb/profiles/$active_profile/skills/$profile_skill/SKILL.md"
    done
    IFS=$old_ifs
    ok "active profile: $active_profile"
  fi
else
  warn "no active profile (compatible legacy CCB project); run install-project.sh --profile generic to add one"
fi

if [ "$ERRORS" -ne 0 ]; then
  error "CCB template validation failed"
  exit 1
fi

warn "validation does not inspect provider credentials or runtime state"
ok "CCB template validation passed"
