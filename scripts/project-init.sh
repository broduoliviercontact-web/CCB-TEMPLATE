#!/bin/sh
set -u
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
PROFILE_ROOT="$TEMPLATE_ROOT/project-profiles"
HOME_ROOT=$(CDPATH= cd "${HOME:?HOME is required}" && pwd)
. "$SCRIPT_DIR/model-lib.sh"
. "$SCRIPT_DIR/project-profile-lib.sh"
. "$SCRIPT_DIR/project-skills-lib.sh"
. "$SCRIPT_DIR/project-agents-lib.sh"

target= project_name= profile=generic profile_set=0 model= planner_model= coder_model= reviewer_model= ponytail_mode=full yes=0 dry_run=0 new_target=0
tmp_project= tmp_models= tmp_skills= tmp_agents_conf= tmp_context= tmp_agents= expected_project= expected_models= expected_skills= expected_agents_conf= expected_context= expected_agents=
usage() { cat >&2 <<'EOF'
usage: ccb.sh init TARGET [OPTIONS]

Options:
  --project-name NAME    Set the literal project name
  --profile PROFILE      generic, web, node, python, or audio
  --model MODEL          Set the default model for all roles
  --planner-model MODEL  Override the planner model
  --coder-model MODEL    Override the coder model
  --reviewer-model MODEL Override the reviewer model
  --ponytail-mode MODE  off, lite, full, or ultra (default: full)
  --yes                  Permit creation of a new target without a TTY
  --dry-run              Show the plan without modifying files
  -h, --help             Show this help
EOF
  exit "${1:-2}"
}
error() { printf 'error: %s\n' "$*" >&2; }
cleanup() { status=$?; for file in "$tmp_project" "$tmp_models" "$tmp_skills" "$tmp_agents_conf" "$tmp_context" "$tmp_agents" "$expected_project" "$expected_models" "$expected_skills" "$expected_agents_conf" "$expected_context" "$expected_agents"; do [ -n "$file" ] && [ -f "$file" ] && [ ! -L "$file" ] && rm -f "$file" || :; done; return "$status"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 129' HUP
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage 0;; --project-name) shift; [ "$#" -gt 0 ] || { error '--project-name requires a value'; exit 2; }; project_name=$1;;
    --profile) shift; [ "$#" -gt 0 ] || { error '--profile requires a value'; exit 2; }; profile=$1; profile_set=1;;
    --model) shift; [ "$#" -gt 0 ] || { error '--model requires a value'; exit 2; }; model=$1;;
    --planner-model) shift; [ "$#" -gt 0 ] || { error '--planner-model requires a value'; exit 2; }; planner_model=$1;;
    --coder-model) shift; [ "$#" -gt 0 ] || { error '--coder-model requires a value'; exit 2; }; coder_model=$1;;
    --reviewer-model) shift; [ "$#" -gt 0 ] || { error '--reviewer-model requires a value'; exit 2; }; reviewer_model=$1;;
    --ponytail-mode) shift; [ "$#" -gt 0 ] || { error '--ponytail-mode requires a value'; exit 2; }; ponytail_mode=$1;;
    --yes) yes=1;; --dry-run) dry_run=1;; --force|--no-models|--single-model|--description|--non-interactive) error "option not supported in project init: $1"; exit 2;;
    -*) usage 2;; *) [ -z "$target" ] || { error 'only one TARGET is accepted'; exit 2; }; target=$1;;
  esac
  shift
done
[ -n "$target" ] || usage 2
project_profile_id_is_safe "$profile" && project_profile_parse "$PROFILE_ROOT/$profile.conf" && [ "$PROJECT_PROFILE_ID" = "$profile" ] || { error "unsupported project profile: $profile"; printf 'supported profiles: %s\n' "$(project_profiles_list)" >&2; exit 2; }
for candidate in "$model" "$planner_model" "$coder_model" "$reviewer_model"; do [ -z "$candidate" ] || model_name_is_safe "$candidate" || { error 'invalid model name'; exit 2; }; done
ponytail_mode_is_valid "$ponytail_mode" || { error "unsupported Ponytail mode: $ponytail_mode"; echo 'supported modes: off, lite, full, ultra' >&2; exit 2; }
case "/$target/" in */../*|*/.git/*) error 'unsafe target path'; exit 2;; esac
if [ -e "$target" ] || [ -L "$target" ]; then [ -d "$target" ] && [ ! -L "$target" ] || { error 'target is not a real directory'; exit 2; }; target=$(CDPATH= cd "$target" && pwd) || exit 2
else parent=$(dirname "$target"); leaf=$(basename "$target"); [ "$leaf" != .git ] && [ -d "$parent" ] && [ ! -L "$parent" ] || { error 'unsafe target path'; exit 2; }; parent=$(CDPATH= cd "$parent" && pwd) || exit 2; target=$parent/$leaf; new_target=1; fi
case "$target" in /|"$HOME_ROOT"|"$TEMPLATE_ROOT") error 'unsafe target path'; exit 2;; esac
[ -n "$project_name" ] || project_name=$(basename "$target")
case "$project_name" in ''|*'
'*|*''*) error 'invalid project name'; exit 2;; esac
default_model=${model:-$PROJECT_MODEL_DEFAULT}; planner=${planner_model:-${model:-$PROJECT_MODEL_PLANNER}}; coder=${coder_model:-${model:-$PROJECT_MODEL_CODER}}; reviewer=${reviewer_model:-${model:-$PROJECT_MODEL_REVIEWER}}

expected_project=$(mktemp "${TMPDIR:-/tmp}/ccb-project.XXXXXX") || exit 1; expected_models=$(mktemp "${TMPDIR:-/tmp}/ccb-models.XXXXXX") || exit 1; expected_context=$(mktemp "${TMPDIR:-/tmp}/ccb-context.XXXXXX") || exit 1; expected_agents=$(mktemp "${TMPDIR:-/tmp}/ccb-agents.XXXXXX") || exit 1
expected_skills=$(mktemp "${TMPDIR:-/tmp}/ccb-skills.XXXXXX") || exit 1; expected_agents_conf=$(mktemp "${TMPDIR:-/tmp}/ccb-agents-conf.XXXXXX") || exit 1
printf 'CCB_PROJECT_NAME=%s\nCCB_PROJECT_PROFILE=%s\nCCB_PROJECT_VERSION=1\nCCB_TEMPLATE_VERSION=1.7.0\n' "$project_name" "$profile" >"$expected_project" || exit 1
printf 'CCB_MODEL_PROVIDER=ollama\nCCB_MODEL_DEFAULT=%s\nCCB_MODEL_PLANNER=%s\nCCB_MODEL_CODER=%s\nCCB_MODEL_REVIEWER=%s\n' "$default_model" "$planner" "$coder" "$reviewer" >"$expected_models" || exit 1
case "$ponytail_mode" in off) ponytail_status=disabled; ponytail_rules='Ponytail rules are disabled for this project.';; lite) ponytail_status=enabled; ponytail_rules='Confirm necessity. Reuse existing helpers. Prefer standard and native features. Keep changes small and targeted.';; full) ponytail_status=enabled; ponytail_rules='Confirm necessity. Trace the affected flow. Reuse existing helpers. Prefer standard and native features. Fix root causes. Make the smallest complete change. Leave a focused runnable check. Never weaken validation, error handling, security, accessibility, or project safety constraints.';; ultra) ponytail_status=enabled; ponytail_rules='Apply full rules. Challenge unnecessary features. Use the smallest justified complete diff. Add no avoidable dependency or abstraction. Inspect affected flows before writing and justify extra files. Never weaken validation, error handling, security, accessibility, or project safety constraints.';; esac
printf 'CCB_SKILLS_VERSION=1\nCCB_SKILL_PONYTAIL=%s\nCCB_SKILL_PONYTAIL_MODE=%s\nCCB_SKILL_PONYTAIL_SOURCE=DietrichGebert/ponytail\nCCB_SKILL_PONYTAIL_REF=main\n' "$ponytail_status" "$ponytail_mode" >"$expected_skills" || exit 1
project_agents_default_content >"$expected_agents_conf" || exit 1
printf '# Project context\n\nProject: %s\nProfile: %s\n\n## Profile guidance\n\n%s\n\nSafety: %s\n\n## Skills\n\nPonytail: %s\nPonytail mode: %s\nSource: DietrichGebert/ponytail\n\n## Agent roles\n\n- manager — read-only\n- graph — read-only\n- graphiste — write\n- developer — write\n- reviewer — read-only\n\nAccess levels are declarative in V1.7.0 and are not an operating-system sandbox.\n\n## Model routing\n\nProvider: ollama\nDefault: %s\nPlanner: %s\nCoder: %s\nReviewer: %s\n' "$project_name" "$profile" "$PROJECT_PROFILE_GUIDANCE" "$PROJECT_PROFILE_SECURITY" "$ponytail_status" "$ponytail_mode" "$default_model" "$planner" "$coder" "$reviewer" >"$expected_context" || exit 1
printf '# Agent guidance\n\nRead .ccb/context/project.md before modifying files.\nRead .ccb/models.conf before selecting a model or agent role.\nRead .ccb/skills.conf before applying project skills.\nRead .ccb/agents.conf before selecting an agent role.\nRespect the active role: read-only roles provide analysis or recommendations only; write roles change only what is necessary and verify first. Access is declarative only, not an operating-system sandbox.\n\n## Ponytail\n\nMode: %s\nSource: DietrichGebert/ponytail\n\n%s\n' "$ponytail_mode" "$ponytail_rules" >"$expected_agents" || exit 1

conflicts= messages= state_project=CREATE state_models=CREATE state_skills=CREATE state_agents_conf=CREATE state_context=CREATE state_agents=CREATE
conflict() { conflicts=1; messages="${messages}${1}
"; }
classify() { path=$1 expected=$2 label=$3; if [ -L "$path" ]; then conflict "error: symbolic links are not accepted: $label"; result=CONFLICT; elif [ -e "$path" ]; then if [ -f "$path" ] && cmp -s "$expected" "$path"; then result=SKIP; else conflict "error: conflicting managed file: $label"; result=CONFLICT; fi; else result=CREATE; fi; }
if [ "$new_target" -eq 0 ] && { [ -L "$target/.ccb" ] || { [ -e "$target/.ccb" ] && [ ! -d "$target/.ccb" ]; }; }; then conflict 'error: incompatible parent path: .ccb'; state_project=CONFLICT; state_models=CONFLICT; state_context=CONFLICT
else
  classify "$target/.ccb/project.conf" "$expected_project" .ccb/project.conf; state_project=$result
  classify "$target/.ccb/models.conf" "$expected_models" .ccb/models.conf; state_models=$result
  classify "$target/.ccb/skills.conf" "$expected_skills" .ccb/skills.conf; state_skills=$result
  classify "$target/.ccb/agents.conf" "$expected_agents_conf" .ccb/agents.conf; state_agents_conf=$result
  if [ "$new_target" -eq 0 ] && { [ -L "$target/.ccb/context" ] || { [ -e "$target/.ccb/context" ] && [ ! -d "$target/.ccb/context" ]; }; }; then conflict 'error: incompatible parent path: .ccb/context'; state_context=CONFLICT; else classify "$target/.ccb/context/project.md" "$expected_context" .ccb/context/project.md; state_context=$result; fi
fi
classify "$target/AGENTS.md" "$expected_agents" AGENTS.md; state_agents=$result
printf 'Plan:\n  %s .ccb/project.conf\n  %s .ccb/models.conf\n  %s .ccb/skills.conf\n  %s .ccb/agents.conf\n  %s .ccb/context/project.md\n  %s AGENTS.md\n' "$state_project" "$state_models" "$state_skills" "$state_agents_conf" "$state_context" "$state_agents"
if [ -n "$conflicts" ]; then printf '%s' "$messages" >&2; error 'initialization aborted because managed files conflict'; exit 1; fi
[ "$dry_run" -eq 0 ] || { echo 'DRY RUN — no files were modified'; exit 0; }
if [ "$new_target" -eq 1 ] && [ "$yes" -ne 1 ] && [ ! -t 0 ]; then error '--yes is required to create a new target without a TTY'; exit 2; fi
created_target=0 created_ccb=0 created_context=0
[ "$new_target" -eq 0 ] || { mkdir "$target" || exit 1; created_target=1; }
[ -d "$target/.ccb" ] || { mkdir "$target/.ccb" || exit 1; created_ccb=1; }
[ -d "$target/.ccb/context" ] || { mkdir "$target/.ccb/context" || exit 1; created_context=1; }
prepare() { dest=$1 expected=$2 kind=$3 dir=$(dirname "$dest"); base=$(basename "$dest"); temp=$(mktemp "$dir/.${base}.tmp.XXXXXX") || return 1; cp "$expected" "$temp" && chmod 644 "$temp" || { rm -f "$temp" || :; return 1; }; case "$kind" in project) tmp_project=$temp;; models) tmp_models=$temp;; skills) tmp_skills=$temp;; agents_conf) tmp_agents_conf=$temp;; context) tmp_context=$temp;; agents) tmp_agents=$temp;; esac; }
prepare_all() { [ "$state_project" != CREATE ] || prepare "$target/.ccb/project.conf" "$expected_project" project || return 1; [ "$state_models" != CREATE ] || prepare "$target/.ccb/models.conf" "$expected_models" models || return 1; [ "$state_skills" != CREATE ] || prepare "$target/.ccb/skills.conf" "$expected_skills" skills || return 1; [ "$state_agents_conf" != CREATE ] || prepare "$target/.ccb/agents.conf" "$expected_agents_conf" agents_conf || return 1; [ "$state_context" != CREATE ] || prepare "$target/.ccb/context/project.md" "$expected_context" context || return 1; [ "$state_agents" != CREATE ] || prepare "$target/AGENTS.md" "$expected_agents" agents || return 1; }
if ! prepare_all; then error 'cannot prepare all managed files; no files were finalized'; [ "$created_context" -eq 0 ] || rmdir "$target/.ccb/context" 2>/dev/null || :; [ "$created_ccb" -eq 0 ] || rmdir "$target/.ccb" 2>/dev/null || :; [ "$created_target" -eq 0 ] || rmdir "$target" 2>/dev/null || :; exit 1; fi
finalize() { temp=$1 dest=$2; [ -z "$temp" ] || mv "$temp" "$dest"; }
if ! finalize "$tmp_project" "$target/.ccb/project.conf" || ! finalize "$tmp_models" "$target/.ccb/models.conf" || ! finalize "$tmp_skills" "$target/.ccb/skills.conf" || ! finalize "$tmp_agents_conf" "$target/.ccb/agents.conf" || ! finalize "$tmp_context" "$target/.ccb/context/project.md" || ! finalize "$tmp_agents" "$target/AGENTS.md"; then error 'failed to finalize one or more managed files'; exit 1; fi
tmp_project= tmp_models= tmp_skills= tmp_agents_conf= tmp_context= tmp_agents=
printf 'CCB bootstrap initialized: %s\n' "$target"
