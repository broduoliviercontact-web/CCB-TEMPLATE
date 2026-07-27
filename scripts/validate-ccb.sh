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
require_template_executable scripts/project-init.sh
require_template_executable scripts/project-config.sh
require_template_executable scripts/project-skills.sh
require_template_executable scripts/project-agents.sh
if [ -s "$TEMPLATE_ROOT/scripts/project-agents-lib.sh" ] && sh -n "$TEMPLATE_ROOT/scripts/project-agents-lib.sh"; then ok 'template library: scripts/project-agents-lib.sh'; else error 'invalid agents library'; fi
require_template_executable scripts/project-upgrade.sh
require_template_executable scripts/doctor.sh

for project_test in tests/test-project-init.sh tests/test-project-profiles.sh tests/test-project-models.sh tests/test-project-config.sh tests/test-project-skills.sh tests/test-skills-command.sh tests/test-project-agents.sh tests/test-project-upgrade.sh tests/test-doctor.sh; do
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

for template_file in VERSION profiles/README.md profiles/generic/profile.conf tests/test-profiles.sh tests/test-cli.sh tests/test-project-init.sh tests/test-project-profiles.sh tests/test-project-models.sh tests/test-project-config.sh tests/test-project-skills.sh tests/test-skills-command.sh tests/test-project-agents.sh tests/test-project-upgrade.sh tests/test-doctor.sh tests/test-setup-wizard.sh tests/test-models.sh docs/models.md docs/project-bootstrap.md docs/project-skills.md docs/project-agents.md docs/project-upgrade.md docs/ponytail.md docs/doctor.md docs/v1.6.0.md docs/v1.6.1.md docs/v1.7.0.md CHANGELOG.md; do
  if [ -s "$TEMPLATE_ROOT/$template_file" ]; then
    ok "template file: $template_file"
  else
    error "missing or empty template file: $template_file"
  fi
done

if [ "$(cat "$TEMPLATE_ROOT/VERSION")" = 1.7.0 ]; then ok 'template version: 1.7.0'; else error 'template VERSION must be 1.7.0'; fi

for project_profile in generic web node python audio; do
  if project_profile_parse "$TEMPLATE_ROOT/project-profiles/$project_profile.conf" && [ "$PROJECT_PROFILE_ID" = "$project_profile" ]; then
    ok "project bootstrap profile: $project_profile"
  else
    error "invalid project bootstrap profile: $project_profile"
  fi
done

for audited_script in scripts/doctor.sh scripts/project-init.sh scripts/project-upgrade.sh scripts/project-config.sh scripts/project-config-lib.sh scripts/project-profile-lib.sh; do
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
