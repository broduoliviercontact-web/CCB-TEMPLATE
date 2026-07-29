#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "missing $2 in $1"; }

require "$ROOT/README.md" 'SeemSeam/claude_codex_bridge'
require "$ROOT/README.md" './install.sh /chemin/du/projet'
require "$ROOT/README.md" 'repository-local `./ccb` command has been removed'
require "$ROOT/README.md" 'official globally installed CCB binary'
require "$ROOT/README.md" 'V1.8.0 archive'
require "$ROOT/README.md" 'does not use OpenCode'
require "$ROOT/README.md" '--token-optimization'
require "$ROOT/README.md" 'rtk init -g'
require "$ROOT/README.md" 'tilth@0.9.0'

for document in docs/v2-quickstart.md docs/v2-architecture.md docs/v2-migration-from-v1.md docs/v2-troubleshooting.md; do
  [ -f "$ROOT/$document" ] || fail "missing $document"
  if grep -F -- '--break-system-packages' "$ROOT/$document" | grep -Eiv 'do not use.*--break-system-packages|--break-system-packages.*do not use' >/dev/null; then fail "$document recommends --break-system-packages"; fi
  if grep -Fq 'qwen3-coder:480b-cloud' "$ROOT/$document"; then fail "$document mentions retired model"; fi
done

for model in glm-5.2:cloud qwen3.5:397b-cloud kimi-k2.7-code:cloud kimi-k2.6:cloud; do
  require "$ROOT/docs/v2-architecture.md" "$model"
done

require "$ROOT/.github/workflows/validate.yml" './tests/test-v2-install.sh'
require "$ROOT/.github/workflows/validate.yml" './tests/test-v2-docs.sh'
require "$ROOT/.github/workflows/validate.yml" './tests/test-v2-clean-tree.sh'
require "$ROOT/.github/workflows/validate.yml" 'token-optimization tests'
require "$ROOT/README.md" 'V1 profiles, skills, prompts and manuals were removed'
require "$ROOT/README.md" 'standard built-in asset preset'
require "$ROOT/docs/v2-quickstart.md" 'standard built-in asset preset'

if rg -n '^\s*ccb\s*$|\$\s*ccb\s*$' "$ROOT/tests/test-v2-install.sh" "$ROOT/tests/test-v2-docs.sh" >/dev/null; then
  fail 'a V2 test launches ccb without a subcommand'
fi
require "$ROOT/docs/v2-architecture.md" 'does not call Ollama directly'
require "$ROOT/docs/v2-architecture.md" 'not a workflow engine'
require "$ROOT/docs/v2-architecture.md" 'project/workspace MCP metadata'
require "$ROOT/docs/v2-quickstart.md" 'npx tilth --version'
require "$ROOT/docs/v2-troubleshooting.md" 'MCP configuration'

echo '[OK] V2 documentation tests passed (25 checks)'
