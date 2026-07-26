#!/bin/sh
# Read-only diagnostics for the CCB template and V1.6.0 bootstrap projects.
set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/model-lib.sh"
. "$SCRIPT_DIR/project-profile-lib.sh"
. "$SCRIPT_DIR/project-config-lib.sh"

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
  if [ ! -d "$target" ] || [ -L "$target" ]; then echo 'error: TARGET must be a real directory' >&2; exit 2; fi
  target=$(CDPATH= cd "$target" && pwd) || exit 2
  printf 'Target: %s\n' "$target"
else
  printf 'Target: template-only\n'
fi

for tool in sh sed grep awk mktemp mv chmod mkdir rm basename dirname; do
  if command -v "$tool" >/dev/null 2>&1; then emit OK "shell.$tool" available; else emit FAIL "shell.$tool" missing; fi
done

if [ -f "$TEMPLATE_ROOT/VERSION" ] && [ "$(cat "$TEMPLATE_ROOT/VERSION")" = 1.6.0 ]; then emit OK template.version 1.6.0; else emit FAIL template.version 'expected 1.6.0'; fi
for script in scripts/ccb.sh scripts/project-init.sh scripts/project-config.sh scripts/validate-ccb.sh; do
  if [ -x "$TEMPLATE_ROOT/$script" ]; then emit OK "template.$script" executable; else emit FAIL "template.$script" missing-or-not-executable; fi
  if [ -f "$TEMPLATE_ROOT/$script" ] && sh -n "$TEMPLATE_ROOT/$script" >/dev/null 2>&1; then emit OK "syntax.$script" valid; else emit FAIL "syntax.$script" invalid; fi
done
for profile in generic web node python audio; do
  if project_profile_parse "$TEMPLATE_ROOT/project-profiles/$profile.conf" && [ "$PROJECT_PROFILE_ID" = "$profile" ]; then emit OK "template.profile.$profile" valid; else emit FAIL "template.profile.$profile" invalid; fi
done
for file in docs/project-bootstrap.md docs/doctor.md docs/v1.6.0.md tests/test-doctor.sh .github/workflows/validate.yml; do
  [ -s "$TEMPLATE_ROOT/$file" ] && emit OK "template.$file" present || emit FAIL "template.$file" missing
done
if command -v git >/dev/null 2>&1; then
  emit OK git.command available
  if [ -z "$target" ] && git -C "$TEMPLATE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -n "$(git -C "$TEMPLATE_ROOT" status --porcelain 2>/dev/null)" ]; then emit WARN git.template working-tree-dirty; else emit OK git.template working-tree-clean; fi
  else emit SKIP git.template not-a-repository; fi
else emit WARN git.command unavailable; fi

file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || return 1
}
check_managed_file() {
  path=$1 id=$2
  if [ -L "$path" ]; then emit FAIL "$id" symbolic-link
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
    check_managed_file "$target/.ccb/context/project.md" project.context
    check_managed_file "$target/AGENTS.md" project.agents
    if project_conf_parse "$target/.ccb/project.conf"; then
    profile=$PROJECT_PROFILE
    project_version=$(awk -F= '$1=="CCB_PROJECT_VERSION" {print $2}' "$target/.ccb/project.conf")
    template_version=$(awk -F= '$1=="CCB_TEMPLATE_VERSION" {print $2}' "$target/.ccb/project.conf")
    if project_profile_parse "$TEMPLATE_ROOT/project-profiles/$profile.conf" && [ "$PROJECT_PROFILE_ID" = "$profile" ]; then emit OK project.profile "$profile"; else emit FAIL project.profile unsupported; fi
    [ "$project_version" = 1 ] && emit OK project.version 1 || emit FAIL project.version unsupported
    [ "$template_version" = "$(cat "$TEMPLATE_ROOT/VERSION")" ] && emit OK project.template_version "$template_version" || emit FAIL project.template_version incompatible
    grep -Fq "Project: $PROJECT_NAME" "$target/.ccb/context/project.md" 2>/dev/null && emit OK project.context_name present || emit WARN project.context_name missing
    grep -Fq "Profile: $profile" "$target/.ccb/context/project.md" 2>/dev/null && emit OK project.context_profile present || emit WARN project.context_profile missing
    else emit FAIL project.project_conf invalid; fi
    if project_models_parse "$target/.ccb/models.conf"; then
    emit OK project.provider "$PROJECT_MODEL_PROVIDER"
    for role in default planner coder reviewer; do model_value=$(awk -F= -v key="CCB_MODEL_$(printf '%s' "$role" | tr '[:lower:]' '[:upper:]')" '$1==key {print $2}' "$target/.ccb/models.conf"); [ -n "$model_value" ] && emit OK "project.model.$role" "$model_value" || emit FAIL "project.model.$role" missing; done
    else emit FAIL project.models_conf invalid; fi
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
      for configured in "$PROJECT_MODEL_DEFAULT" "$PROJECT_MODEL_PLANNER" "$PROJECT_MODEL_CODER" "$PROJECT_MODEL_REVIEWER"; do printf '%s\n' "$local_models" | grep -Fqx "$configured" && emit OK "ollama.model.$configured" installed || emit WARN "ollama.model.$configured" not-installed; done
    fi
  else emit SKIP ollama.models no-project; fi
fi

printf 'Summary: OK=%s WARN=%s FAIL=%s SKIP=%s\n' "$ok_count" "$warn_count" "$fail_count" "$skip_count"
[ "$fail_count" -eq 0 ] || exit 1
[ "$strict" -eq 0 ] || [ "$warn_count" -eq 0 ] || exit 1
exit 0
