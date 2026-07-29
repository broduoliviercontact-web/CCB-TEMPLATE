#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
require_file() { [ -f "$ROOT/$1" ] || fail "missing required file: $1"; }
require_absent() { [ ! -e "$ROOT/$1" ] || fail "legacy or generated path exists: $1"; }

for path in \
  ccb scripts/ccb.sh scripts/provider-router.sh scripts/agent-launcher.sh \
  scripts/runtime scripts/project-workflows.sh scripts/project-runs.sh \
  model-presets project-profiles .ccb/runs graphify-out graphiste-out assets/agents/graphiste \
  agent-runtime profiles skills examples; do
  require_absent "$path"
done

for path in \
  install.sh ccb-template VERSION LICENSE README.md \
  scripts/v2/common.sh scripts/v2/preflight.sh scripts/v2/render-config.sh scripts/v2/install-assets.sh \
  assets/AGENT_POLICY.md assets/CLAUDE.md assets/ccb_memory.md assets/token-optimization.md assets/token-proxy.py assets/token-pricing.json \
  assets/agents/manager/memory.md assets/agents/graph/memory.md \
  assets/agents/developer/memory.md \
  assets/agents/reviewer/memory.md \
  assets/agents/manager/CLAUDE.md assets/agents/graph/CLAUDE.md \
  assets/agents/developer/CLAUDE.md assets/agents/reviewer/CLAUDE.md \
  assets/skills/ccb-manager-planning/SKILL.md assets/skills/ccb-graph-analysis/SKILL.md \
  assets/skills/ccb-developer-delivery/SKILL.md assets/skills/ccb-reviewer-audit/SKILL.md \
  docs/v2-architecture.md docs/v2-migration-from-v1.md docs/v2-migration-plan.md \
  docs/v2-quickstart.md docs/v2-troubleshooting.md docs/v2-codex-workflow.md \
  tests/fixtures/ccb.config.expected tests/test-v2-install.sh tests/test-v2-docs.sh; do
  require_file "$path"
done

retired_prefix=qwen3-coder
retired_model=$retired_prefix:480b-cloud
if rg -n --glob '!tests/test-v2-docs.sh' "$retired_model" \
  "$ROOT/install.sh" "$ROOT/README.md" "$ROOT/scripts/v2" "$ROOT/assets" "$ROOT/docs/v2-"*.md; then
  fail 'retired model is present in V2 code or documentation'
fi

if rg -n 'sk-ant-|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|Bearer [A-Za-z0-9]' \
  "$ROOT/install.sh" "$ROOT/README.md" "$ROOT/.github" "$ROOT/scripts/v2" "$ROOT/assets" \
  "$ROOT/docs/v2-architecture.md" "$ROOT/docs/v2-migration-from-v1.md" \
  "$ROOT/docs/v2-migration-plan.md" "$ROOT/docs/v2-quickstart.md" \
  "$ROOT/docs/v2-troubleshooting.md" "$ROOT/tests/fixtures"; then
  fail 'secret-like value found in the V2 tree'
fi

if git -C "$ROOT" ls-files -s | awk '$1 == "120000" { found = 1 } END { exit found ? 0 : 1 }'; then
  fail 'a tracked symbolic link remains'
fi

for sourced in scripts/v2/common.sh scripts/v2/preflight.sh scripts/v2/render-config.sh scripts/v2/install-assets.sh; do
  [ -f "$ROOT/$sourced" ] || fail "install.sh sources a missing file: $sourced"
done

if rg -n 'scripts/ccb\.sh|provider-router|agent-launcher|project-workflows|project-runs|model-presets|project-profiles' \
  "$ROOT/install.sh" "$ROOT/scripts/v2" "$ROOT/README.md" "$ROOT/docs/v2-"*.md; then
  fail 'active V1 command reference found'
fi

for document in "$ROOT"/docs/*; do
  case "$(basename "$document")" in
    v2-architecture.md|v2-codex-workflow.md|v2-migration-from-v1.md|v2-migration-plan.md|v2-quickstart.md|v2-troubleshooting.md) : ;;
    *) fail "non-V2 documentation remains: $(basename "$document")" ;;
  esac
done

echo '[OK] V2 clean-tree tests passed (13 checks)'
