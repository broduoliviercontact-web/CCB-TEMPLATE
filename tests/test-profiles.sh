#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
INSTALL="$TEMPLATE_ROOT/scripts/install-project.sh"
VALIDATE="$TEMPLATE_ROOT/scripts/validate-ccb.sh"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ccb-profiles-test.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

test -s "$TEMPLATE_ROOT/profiles/generic/profile.conf"
for profile in "$TEMPLATE_ROOT"/profiles/*; do
  test -d "$profile" || continue
  test -s "$profile/profile.conf"
  test -s "$profile/PROFILE.md"
  test -s "$profile/memory/project-seed.md"
done

repo="$TEMP_ROOT/project"
mkdir -p "$repo"
git init -q "$repo"
git -C "$repo" config user.name "CCB Profile Test"
git -C "$repo" config user.email "ccb-profile-test@example.invalid"
printf 'fixture\n' >"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -qm fixture

"$INSTALL" "$repo"
test "$(cat "$repo/.ccb/active-profile")" = generic
grep -Fq '<!-- BEGIN CCB PROFILE generic -->' "$repo/.ccb/ccb_memory.md"
"$INSTALL" "$repo" --profile generic >/dev/null
test "$(grep -Fc '<!-- BEGIN CCB PROFILE generic -->' "$repo/.ccb/ccb_memory.md")" -eq 1

printf '# local convention\n' >>"$repo/.ccb/agents/manager/memory.md"
"$INSTALL" --profile react-web "$repo" --update
test "$(cat "$repo/.ccb/active-profile")" = react-web
test -s "$repo/.ccb/profiles/react-web/skills/react-project-audit/SKILL.md"
grep -Fq '<!-- BEGIN CCB PROFILE react-web -->' "$repo/.ccb/ccb_memory.md"
grep -Fq '# local convention' "$repo/.ccb/agents/manager/memory.md"
"$VALIDATE" "$repo" >/dev/null

if "$INSTALL" "$repo" --profile ../unsafe >/dev/null 2>&1; then
  echo "unsafe profile id was accepted" >&2
  exit 1
fi
if "$INSTALL" "$repo" --profile unknown >/dev/null 2>&1; then
  echo "unknown profile was accepted" >&2
  exit 1
fi

echo "[OK] profile integration tests passed"
