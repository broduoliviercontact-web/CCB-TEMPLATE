#!/usr/bin/env sh
set -eu

fail=0

require_path() {
  if [ ! -e "$1" ]; then
    echo "missing: $1" >&2
    fail=1
  fi
}

require_ignore() {
  if ! grep -Fqx "$1" .gitignore 2>/dev/null; then
    echo "missing .gitignore entry: $1" >&2
    fail=1
  fi
}

require_path .ccb
require_path .ccb/AGENT_POLICY.md
require_path .ccb/ccb_memory.md
require_path .ccb/agents/manager/memory.md
require_path .ccb/agents/graph/memory.md
require_path .ccb/agents/reviewer/memory.md
require_path graphify-out
require_ignore "graphify-out/"
require_ignore ".ccb/backups/"

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "CCB template validation passed."
