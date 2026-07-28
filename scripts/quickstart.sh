#!/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
PROJECT_INIT="$SCRIPT_DIR/project-init.sh"
MODEL_SETUP="$SCRIPT_DIR/model-setup.sh"
DOCTOR="$SCRIPT_DIR/doctor.sh"
PROJECT_CONFIG="$SCRIPT_DIR/project-config.sh"
PROJECT_RUNS="$SCRIPT_DIR/project-runs.sh"
. "$SCRIPT_DIR/model-lib.sh"
. "$SCRIPT_DIR/project-profile-lib.sh"
. "$SCRIPT_DIR/project-workflows-lib.sh"

target= project_name= profile=generic preset= run_workflow= cloud=0 no_run=0 yes=0 dry_run=0 force_new=0 verbose=0
output_file= target_was_created=0 ccb_was_created=0 context_was_created=0 runs_was_created=0 run_id=
models_before=0 models_backup_list= project_before=0 models_before_path= skills_before=0 agents_conf_before=0 workflows_before=0 context_before=0 agents_before=0

usage() {
  cat <<'EOF'
usage: ccb.sh quickstart TARGET [OPTIONS]

Options:
  --name NAME, --project-name NAME  Set the project name
  --profile PROFILE                 generic, web, node, python, or audio
  --cloud                           Use local-proxy Ollama Cloud models
  --preset PRESET                   Select a model preset
  --run WORKFLOW                    Start and execute feature, bugfix, design, or review
  --no-run                          Initialize without creating a workflow run
  --yes                             Confirm non-interactive changes
  --dry-run                         Show the plan without modifying files
  --force-new                       Use TARGET-N when TARGET already exists
  --verbose                         Show detailed subcommand output
  -h, --help                        Show this help
EOF
  exit "${1:-2}"
}

fail() { printf '[FAIL] %s\n' "$1" >&2; [ -n "${2:-}" ] && printf '%s\n' "$2" >&2; exit 1; }
stage() { printf '[%s/7] %-24s %s\n' "$1" "$2" "$3"; }
capture() {
  output_file=$(mktemp "${TMPDIR:-/tmp}/ccb-quickstart-output.XXXXXX") || return 1
  if "$@" >"$output_file" 2>&1; then status=0; else status=$?; fi
  [ "$verbose" -eq 1 ] && cat "$output_file"
  rm -f "$output_file"; output_file=; return "$status"
}
capture_with_output() {
  output_file=$(mktemp "${TMPDIR:-/tmp}/ccb-quickstart-output.XXXXXX") || return 1
  if "$@" >"$output_file" 2>&1; then status=0; else status=$?; fi
  [ "$verbose" -eq 1 ] && cat "$output_file"
  return "$status"
}

quickstart_hook() {
  [ "${CCB_TEST_MODE:-0}" = 1 ] || return 0
  [ "${CCB_TEST_QUICKSTART_FAIL_STAGE:-}" = "$1" ] || return 0
  printf 'test quickstart failure at %s\n' "$1" >&2
  return 1
}

path_is_safe() {
  value=$1
  case "/$value/" in */../*|*/.git/*) return 1;; esac
  [ "$value" != / ] && [ "$value" != "$HOME" ] && [ "$value" != "$TEMPLATE_ROOT" ]
}

check_target_path() {
  path=$1
  path_is_safe "$path" || return 1
  if [ -L "$path" ]; then return 1; fi
  if [ -e "$path" ]; then [ -d "$path" ] || return 1; fi
  parent=$(dirname "$path")
  [ -d "$parent" ] && [ ! -L "$parent" ] || return 1
  [ "$parent" != "$TEMPLATE_ROOT" ] || return 1
}

choose_force_target() {
  original=$target
  [ "$force_new" -eq 1 ] && [ -e "$target" ] || return 0
  suffix=2
  while :; do
    candidate="$original-$suffix"
    [ ! -e "$candidate" ] && [ ! -L "$candidate" ] && { target=$candidate; return 0; }
    suffix=$((suffix + 1))
    [ "$suffix" -le 9999 ] || return 1
  done
}

record_before_state() {
  project_before=0; models_before=0; skills_before=0; agents_conf_before=0; workflows_before=0; context_before=0; agents_before=0
  [ -e "$target/.ccb/project.conf" ] || [ -L "$target/.ccb/project.conf" ] && project_before=1
  [ -e "$target/.ccb/models.conf" ] || [ -L "$target/.ccb/models.conf" ] && models_before=1
  [ -e "$target/.ccb/skills.conf" ] || [ -L "$target/.ccb/skills.conf" ] && skills_before=1
  [ -e "$target/.ccb/agents.conf" ] || [ -L "$target/.ccb/agents.conf" ] && agents_conf_before=1
  [ -e "$target/.ccb/workflows.conf" ] || [ -L "$target/.ccb/workflows.conf" ] && workflows_before=1
  [ -e "$target/.ccb/context/project.md" ] || [ -L "$target/.ccb/context/project.md" ] && context_before=1
  [ -e "$target/AGENTS.md" ] || [ -L "$target/AGENTS.md" ] && agents_before=1
  if [ -f "$target/.ccb/models.conf" ] && [ ! -L "$target/.ccb/models.conf" ]; then
    models_before_path=$(mktemp "${TMPDIR:-/tmp}/ccb-quickstart-models.XXXXXX") || return 1
    cp "$target/.ccb/models.conf" "$models_before_path" || return 1
  fi
  models_backup_list=$(mktemp "${TMPDIR:-/tmp}/ccb-quickstart-backups.XXXXXX") || return 1
  find "$target/.ccb" -maxdepth 1 -type f -name 'models.conf.backup-*' -print 2>/dev/null >"$models_backup_list" || :
}

remove_new_backups() {
  [ -f "$models_backup_list" ] || return 0
  for backup in "$target/.ccb"/models.conf.backup-*; do
    [ -f "$backup" ] || continue
    grep -Fqx "$backup" "$models_backup_list" || rm -f "$backup"
  done
}

rollback() {
  [ -n "$run_id" ] && [ -d "$target/.ccb/runs/$run_id" ] && [ ! -L "$target/.ccb/runs/$run_id" ] && rm -f "$target/.ccb/runs/$run_id"/*/* "$target/.ccb/runs/$run_id"/* 2>/dev/null || :
  [ -n "$run_id" ] && rmdir "$target/.ccb/runs/$run_id"/* "$target/.ccb/runs/$run_id" 2>/dev/null || :
  if [ "$models_before" -eq 1 ] && [ -f "$models_before_path" ]; then cp "$models_before_path" "$target/.ccb/models.conf"; else [ "$models_before" -eq 0 ] && rm -f "$target/.ccb/models.conf"; fi
  remove_new_backups
  [ "$project_before" -eq 1 ] || rm -f "$target/.ccb/project.conf"
  [ "$skills_before" -eq 1 ] || rm -f "$target/.ccb/skills.conf"
  [ "$agents_conf_before" -eq 1 ] || rm -f "$target/.ccb/agents.conf"
  [ "$workflows_before" -eq 1 ] || rm -f "$target/.ccb/workflows.conf"
  [ "$context_before" -eq 1 ] || rm -f "$target/.ccb/context/project.md"
  [ "$agents_before" -eq 1 ] || rm -f "$target/AGENTS.md"
  [ "$context_was_created" -eq 1 ] && rmdir "$target/.ccb/context" 2>/dev/null || :
  [ "$ccb_was_created" -eq 1 ] && rmdir "$target/.ccb" 2>/dev/null || :
  [ "$target_was_created" -eq 1 ] && rmdir "$target" 2>/dev/null || :
}

cleanup() {
  status=$?
  [ "$status" -eq 0 ] || rollback
  [ -n "$models_before_path" ] && rm -f "$models_before_path"
  [ -n "$models_backup_list" ] && rm -f "$models_backup_list"
  [ -n "$output_file" ] && rm -f "$output_file"
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage 0;;
    --name|--project-name) shift; [ "$#" -gt 0 ] || usage 2; [ -z "$project_name" ] || [ "$project_name" = "$1" ] || fail 'conflicting --name and --project-name values'; project_name=$1;;
    --profile) shift; [ "$#" -gt 0 ] || usage 2; profile=$1;;
    --cloud) cloud=1;; --preset) shift; [ "$#" -gt 0 ] || usage 2; preset=$1;;
    --run) shift; [ "$#" -gt 0 ] || usage 2; run_workflow=$1;; --no-run) no_run=1;; --yes) yes=1;; --dry-run) dry_run=1;; --force-new) force_new=1;; --verbose) verbose=1;;
    -*) echo "error: unknown option: $1" >&2; usage 2;;
    *) [ -z "$target" ] || usage 2; target=$1;;
  esac
  shift
done
[ -n "$target" ] || usage 2
[ "$no_run" -eq 0 ] || [ -z "$run_workflow" ] || fail '--no-run cannot be combined with --run'
case "$run_workflow" in ''|feature|bugfix|design|review) :;; *) fail "unsupported workflow: $run_workflow";; esac
choose_force_target || fail 'could not choose a safe --force-new target'
check_target_path "$target" || fail 'TARGET must be a safe, real directory path'
project_profile_id_is_safe "$profile" && project_profile_parse "$TEMPLATE_ROOT/project-profiles/$profile.conf" && [ "$PROJECT_PROFILE_ID" = "$profile" ] || fail "unsupported profile: $profile"
[ -n "$preset" ] || [ "$cloud" -eq 0 ] || preset=coding-cloud
[ -z "$preset" ] || { model_preset_is_safe "$preset" && model_preset_parse "$TEMPLATE_ROOT/model-presets/$preset/preset.conf" && [ "$PRESET_ID" = "$preset" ] || fail "unsupported model preset: $preset"; }
if [ "$cloud" -eq 1 ]; then mode=local-proxy; else mode=local; fi
if [ "$cloud" -eq 1 ]; then
  for cloud_model in "$MANAGER_MODEL" "$GRAPH_MODEL" "$GRAPHISTE_MODEL" "$DEVELOPER_MODEL" "$REVIEWER_MODEL" "$FALLBACK_MODEL"; do model_is_cloud "$cloud_model" || fail 'cloud preset contains a non-cloud model'; done
fi

stage 1 'Prerequisites' 'checking'
command -v sh >/dev/null 2>&1 || fail 'POSIX sh is required'
command -v mktemp >/dev/null 2>&1 || fail 'mktemp is required'
stage 1 'Prerequisites' 'OK'
stage 2 'Ollama' 'checking'
if [ "${CCB_TEST_MODE:-0}" = 1 ]; then
  :
else
  command -v ollama >/dev/null 2>&1 || fail 'Ollama is not installed. Install Ollama, then retry.'
  OLLAMA_HOST=http://127.0.0.1:11434 ollama --version >/dev/null 2>&1 || fail 'Ollama service is not reachable at http://127.0.0.1:11434.'
  OLLAMA_HOST=http://127.0.0.1:11434 ollama list >/dev/null 2>&1 || fail 'Ollama service is stopped. Start Ollama, then retry.'
fi
stage 2 'Ollama' 'OK'
stage 3 'Ollama Cloud' 'checking'
if [ "$cloud" -eq 1 ] && [ "${CCB_TEST_MODE:-0}" != 1 ]; then
  probe_model=$MANAGER_MODEL
  probe_result=$(OLLAMA_HOST=http://127.0.0.1:11434 ollama run "$probe_model" 'Reply with OK.' 2>&1); probe_status=$?
  if [ "$probe_status" -ne 0 ]; then
    probe_lc=$(printf '%s' "$probe_result" | tr '[:upper:]' '[:lower:]')
    case "$probe_lc" in *signin*|*'sign in'*|*'not authenticated'*|*unauthenticated*) fail 'Cloud authentication' 'Run:
  ollama signin

Then retry:
  ./ccb quickstart ...';; *) fail "Cloud model unavailable: $probe_model" 'Check Ollama Cloud access, then retry.';; esac
  fi
fi
stage 3 'Ollama Cloud' 'OK'

if [ "$dry_run" -eq 1 ]; then
  printf '[4/7] Project bootstrap ...... DRY RUN\n[5/7] Cloud models ............. DRY RUN\n[6/7] Doctor strict ............ DRY RUN\n[7/7] Workflow ................ %s\n' "${run_workflow:-not-run}"
  printf '\nProject: %s\nTarget: %s\nProfile: %s\nProvider: %s\nPreset: %s\n\nDRY RUN — no files were modified.\n' "${project_name:-$(basename "$target")}" "$target" "$profile" 'Ollama' "${preset:-project defaults}"
  exit 0
fi

if [ ! -e "$target" ]; then target_was_created=1; fi
[ -d "$target" ] || { parent=$(dirname "$target"); mkdir "$target" || fail 'cannot create TARGET'; }
[ -d "$target/.ccb" ] && ccb_was_created=0 || ccb_was_created=1
[ -d "$target/.ccb/context" ] && context_was_created=0 || context_was_created=1
record_before_state || fail 'cannot snapshot pre-existing project state'
stage 4 'Project bootstrap' 'running'
if [ "$yes" -eq 1 ]; then
  if [ -n "$project_name" ]; then capture "$PROJECT_INIT" "$target" --project-name "$project_name" --profile "$profile" --ponytail-mode full --yes; else capture "$PROJECT_INIT" "$target" --profile "$profile" --ponytail-mode full --yes; fi
  [ "$?" -eq 0 ] || fail 'Project bootstrap failed; no compatible files were changed.'
else
  if [ -n "$project_name" ]; then capture "$PROJECT_INIT" "$target" --project-name "$project_name" --profile "$profile" --ponytail-mode full; else capture "$PROJECT_INIT" "$target" --profile "$profile" --ponytail-mode full; fi
  [ "$?" -eq 0 ] || fail 'Project bootstrap requires --yes in non-interactive mode'
fi
stage 4 'Project bootstrap' 'OK'
quickstart_hook bootstrap || fail 'Quickstart stopped during bootstrap'

stage 5 'Cloud models' 'running'
if [ "$cloud" -eq 1 ]; then
  models_conf_parse "$target/.ccb/models.conf" 2>/dev/null && [ "$MODEL_CONF_FORMAT" = roles ] && [ "$MODEL_CONF_PRESET" = "$preset" ] && [ "$MODEL_CONF_MODE" = "$mode" ] || capture "$MODEL_SETUP" "$target" --preset "$preset" --mode "$mode" --yes || fail 'Cloud model configuration failed'
else
  models_conf_parse "$target/.ccb/models.conf" >/dev/null 2>&1 || fail 'Project model configuration is incompatible'
fi
stage 5 'Cloud models' 'OK'
quickstart_hook config || fail 'Quickstart stopped during model configuration'

stage 6 'Doctor strict' 'running'
capture "$PROJECT_CONFIG" "$target" || fail 'Project configuration validation failed'
capture "$DOCTOR" "$target" --no-ollama --strict || fail 'Doctor strict failed; no workflow was started'
stage 6 'Doctor strict' 'OK'
quickstart_hook doctor || fail 'Quickstart stopped after Doctor'

workflow_status=ready
if [ -n "$run_workflow" ]; then
  stage 7 "Workflow $run_workflow" 'starting'
  capture_with_output "$PROJECT_RUNS" start "$run_workflow" "$target" || fail 'Workflow creation failed'
  run_id=$(sed -n 's/^Run ID: //p' "$output_file" | head -1)
  [ -n "$run_id" ] || fail 'Workflow creation returned no run identifier'
  capture "$PROJECT_RUNS" inspect "$run_id" "$target" || fail 'Workflow snapshot inspection failed'
  capture "$PROJECT_RUNS" run "$run_id" "$target" || fail 'Workflow execution failed'
  workflow_status=completed
  rm -f "$output_file"; output_file=
else
  workflow_status=not-created
fi

printf '\nProject: %s\nTarget: %s\nProfile: %s\nProvider: %s%s\nPreset: %s\nWorkflow: %s\nStatus: %s\n\nCCB project ready.\n' \
  "${project_name:-$(basename "$target")}" "$target" "$profile" 'Ollama' "$( [ "$cloud" -eq 1 ] && printf ' Cloud' || printf '')" "${preset:-project defaults}" "${run_workflow:-none}" "$workflow_status"
exit 0
