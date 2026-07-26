#!/bin/sh
# Minimal, local-only CCB project bootstrap. Managed files always end in a newline.
set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
HOME_ROOT=$(CDPATH= cd "${HOME:?HOME is required}" && pwd)
target= project_name= profile=generic yes=0 dry_run=0 new_target=0
tmp_expected_conf= tmp_expected_context= tmp_expected_agents=
tmp_conf= tmp_context= tmp_agents=

usage() {
  cat >&2 <<'EOF'
usage: ccb.sh init TARGET [OPTIONS]

Create only .ccb/project.conf, .ccb/context/project.md, and AGENTS.md.

Options:
  --project-name NAME  Set the literal project name
  --profile generic    Use the only supported bootstrap profile
  --yes                Permit creation of a new target without a TTY
  --dry-run            Show the complete plan without modifying files
  -h, --help           Show this help
EOF
  exit "${1:-2}"
}

error() { printf 'error: %s\n' "$*" >&2; }

cleanup() {
  status=$?
  for file in "$tmp_conf" "$tmp_context" "$tmp_agents" "$tmp_expected_conf" "$tmp_expected_context" "$tmp_expected_agents"; do
    if [ -n "$file" ] && [ -f "$file" ] && [ ! -L "$file" ]; then rm -f "$file" || :; fi
  done
  return "$status"
}
trap 'cleanup' EXIT
trap 'cleanup; exit 129' HUP
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage 0 ;;
    --project-name) shift; [ "$#" -gt 0 ] || { error '--project-name requires a value'; exit 2; }; project_name=$1 ;;
    --profile) shift; [ "$#" -gt 0 ] || { error '--profile requires a value'; exit 2; }; profile=$1 ;;
    --yes) yes=1 ;;
    --dry-run) dry_run=1 ;;
    --force|--no-models|--single-model|--description|--non-interactive) error "option not supported in bootstrap init: $1"; exit 2 ;;
    -*) usage 2 ;;
    *) [ -z "$target" ] || { error 'only one TARGET is accepted'; exit 2; }; target=$1 ;;
  esac
  shift
done
[ -n "$target" ] || usage 2
[ "$profile" = generic ] || { error "unsupported bootstrap profile: $profile"; exit 2; }

# Validate path components instead of naively rejecting names containing "..".
case "/$target/" in */../*|*/.git/*) error 'unsafe target path'; exit 2;; esac
if [ -e "$target" ] || [ -L "$target" ]; then
  [ -d "$target" ] && [ ! -L "$target" ] || { error 'target is not a real directory'; exit 2; }
  target=$(CDPATH= cd "$target" && pwd) || { error 'cannot resolve target directory'; exit 2; }
else
  parent=$(dirname "$target"); leaf=$(basename "$target")
  [ "$leaf" != .git ] || { error 'unsafe target path'; exit 2; }
  [ -d "$parent" ] && [ ! -L "$parent" ] || { error 'target parent is not a real directory'; exit 2; }
  parent=$(CDPATH= cd "$parent" && pwd) || { error 'cannot resolve target parent'; exit 2; }
  target=$parent/$leaf; new_target=1
fi
case "$target" in /|"$HOME_ROOT"|"$TEMPLATE_ROOT") error 'unsafe target path'; exit 2;; esac
case "/$target/" in */.git/*) error 'unsafe target path'; exit 2;; esac

[ -n "$project_name" ] || project_name=$(basename "$target")
[ -n "$project_name" ] || { error 'invalid project name'; exit 2; }
case "$project_name" in *'
'*|*''*) error 'project name must not contain a line break'; exit 2;; esac

# Expected files are generated once outside TARGET, retaining their final newline.
tmp_expected_conf=$(mktemp "${TMPDIR:-/tmp}/ccb-init-conf.XXXXXX") || { error 'cannot create temporary file'; exit 1; }
tmp_expected_context=$(mktemp "${TMPDIR:-/tmp}/ccb-init-context.XXXXXX") || { error 'cannot create temporary file'; exit 1; }
tmp_expected_agents=$(mktemp "${TMPDIR:-/tmp}/ccb-init-agents.XXXXXX") || { error 'cannot create temporary file'; exit 1; }
printf 'CCB_PROJECT_NAME=%s\nCCB_PROJECT_PROFILE=generic\nCCB_PROJECT_VERSION=1\nCCB_TEMPLATE_VERSION=1.6.0\n' "$project_name" >"$tmp_expected_conf" || exit 1
printf '# Project context\n\nProject: %s\nProfile: generic\n' "$project_name" >"$tmp_expected_context" || exit 1
printf '# Agent guidance\n\nRead .ccb/context/project.md before modifying files. Follow project safety conventions.\n' >"$tmp_expected_agents" || exit 1

state_conf=CREATE state_context=CREATE state_agents=CREATE conflicts= conflict_messages=
mark_conflict() {
  conflicts=1
  conflict_messages="${conflict_messages}${1}
"
}
classify_file() {
  destination=$1 expected=$2 label=$3
  if [ -L "$destination" ]; then mark_conflict "error: symbolic links are not accepted: $label"; classification=CONFLICT
  elif [ -e "$destination" ]; then
    if [ ! -f "$destination" ]; then mark_conflict "error: conflicting path is not a regular file: $label"; classification=CONFLICT
    elif cmp -s "$expected" "$destination"; then classification=SKIP
    else mark_conflict "error: conflicting managed file: $label"; classification=CONFLICT; fi
  else classification=CREATE; fi
}

if [ "$new_target" -eq 0 ] && { [ -L "$target/.ccb" ] || { [ -e "$target/.ccb" ] && [ ! -d "$target/.ccb" ]; }; }; then
  mark_conflict 'error: incompatible parent path: .ccb'; state_conf=CONFLICT; state_context=CONFLICT
else
  classify_file "$target/.ccb/project.conf" "$tmp_expected_conf" '.ccb/project.conf'; state_conf=$classification
  if [ "$new_target" -eq 0 ] && { [ -L "$target/.ccb/context" ] || { [ -e "$target/.ccb/context" ] && [ ! -d "$target/.ccb/context" ]; }; }; then
    mark_conflict 'error: incompatible parent path: .ccb/context'; state_context=CONFLICT
  else classify_file "$target/.ccb/context/project.md" "$tmp_expected_context" '.ccb/context/project.md'; state_context=$classification; fi
fi
classify_file "$target/AGENTS.md" "$tmp_expected_agents" AGENTS.md; state_agents=$classification
printf 'Plan:\n  %s .ccb/project.conf\n  %s .ccb/context/project.md\n  %s AGENTS.md\n' "$state_conf" "$state_context" "$state_agents"
if [ -n "$conflicts" ]; then
  printf '%s' "$conflict_messages" >&2
  error 'initialization aborted because managed files conflict'
  exit 1
fi
if [ "$dry_run" -eq 1 ]; then printf 'DRY RUN — no files were modified\n'; exit 0; fi
if [ "$new_target" -eq 1 ] && [ "$yes" -ne 1 ] && [ ! -t 0 ]; then error '--yes is required to create a new target without a TTY'; exit 2; fi

created_target=0 created_ccb=0 created_context=0
if [ "$new_target" -eq 1 ]; then mkdir "$target" || { error 'cannot create target directory'; exit 1; }; created_target=1; fi
if [ ! -d "$target/.ccb" ]; then mkdir "$target/.ccb" || { error 'cannot create .ccb directory'; exit 1; }; created_ccb=1; fi
if [ ! -d "$target/.ccb/context" ]; then mkdir "$target/.ccb/context" || { error 'cannot create .ccb/context directory'; exit 1; }; created_context=1; fi

prepare_file() {
  destination=$1 expected=$2 kind=$3 directory=$(dirname "$destination") base=$(basename "$destination")
  temp=$(mktemp "$directory/.${base}.tmp.XXXXXX") || return 1
  if ! cp "$expected" "$temp" || ! chmod 644 "$temp"; then rm -f "$temp" || :; return 1; fi
  case "$kind" in conf) tmp_conf=$temp;; context) tmp_context=$temp;; agents) tmp_agents=$temp;; esac
}
prepare_all() {
  [ "$state_conf" != CREATE ] || prepare_file "$target/.ccb/project.conf" "$tmp_expected_conf" conf || return 1
  [ "$state_context" != CREATE ] || prepare_file "$target/.ccb/context/project.md" "$tmp_expected_context" context || return 1
  [ "$state_agents" != CREATE ] || prepare_file "$target/AGENTS.md" "$tmp_expected_agents" agents || return 1
}
if ! prepare_all; then
  error 'cannot prepare all managed files; no files were finalized'
  [ "$created_context" -eq 0 ] || rmdir "$target/.ccb/context" 2>/dev/null || :
  [ "$created_ccb" -eq 0 ] || rmdir "$target/.ccb" 2>/dev/null || :
  [ "$created_target" -eq 0 ] || rmdir "$target" 2>/dev/null || :
  exit 1
fi
finalize_file() { temp=$1 destination=$2; [ -z "$temp" ] || mv "$temp" "$destination"; }
if ! finalize_file "$tmp_conf" "$target/.ccb/project.conf" || ! finalize_file "$tmp_context" "$target/.ccb/context/project.md" || ! finalize_file "$tmp_agents" "$target/AGENTS.md"; then
  error 'failed to finalize one or more managed files'; exit 1
fi
tmp_conf= tmp_context= tmp_agents=
printf 'CCB bootstrap initialized: %s\n' "$target"
