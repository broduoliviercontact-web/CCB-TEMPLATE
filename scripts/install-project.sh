#!/usr/bin/env sh
set -eu

usage() {
  cat <<EOF >&2
usage: $0 [target-directory] [--profile ID] [--update]
       $0 --list-profiles
EOF
  exit "${1:-2}"
}

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
TARGET=
UPDATE=0
PROFILE_ID=generic
LIST_PROFILES=0

. "$SCRIPT_DIR/profile-lib.sh"

list_profiles() {
  for profile_dir in "$TEMPLATE_ROOT"/profiles/*; do
    [ -d "$profile_dir" ] || continue
    profile_name=$(basename "$profile_dir")
    profile_id_is_safe "$profile_name" || continue
    if profile_parse "$profile_dir/profile.conf"; then
      printf '%s\t%s\n' "$PROFILE_ID" "$PROFILE_NAME"
    fi
  done
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --update) UPDATE=1 ;;
    --profile)
      shift
      [ "$#" -gt 0 ] || usage
      PROFILE_ID=$1
      ;;
    --list-profiles) LIST_PROFILES=1 ;;
    --help|-h) usage 0 ;;
    -*) usage ;;
    *)
      if [ -n "$TARGET" ]; then
        usage
      fi
      TARGET=$1
      ;;
  esac
  shift
done

if [ "$LIST_PROFILES" -eq 1 ]; then
  [ -z "$TARGET" ] || usage
  list_profiles
  exit 0
fi

profile_id_is_safe "$PROFILE_ID" || { echo "error: invalid profile id: $PROFILE_ID" >&2; exit 2; }
PROFILE_DIR="$TEMPLATE_ROOT/profiles/$PROFILE_ID"
if [ -L "$PROFILE_DIR" ] || [ -L "$PROFILE_DIR/profile.conf" ]; then
  echo "error: profile directories and configuration files must not be symlinks" >&2
  exit 1
fi
if ! profile_parse "$PROFILE_DIR/profile.conf"; then
  echo "error: invalid or missing profile '$PROFILE_ID': ${PROFILE_PARSE_ERROR:-unknown error}" >&2
  exit 1
fi
if [ "$PROFILE_ID" != "$(basename "$PROFILE_DIR")" ]; then
  echo "error: profile id does not match its directory" >&2
  exit 1
fi
PROFILE_SEED="$PROFILE_DIR/$PROFILE_MEMORY_SEED"
[ -s "$PROFILE_SEED" ] && [ ! -L "$PROFILE_SEED" ] || { echo "error: missing or unsafe profile memory seed: $PROFILE_MEMORY_SEED" >&2; exit 1; }

if [ -z "$TARGET" ]; then
  TARGET=$(pwd)
fi

if [ ! -d "$TARGET" ]; then
  echo "error: target directory does not exist: $TARGET" >&2
  exit 1
fi

TARGET=$(CDPATH= cd "$TARGET" && pwd)

if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: target is not a Git repository: $TARGET" >&2
  exit 1
fi

if ! git -C "$TARGET" rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "error: target needs an initial Git commit before CCB can create developer worktrees" >&2
  exit 1
fi

copy_missing() {
  source=$1
  destination=$2
  if [ -e "$destination" ]; then
    echo "preserved: $destination"
    return
  fi
  mkdir -p "$(dirname "$destination")"
  cp "$source" "$destination"
  echo "installed: $destination"
}

update_policy() {
  source=$1
  destination=$2
  backup_dir="$TARGET/.ccb/backups"
  if [ ! -e "$destination" ]; then
    copy_missing "$source" "$destination"
    return
  fi
  mkdir -p "$backup_dir"
  timestamp=$(date +%Y%m%d%H%M%S)
  backup="$backup_dir/$(basename "$destination").$timestamp.bak"
  cp "$destination" "$backup"
  cp "$source" "$destination"
  echo "backed up: $backup"
  echo "updated: $destination"
}

copy_profile_skill() {
  skill_name=$1
  source="$PROFILE_DIR/skills/$skill_name"
  destination="$TARGET/.ccb/profiles/$PROFILE_ID/skills/$skill_name"
  profile_id_is_safe "$skill_name" || { echo "error: unsafe profile skill: $skill_name" >&2; exit 1; }
  [ -d "$source" ] && [ ! -L "$source" ] || { echo "error: missing or unsafe profile skill: $skill_name" >&2; exit 1; }
  if find "$source" -type l -print | grep -q .; then
    echo "error: profile skill contains a symlink: $skill_name" >&2
    exit 1
  fi
  [ ! -L "$destination" ] || { echo "error: target profile skill is a symlink: $skill_name" >&2; exit 1; }
  if [ -e "$destination" ]; then
    echo "preserved: $destination"
  else
    mkdir -p "$(dirname "$destination")"
    cp -R "$source" "$destination"
    echo "installed: $destination"
  fi
}

install_profile_memory() {
  memory="$TARGET/.ccb/ccb_memory.md"
  temporary=$(mktemp "${TMPDIR:-/tmp}/ccb-profile-memory.XXXXXX")
  trap 'rm -f "$temporary"' EXIT HUP INT TERM
  awk '
    $0 ~ /^<!--[[:space:]]BEGIN CCB PROFILE [a-z0-9-][a-z0-9-]* -->$/ { inside = 1; next }
    $0 ~ /^<!--[[:space:]]END CCB PROFILE [a-z0-9-][a-z0-9-]* -->$/ { inside = 0; next }
    !inside { print }
  ' "$memory" >"$temporary"
  if [ -s "$temporary" ]; then printf '\n' >>"$temporary"; fi
  printf '<!-- BEGIN CCB PROFILE %s -->\n' "$PROFILE_ID" >>"$temporary"
  cat "$PROFILE_SEED" >>"$temporary"
  printf '\n<!-- END CCB PROFILE %s -->\n' "$PROFILE_ID" >>"$temporary"
  mv "$temporary" "$memory"
  trap - EXIT HUP INT TERM
  echo "updated: $memory (active profile memory)"
}

install_profile() {
  profile_target="$TARGET/.ccb/profiles/$PROFILE_ID"
  for guarded_path in "$TARGET/.ccb" "$TARGET/.ccb/profiles" "$TARGET/.ccb/active-profile" "$profile_target"; do
    [ ! -L "$guarded_path" ] || { echo "error: refusing target symlink: $guarded_path" >&2; exit 1; }
  done
  old_profile=
  if [ -f "$TARGET/.ccb/active-profile" ]; then old_profile=$(cat "$TARGET/.ccb/active-profile"); fi
  if [ "$UPDATE" -eq 1 ] && [ -n "$old_profile" ] && [ "$old_profile" != "$PROFILE_ID" ]; then
    mkdir -p "$TARGET/.ccb/backups"
    cp "$TARGET/.ccb/active-profile" "$TARGET/.ccb/backups/active-profile.$(date +%Y%m%d%H%M%S).bak"
    echo "backed up: active profile $old_profile"
  fi
  mkdir -p "$profile_target/skills"
  copy_missing "$PROFILE_DIR/PROFILE.md" "$profile_target/PROFILE.md"
  old_ifs=$IFS; IFS=,
  for skill_name in $PROFILE_SKILLS; do [ -n "$skill_name" ] && copy_profile_skill "$skill_name"; done
  IFS=$old_ifs
  printf '%s\n' "$PROFILE_ID" >"$TARGET/.ccb/active-profile"
  echo "updated: $TARGET/.ccb/active-profile"
  install_profile_memory
}

write_gitignore_block() {
  gitignore="$TARGET/.gitignore"
  block_file=$(mktemp "${TMPDIR:-/tmp}/ccb-template-block.XXXXXX")
  output_file=$(mktemp "${TMPDIR:-/tmp}/ccb-template-ignore.XXXXXX")
  trap 'rm -f "$block_file" "$output_file"' EXIT HUP INT TERM

  cat >"$block_file" <<'BLOCK'
# BEGIN CCB TEMPLATE
# CCB runtime and recoverable state
.ccb/backups/
.ccb/ccbd/
.ccb/workspaces/
.ccb/.claude-*-session
.ccb/*.log
.ccb/*.pid
.ccb/agents/*/cancel_flags/
.ccb/agents/*/jobs.jsonl
.ccb/agents/*/logs/
.ccb/agents/*/sessions/
.ccb/agents/*/provider-state/
.ccb/agents/*/restore.json
.ccb/agents/*/history/
.ccb/agents/*/histories/
.ccb/agents/*/history.json
.ccb/agents/*/history.jsonl

graphify-out/
!graphify-out/
graphify-out/*
!graphify-out/.gitkeep

graphiste-out/
!graphiste-out/
graphiste-out/*
!graphiste-out/.gitkeep
# END CCB TEMPLATE
BLOCK

  touch "$gitignore"
  begins=$(grep -Fxc '# BEGIN CCB TEMPLATE' "$gitignore" || true)
  ends=$(grep -Fxc '# END CCB TEMPLATE' "$gitignore" || true)
  if [ "$begins" -eq 0 ] && [ "$ends" -eq 0 ]; then
    cat "$gitignore" >"$output_file"
    if [ -s "$output_file" ]; then
      printf '\n' >>"$output_file"
    fi
    cat "$block_file" >>"$output_file"
  elif [ "$begins" -eq 1 ] && [ "$ends" -eq 1 ]; then
    awk -v block="$block_file" '
      $0 == "# BEGIN CCB TEMPLATE" {
        while ((getline line < block) > 0) print line
        close(block)
        inside = 1
        next
      }
      $0 == "# END CCB TEMPLATE" {
        inside = 0
        next
      }
      !inside { print }
    ' "$gitignore" >"$output_file"
  else
    echo "error: malformed CCB TEMPLATE block in $gitignore" >&2
    exit 1
  fi
  mv "$output_file" "$gitignore"
  trap - EXIT HUP INT TERM
  rm -f "$block_file"
  echo "updated: $gitignore (managed CCB TEMPLATE block)"
}

mkdir -p \
  "$TARGET/.ccb/agents/manager" \
  "$TARGET/.ccb/agents/graph" \
  "$TARGET/.ccb/agents/graphiste" \
  "$TARGET/.ccb/agents/reviewer" \
  "$TARGET/graphify-out" \
  "$TARGET/graphiste-out"

if [ "$UPDATE" -eq 1 ]; then
  update_policy "$TEMPLATE_ROOT/.ccb/AGENT_POLICY.md" "$TARGET/.ccb/AGENT_POLICY.md"
else
  copy_missing "$TEMPLATE_ROOT/.ccb/AGENT_POLICY.md" "$TARGET/.ccb/AGENT_POLICY.md"
fi

copy_missing "$TEMPLATE_ROOT/.ccb/ccb_memory.md" "$TARGET/.ccb/ccb_memory.md"
copy_missing "$TEMPLATE_ROOT/.ccb/agents/manager/memory.md" "$TARGET/.ccb/agents/manager/memory.md"
copy_missing "$TEMPLATE_ROOT/.ccb/agents/graph/memory.md" "$TARGET/.ccb/agents/graph/memory.md"
copy_missing "$TEMPLATE_ROOT/.ccb/agents/graphiste/memory.md" "$TARGET/.ccb/agents/graphiste/memory.md"
copy_missing "$TEMPLATE_ROOT/.ccb/agents/reviewer/memory.md" "$TARGET/.ccb/agents/reviewer/memory.md"
install_profile
write_gitignore_block

echo "CCB project installation completed: $TARGET"
