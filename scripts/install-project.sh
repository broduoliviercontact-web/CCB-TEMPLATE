#!/usr/bin/env sh
set -eu

usage() {
  echo "usage: $0 [target-directory] [--update]" >&2
  exit 2
}

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
TARGET=
UPDATE=0

for argument in "$@"; do
  case "$argument" in
    --update) UPDATE=1 ;;
    -*) usage ;;
    *)
      if [ -n "$TARGET" ]; then
        usage
      fi
      TARGET=$argument
      ;;
  esac
done

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
write_gitignore_block

echo "CCB project installation completed: $TARGET"
