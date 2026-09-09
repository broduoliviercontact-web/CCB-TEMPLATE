#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "missing $2 in $1"; }
reject() { if grep -Fq -- "$2" "$1"; then fail "unexpected $2 in $1"; fi; }

role=$ROOT/assets/agents/reviewer/CLAUDE.md
skill=$ROOT/assets/skills/ccb-reviewer-audit/SKILL.md
memory=$ROOT/assets/agents/reviewer/memory.md
dev=$ROOT/assets/skills/ccb-developer-delivery/SKILL.md
doc=$ROOT/docs/v2-reviewer-diff-first.md

for f in "$role" "$skill" "$memory" "$dev" "$doc"; do
  [ -f "$f" ] || fail "missing $f"
done

# Concept checks (presence, not exact phrasing).
# 1. Diff-first discipline is stated somewhere in role, skill and memory.
for f in "$role" "$skill" "$memory"; do
  if ! grep -Fqi 'diff-first' "$f"; then fail "diff-first missing in $f"; fi
done

# 2. Reviewer workflow covers the five steps conceptually.
for step in 'Scope' 'Diff' 'Validation' 'Targeted expansion' 'Findings'; do
  if ! grep -Fq -- "$step" "$skill"; then fail "missing step $step in skill"; fi
done
require "$doc" 'Scope -> Diff -> Validation -> Targeted expansion -> Findings'

# 3. The skill rejects automatic exploration and global reruns (any wording).
flat=$(tr '\n' ' ' < "$skill")
printf '%s\n' "$flat" | grep -Eqi 'to be sure'   || fail 'skill does not reject "to be sure" exploration'
printf '%s\n' "$flat" | grep -Eqi 'rerun'  || fail 'skill does not reject rerunning large suites'
printf '%s\n' "$flat" | grep -Eqi 'enough evidence' || fail 'skill missing stop-on-evidence discipline'

# 4. The skill forbids Graph auto-invocation.
require "$skill" 'call Graph automatically'
require "$skill" 'calling Graph from here'

# 5. Findings format: severities and required content.
require "$skill" 'BLOCKER'
require "$skill" 'HIGH'
require "$skill" 'MEDIUM'
require "$skill" 'LOW'
require "$skill" 'severity'
require "$skill" 'file'
require "$skill" 'line'
require "$skill" 'consequence'
require "$skill" 'expected fix'

# 6. Reviewer input contract is documented (REVIEW INPUT block).
require "$skill" 'REVIEW INPUT'
require "$skill" 'Acceptance criteria'
require "$skill" 'Changed files'
require "$skill" 'Diff'
require "$skill" 'Validation'
require "$skill" 'Developer notes'

# 7. Developer delivery contract: writes the DELIVERY DELTA. The brief output
#    stays short and never includes the full diff.
flat_dev=$(tr '\n' ' ' < "$dev")
printf '%s\n' "$flat_dev" | grep -Eqi 'DELIVERY DELTA' || fail 'dev skill no longer mentions DELIVERY DELTA'
printf '%s\n' "$flat_dev" | grep -Fq 'Never include the full diff' \
  || fail 'dev skill must forbid including the full diff in the handoff'

# 8. Complexity Router behaviour is preserved: SIMPLE still skips reviewer.
proj=$(mktemp -d /tmp/ccb-reviewer-XXXXXX)
mkdir -p "$proj/.ccb/briefs"
printf '# Brief\nfix typo\n' >"$proj/.ccb/briefs/brief.md"
simple_prompt=$("$ROOT/ccb-template" manager-prompt "$proj" brief.md --complexity simple)
printf '%s\n' "$simple_prompt" | grep -Fq '## Routing level: SIMPLE' \
  || fail 'SIMPLE block is missing'
printf '%s\n' "$simple_prompt" | grep -Fq 'Reviewer is NOT mandatory' \
  || fail 'SIMPLE block must keep skipping reviewer by default'
printf '%s\n' "$simple_prompt" | grep -Fq 'Request independent validation from reviewer' \
  && fail 'SIMPLE block must not require reviewer'
rm -rf "$proj"

# 9. Read-only invariant is still stated.
printf '%s\n' "$(cat "$role")" | grep -Fqi 'read-only' || fail 'role brief no longer states read-only'
printf '%s\n' "$(cat "$skill")" | grep -Fqi 'read-only' || fail 'skill no longer states read-only'

# 10. AGENT_POLICY keeps its complexity-router wording (no regression).
policy=$ROOT/assets/AGENT_POLICY.md
require "$policy" 'depend on the selected complexity level'
require "$policy" 'ESCALATE: SIMPLE -> NORMAL'

# 11. Runtime size guard.
# The whole runtime context for the reviewer is the union of:
#   - AGENT_POLICY.md (shared)
#   - ccb_memory.md (shared)
#   - reviewer/CLAUDE.md
#   - reviewer/memory.md
#   - ccb-reviewer-audit/SKILL.md
# We guard the role-specific files (CLAUDE.md + memory.md + SKILL.md) to
# catch regressions of the form "reviewer runtime triples in size".
reviewer_chars=$(cat "$role" "$memory" "$skill" | wc -c | awk '{ print $1 }')
# Threshold: roughly 6 KiB of total reviewer runtime; large enough to allow
# honest growth, small enough to catch a 4x regression early.
max_chars=6000
if [ "$reviewer_chars" -gt "$max_chars" ]; then
  fail "reviewer runtime is $reviewer_chars bytes (> $max_chars); reviewer files may have bloated"
fi

echo '[OK] V2 reviewer diff-first tests passed'