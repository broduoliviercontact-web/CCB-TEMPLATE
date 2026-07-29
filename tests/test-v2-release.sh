#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "missing $2 in $1"; }

[ -f "$ROOT/VERSION" ] || fail 'VERSION is missing'
version=$(sed -n '1p' "$ROOT/VERSION")
[ "$(sed -n '$=' "$ROOT/VERSION")" = 1 ] || fail 'VERSION must contain exactly one line'
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail 'VERSION is not MAJOR.MINOR.PATCH'
[ "$version" = 2.0.0 ] || fail "VERSION is not 2.0.0: $version"
[ "$("$ROOT/install.sh" --version)" = 'CCB-TEMPLATE 2.0.0' ] || fail 'install.sh --version is inconsistent'

require "$ROOT/README.md" 'CCB-TEMPLATE 2.0.0'
require "$ROOT/README.md" 'official CCB 8.4.3 or later'
require "$ROOT/README.md" 'only preset supported by'
require "$ROOT/README.md" 'v1.8.0'
require "$ROOT/CHANGELOG.md" '## 2.0.0 — 2026-07-28'
require "$ROOT/CHANGELOG.md" '## Unreleased'
require "$ROOT/CHANGELOG.md" '--token-optimization'
for section in '### Breaking changes' '### Added' '### Removed' '### Migration'; do
  require "$ROOT/CHANGELOG.md" "$section"
done

for document in "$ROOT/README.md" "$ROOT"/docs/v2-*.md; do
  if grep -Eiq 'in progress|future release|migration branch' "$document"; then
    fail "release documentation is unfinished: $(basename "$document")"
  fi
done

if rg -n '^\s*(\./ccb|scripts/ccb\.sh)(\s|$)' "$ROOT/README.md" "$ROOT/docs/v2-"*.md; then
  fail 'active documentation recommends the removed V1 command'
fi
if grep -RIn 'OpenCode' "$ROOT/README.md" "$ROOT"/docs/v2-*.md | grep -Eiv 'does not use OpenCode|OpenCode is not used'; then
  fail 'active documentation recommends OpenCode'
fi

retired_prefix=qwen3-coder
retired_model=$retired_prefix:480b-cloud
if rg -n "$retired_model" "$ROOT/install.sh" "$ROOT/README.md" "$ROOT/CHANGELOG.md" \
  "$ROOT/scripts/v2" "$ROOT/assets" "$ROOT/docs/v2-"*.md; then
  fail 'retired model appears in an active file'
fi
if rg -n 'sk-ant-|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|Bearer [A-Za-z0-9]' \
  "$ROOT/install.sh" "$ROOT/README.md" "$ROOT/CHANGELOG.md" "$ROOT/.github" \
  "$ROOT/scripts/v2" "$ROOT/assets" "$ROOT/docs/v2-"*.md; then
  fail 'secret-like value appears in an active file'
fi
echo '[OK] V2 release tests passed (19 checks)'
