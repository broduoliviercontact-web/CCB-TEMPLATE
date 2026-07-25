#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
INSTALL="$TEMPLATE_ROOT/scripts/install-project.sh"
VALIDATE="$TEMPLATE_ROOT/scripts/validate-ccb.sh"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ccb-template-test.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

repo="$TEMP_ROOT/project"
empty_repo="$TEMP_ROOT/without-head"
mkdir -p "$repo" "$empty_repo"
git init -q "$repo"
git -C "$repo" config user.name "CCB Template Test"
git -C "$repo" config user.email "ccb-template-test@example.invalid"
printf 'fixture\n' >"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -qm "test: initial fixture"

"$INSTALL" "$repo"

for path in \
  .ccb \
  .ccb/AGENT_POLICY.md \
  .ccb/ccb_memory.md \
  .ccb/agents/manager/memory.md \
  .ccb/agents/graph/memory.md \
  .ccb/agents/graphiste/memory.md \
  .ccb/agents/reviewer/memory.md \
  graphify-out \
  graphiste-out; do
  test -e "$repo/$path" || { echo "missing after install: $path" >&2; exit 1; }
done

grep -Fq 'graphiste' "$repo/.ccb/AGENT_POLICY.md"
grep -Fqx 'graphiste-out/' "$repo/.gitignore"
"$VALIDATE" "$repo"

printf '# local manager convention\n' >"$repo/.ccb/agents/manager/memory.md"
"$INSTALL" "$repo" >/dev/null
grep -Fqx '# local manager convention' "$repo/.ccb/agents/manager/memory.md"

printf '# local policy before update\n' >"$repo/.ccb/AGENT_POLICY.md"
"$INSTALL" "$repo" --update
grep -Fq 'CCB Agent Policy' "$repo/.ccb/AGENT_POLICY.md"
find "$repo/.ccb/backups" -type f -name 'AGENT_POLICY.md.*.bak' | grep -q .
grep -Fqx '# local manager convention' "$repo/.ccb/agents/manager/memory.md"

git init -q "$empty_repo"
if "$INSTALL" "$empty_repo" >/dev/null 2>&1; then
  echo "installer unexpectedly accepted repository without HEAD" >&2
  exit 1
fi

echo "[OK] installation integration tests passed"
