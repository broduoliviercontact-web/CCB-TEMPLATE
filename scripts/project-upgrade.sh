#!/bin/sh
# Safe, deliberately narrow migration for CCB bootstrap projects.
set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
PROFILE_ROOT="$TEMPLATE_ROOT/project-profiles"
. "$SCRIPT_DIR/model-lib.sh"
. "$SCRIPT_DIR/project-profile-lib.sh"
. "$SCRIPT_DIR/project-config-lib.sh"
. "$SCRIPT_DIR/project-skills-lib.sh"

target= dry_run=0 yes=0 ponytail_mode=full
state_project= state_models= state_skills= state_context= state_agents=
tmp_project= tmp_skills= tmp_context= tmp_agents=
backup_project= backup_context= backup_agents=
applied_project= applied_skills= applied_context= applied_agents=

usage() { cat >&2 <<'EOF'
usage: ccb.sh upgrade TARGET [OPTIONS]

Safely migrate a CCB bootstrap project from 1.6.0 to 1.6.1.

Options:
  --dry-run             Show the complete plan without modifying files
  --yes                 Apply the displayed plan without prompting
  --ponytail-mode MODE  off, lite, full, or ultra (default: full)
  -h, --help            Show this help
EOF
  exit "${1:-2}"
}
error() { printf 'error: %s\n' "$*" >&2; }
cleanup() { status=$?; for f in "$tmp_project" "$tmp_skills" "$tmp_context" "$tmp_agents" "$backup_project" "$backup_context" "$backup_agents"; do [ -n "$f" ] && [ -f "$f" ] && [ ! -L "$f" ] && rm -f "$f" || :; done; return "$status"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 129' HUP
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage 0;; --dry-run) dry_run=1;; --yes) yes=1;;
    --ponytail-mode) shift; [ "$#" -gt 0 ] || { error '--ponytail-mode requires a value'; exit 2; }; ponytail_mode=$1;;
    -*) error "unknown option: $1"; usage 2;;
    *) [ -z "$target" ] || { error 'only one TARGET is accepted'; exit 2; }; target=$1;;
  esac
  shift
done
[ -n "$target" ] || usage 2
ponytail_mode_is_valid "$ponytail_mode" || { error "unsupported Ponytail mode: $ponytail_mode"; exit 2; }
[ -d "$target" ] && [ ! -L "$target" ] || { error 'target is not a real directory'; exit 1; }
target=$(CDPATH= cd "$target" && pwd) || exit 1
[ -d "$target/.ccb" ] && [ ! -L "$target/.ccb" ] || { error 'invalid CCB project: .ccb is missing or unsafe'; exit 1; }
[ -d "$target/.ccb/context" ] && [ ! -L "$target/.ccb/context" ] || { error 'invalid CCB project: .ccb/context is missing or unsafe'; exit 1; }
project_conf_parse "$target/.ccb/project.conf" || { error 'invalid or missing project.conf'; exit 1; }
template_version=$(awk -F= '$1=="CCB_TEMPLATE_VERSION" {print $2}' "$target/.ccb/project.conf")
project_version=$(awk -F= '$1=="CCB_PROJECT_VERSION" {print $2}' "$target/.ccb/project.conf")
[ "$project_version" = 1 ] || { error "unsupported project configuration version: ${project_version:-missing}"; exit 1; }
case "$template_version" in
  1.6.0|1.6.1) ;;
  1.[7-9]*|[2-9]*) error "project template version $template_version is newer than this CCB template"; exit 1;;
  *) error "unsupported project template version: ${template_version:-missing}"; echo 'supported upgrade path: 1.6.0 -> 1.6.1' >&2; exit 1;;
esac
project_models_parse "$target/.ccb/models.conf" || { error 'invalid or missing models.conf'; exit 1; }
project_profile_parse "$PROFILE_ROOT/$PROJECT_PROFILE.conf" && [ "$PROJECT_PROFILE_ID" = "$PROJECT_PROFILE" ] || { error "unsupported project profile: $PROJECT_PROFILE"; exit 1; }

rules_for_mode() {
  case "$1" in
    off) ponytail_status=disabled; ponytail_rules='Ponytail rules are disabled for this project.';;
    lite) ponytail_status=enabled; ponytail_rules='Confirm necessity. Reuse existing helpers. Prefer standard and native features. Keep changes small and targeted.';;
    full) ponytail_status=enabled; ponytail_rules='Confirm necessity. Trace the affected flow. Reuse existing helpers. Prefer standard and native features. Fix root causes. Make the smallest complete change. Leave a focused runnable check. Never weaken validation, error handling, security, accessibility, or project safety constraints.';;
    ultra) ponytail_status=enabled; ponytail_rules='Apply full rules. Challenge unnecessary features. Use the smallest justified complete diff. Add no avoidable dependency or abstraction. Inspect affected flows before writing and justify extra files. Never weaken validation, error handling, security, accessibility, or project safety constraints.';;
  esac
}
legacy_project() { printf 'CCB_PROJECT_NAME=%s\nCCB_PROJECT_PROFILE=%s\nCCB_PROJECT_VERSION=1\nCCB_TEMPLATE_VERSION=1.6.0\n' "$PROJECT_NAME" "$PROJECT_PROFILE"; }
final_project() { printf 'CCB_PROJECT_NAME=%s\nCCB_PROJECT_PROFILE=%s\nCCB_PROJECT_VERSION=1\nCCB_TEMPLATE_VERSION=1.6.1\n' "$PROJECT_NAME" "$PROJECT_PROFILE"; }
legacy_context() { printf '# Project context\n\nProject: %s\nProfile: %s\n\n## Profile guidance\n\n%s\n\nSafety: %s\n\n## Model routing\n\nProvider: ollama\nDefault: %s\nPlanner: %s\nCoder: %s\nReviewer: %s\n' "$PROJECT_NAME" "$PROJECT_PROFILE" "$PROJECT_PROFILE_GUIDANCE" "$PROJECT_PROFILE_SECURITY" "$PROJECT_MODEL_DEFAULT" "$PROJECT_MODEL_PLANNER" "$PROJECT_MODEL_CODER" "$PROJECT_MODEL_REVIEWER"; }
legacy_agents() { printf '# Agent guidance\n\nRead .ccb/context/project.md before modifying files.\nRead .ccb/models.conf before selecting a model or agent role.\nFollow project safety conventions.\n'; }
final_skills() { rules_for_mode "$ponytail_mode"; printf 'CCB_SKILLS_VERSION=1\nCCB_SKILL_PONYTAIL=%s\nCCB_SKILL_PONYTAIL_MODE=%s\nCCB_SKILL_PONYTAIL_SOURCE=DietrichGebert/ponytail\nCCB_SKILL_PONYTAIL_REF=main\n' "$ponytail_status" "$ponytail_mode"; }
final_context() { rules_for_mode "$ponytail_mode"; printf '# Project context\n\nProject: %s\nProfile: %s\n\n## Profile guidance\n\n%s\n\nSafety: %s\n\n## Skills\n\nPonytail: %s\nPonytail mode: %s\nSource: DietrichGebert/ponytail\n\n## Model routing\n\nProvider: ollama\nDefault: %s\nPlanner: %s\nCoder: %s\nReviewer: %s\n' "$PROJECT_NAME" "$PROJECT_PROFILE" "$PROJECT_PROFILE_GUIDANCE" "$PROJECT_PROFILE_SECURITY" "$ponytail_status" "$ponytail_mode" "$PROJECT_MODEL_DEFAULT" "$PROJECT_MODEL_PLANNER" "$PROJECT_MODEL_CODER" "$PROJECT_MODEL_REVIEWER"; }
final_agents() { rules_for_mode "$ponytail_mode"; printf '# Agent guidance\n\nRead .ccb/context/project.md before modifying files.\nRead .ccb/models.conf before selecting a model or agent role.\nRead .ccb/skills.conf before applying project skills.\nFollow project safety conventions.\n\n## Ponytail\n\nMode: %s\nSource: DietrichGebert/ponytail\n\n%s\n' "$ponytail_mode" "$ponytail_rules"; }
same_generated() { generator=$1; path=$2; "$generator" | cmp -s "$path" -; }
classify_versioned() { path=$1 label=$2 old_generator=$3 final_generator=$4
  if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then result=CONFLICT; reason='symbolic link or non-regular file'
  elif [ ! -e "$path" ]; then result=CONFLICT; reason='required historical file is missing'
  elif same_generated "$final_generator" "$path"; then result=SKIP; reason=
  elif [ "$template_version" = 1.6.0 ] && same_generated "$old_generator" "$path"; then result=UPDATE; reason=
  else result=CONFLICT; reason='file differs from the recognized CCB 1.6.0 and 1.6.1 managed forms'; fi
  [ "$result" != CONFLICT ] || printf 'reason: %s\naction: preserve the file and migrate manually\n' "$reason" >&2
}
classify_skills() {
  path=$target/.ccb/skills.conf
  if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then result=CONFLICT
  elif [ ! -e "$path" ]; then [ "$template_version" = 1.6.0 ] && result=CREATE || result=CONFLICT
  elif same_generated final_skills "$path"; then result=SKIP
  else result=CONFLICT; fi
}
if [ "$template_version" = 1.6.1 ]; then
  for required in "$target/.ccb/project.conf" "$target/.ccb/models.conf" "$target/.ccb/skills.conf" "$target/.ccb/context/project.md" "$target/AGENTS.md"; do
    [ -f "$required" ] && [ ! -L "$required" ] || { error "invalid 1.6.1 managed file: $required"; exit 1; }
  done
  project_skills_parse "$target/.ccb/skills.conf" || { error 'invalid 1.6.1 skills.conf'; exit 1; }
  state_project=SKIP; state_models=SKIP; state_skills=SKIP; state_context=SKIP; state_agents=SKIP
else
  classify_versioned "$target/.ccb/project.conf" .ccb/project.conf legacy_project final_project; state_project=$result
  state_models=SKIP
  classify_skills; state_skills=$result
  classify_versioned "$target/.ccb/context/project.md" .ccb/context/project.md legacy_context final_context; state_context=$result
  classify_versioned "$target/AGENTS.md" AGENTS.md legacy_agents final_agents; state_agents=$result
fi

conflicts=0; for state in "$state_project" "$state_models" "$state_skills" "$state_context" "$state_agents"; do [ "$state" = CONFLICT ] && conflicts=$((conflicts + 1)); done
printf 'CCB Project Upgrade\nTarget: %s\nFrom: %s\nTo: 1.6.1\nPonytail mode: %s\n\nPlan:\n  %-8s %s\n  %-8s %s\n  %-8s %s\n  %-8s %s\n  %-8s %s\n\nSummary:\n  CREATE: %s\n  UPDATE: %s\n  SKIP: %s\n  CONFLICT: %s\n' "$target" "$template_version" "$ponytail_mode" "$state_project" .ccb/project.conf "$state_models" .ccb/models.conf "$state_skills" .ccb/skills.conf "$state_context" .ccb/context/project.md "$state_agents" AGENTS.md "$(printf '%s\n' "$state_project" "$state_models" "$state_skills" "$state_context" "$state_agents" | grep -c '^CREATE$')" "$(printf '%s\n' "$state_project" "$state_models" "$state_skills" "$state_context" "$state_agents" | grep -c '^UPDATE$')" "$(printf '%s\n' "$state_project" "$state_models" "$state_skills" "$state_context" "$state_agents" | grep -c '^SKIP$')" "$conflicts"
[ "$conflicts" -eq 0 ] || { echo 'No files were modified.'; exit 1; }
[ "$template_version" = 1.6.0 ] || { echo 'Result: already up to date'; exit 0; }
[ "$dry_run" -eq 0 ] || { echo 'DRY RUN — no files were modified'; exit 0; }
if [ "$yes" -ne 1 ]; then
  if [ ! -t 0 ]; then error 'upgrade requires --yes or --dry-run in non-interactive mode'; exit 2; fi
  printf 'Apply this upgrade? [y/N] '; IFS= read -r answer || exit 0
  case "$answer" in y|Y|yes|YES) :;; *) echo 'Upgrade cancelled.'; exit 0;; esac
fi

prepare() { dest=$1 generator=$2 kind=$3; dir=$(dirname "$dest"); base=$(basename "$dest"); temp=$(mktemp "$dir/.${base}.upgrade.XXXXXX") || return 1; "$generator" >"$temp" && chmod 644 "$temp" || { rm -f "$temp"; return 1; }; case "$kind" in project) tmp_project=$temp;; skills) tmp_skills=$temp;; context) tmp_context=$temp;; agents) tmp_agents=$temp;; esac; }
backup() { dest=$1 kind=$2; dir=$(dirname "$dest"); base=$(basename "$dest"); file=$(mktemp "$dir/.${base}.rollback.XXXXXX") || return 1; cp "$dest" "$file" || return 1; case "$kind" in project) backup_project=$file;; context) backup_context=$file;; agents) backup_agents=$file;; esac; }
prepare "$target/.ccb/project.conf" final_project project && prepare "$target/.ccb/skills.conf" final_skills skills && prepare "$target/.ccb/context/project.md" final_context context && prepare "$target/AGENTS.md" final_agents agents || { error 'could not prepare all replacement files'; exit 1; }
backup "$target/.ccb/project.conf" project && backup "$target/.ccb/context/project.md" context && backup "$target/AGENTS.md" agents || { error 'could not prepare rollback files'; exit 1; }
rollback() { [ -z "$applied_agents" ] || mv "$backup_agents" "$target/AGENTS.md" || :; [ -z "$applied_context" ] || mv "$backup_context" "$target/.ccb/context/project.md" || :; [ -z "$applied_skills" ] || rm -f "$target/.ccb/skills.conf" || :; [ -z "$applied_project" ] || mv "$backup_project" "$target/.ccb/project.conf" || :; }
apply_one() { temp=$1 dest=$2 kind=$3; mv "$temp" "$dest" || return 1; case "$kind" in project) tmp_project=; applied_project=1;; skills) tmp_skills=; applied_skills=1;; context) tmp_context=; applied_context=1;; agents) tmp_agents=; applied_agents=1;; esac; }
if ! apply_one "$tmp_project" "$target/.ccb/project.conf" project || ! apply_one "$tmp_skills" "$target/.ccb/skills.conf" skills || ! apply_one "$tmp_context" "$target/.ccb/context/project.md" context || ! apply_one "$tmp_agents" "$target/AGENTS.md" agents; then error 'upgrade write failed; attempting rollback'; rollback; exit 1; fi
echo "CCB project upgraded: $target"
