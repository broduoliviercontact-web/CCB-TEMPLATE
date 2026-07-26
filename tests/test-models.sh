#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/scripts/ccb.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ccb-models.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
repo="$TMP/project with spaces"; mkdir -p "$repo/.ccb"
for preset in "$ROOT"/model-presets/*; do test -s "$preset/PRESET.md"; test -s "$preset/preset.conf"; done
"$CLI" models presets | grep -Fq balanced-cloud
"$CLI" models preset show balanced-cloud | grep -Fq 'Manager:'
"$CLI" models setup "$repo" --preset balanced-cloud --dry-run | grep -Fq 'DRY RUN'
test ! -e "$repo/.ccb/models.conf"
"$CLI" models setup "$repo" --preset balanced-cloud --yes >/dev/null
test -s "$repo/.ccb/models.conf"
"$ROOT/scripts/model-resolve.sh" developer "$repo" | grep -Fxq qwen3-coder:480b-cloud
"$CLI" models setup "$repo" --single-model qwen3.5:cloud --yes >/dev/null
"$ROOT/scripts/model-resolve.sh" graph "$repo" | grep -Fxq qwen3.5:cloud
test -n "$(find "$repo/.ccb" -name 'models.conf.backup-*' -type f)"
if "$CLI" models setup "$repo" --single-model 'bad;model' --yes >/dev/null 2>&1; then exit 1; fi
echo '[OK] model integration tests passed'
