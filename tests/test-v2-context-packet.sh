#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-v2-packet.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { printf '%s\n' "$1" | grep -Fq -- "$2" || fail "missing: $2"; }
assert_not_contains() { printf '%s\n' "$1" | grep -Fq -- "$2" && fail "unexpected: $2" || return 0; }

# Module is shell-valid and present in the clean tree.
sh -n "$ROOT/scripts/v2/context-packet.sh" || fail 'context-packet.sh has syntax errors'
[ -f "$ROOT/scripts/v2/context-packet.sh" ] || fail 'context-packet.sh missing'

# Realistic fixture: a project with a brief, an init git repo and a couple of
# changes the developer would commit.
PROJ=$WORK/proj
BRIEF_ID=2026-09-09-fix-login
mkdir -p "$PROJ/.ccb/briefs" "$PROJ/src/login" "$PROJ/tests"
cat >"$PROJ/.ccb/briefs/$BRIEF_ID.md" <<'BRIEF'
# Brief
Fix the login email preservation across the password reset redirect.

The login form clears the email field after a successful password reset
and the user has to retype it. We want the email to be preserved across
the redirect so the next attempt is one click away.
BRIEF
git -C "$PROJ" init -q
git -C "$PROJ" config user.email 'ci@example.com'
git -C "$PROJ" config user.name 'CI'
printf 'old' >"$PROJ/src/login/form.tsx"
printf 'old' >"$PROJ/tests/login.test.tsx"
git -C "$PROJ" add -A && git -C "$PROJ" commit -q -m 'baseline'
printf 'new' >"$PROJ/src/login/form.tsx"
printf 'new' >"$PROJ/tests/login.test.tsx"

# 1. task create writes task.md with derived id and the chosen complexity.
"$ROOT/ccb-template" task create "$PROJ" "$BRIEF_ID.md" --complexity normal --id "$BRIEF_ID" \
  >/dev/null
TASK_FILE=$PROJ/.ccb/tasks/$BRIEF_ID/task.md
[ -f "$TASK_FILE" ] || fail 'task.md was not created'
assert_contains "$(cat "$TASK_FILE")" 'TASK PACKET'
assert_contains "$(cat "$TASK_FILE")" "Task id: $BRIEF_ID"
assert_contains "$(cat "$TASK_FILE")" 'Complexity: normal'

# 2. task.md must not contain the diff or test logs.
assert_not_contains "$(cat "$TASK_FILE")" 'diff --git'
assert_not_contains "$(cat "$TASK_FILE")" 'PASSED'
assert_not_contains "$(cat "$TASK_FILE")" 'FAILED'

# 3. Path traversal and symlink rejection.
if "$ROOT/ccb-template" task create "$PROJ" "$BRIEF_ID.md" --id '../escape' >/dev/null 2>&1; then
  fail 'task create must reject traversal ids'
fi
[ ! -e "$PROJ/.ccb/tasks/../escape" ] || fail 'traversal id created something outside .ccb/tasks'

# 4. Re-running create on an existing task must fail.
if "$ROOT/ccb-template" task create "$PROJ" "$BRIEF_ID.md" --id "$BRIEF_ID" >/dev/null 2>&1; then
  fail 'task create should refuse to overwrite an existing task.md'
fi

# 5. task delivery writes DELIVERY DELTA. When omitted, --changed is derived
#    from git diff --name-only HEAD.
"$ROOT/ccb-template" task delivery "$PROJ" "$BRIEF_ID" \
  --validation "npm test -- login.test.tsx -> PASS" \
  --summary "Email is now read from the draft store after reset." \
  --notes "none" >/dev/null
DELIVERY=$PROJ/.ccb/tasks/$BRIEF_ID/delivery.md
[ -f "$DELIVERY" ] || fail 'delivery.md was not created'
assert_contains "$(cat "$DELIVERY")" 'DELIVERY DELTA'
assert_contains "$(cat "$DELIVERY")" 'src/login/form.tsx'
assert_contains "$(cat "$DELIVERY")" 'tests/login.test.tsx'
assert_contains "$(cat "$DELIVERY")" 'npm test -- login.test.tsx -> PASS'
# Delivery must not include the full diff.
assert_not_contains "$(cat "$DELIVERY")" 'diff --git'
# Delivery must not include the conversation history.
assert_not_contains "$(cat "$DELIVERY")" 'as discussed'
assert_not_contains "$(cat "$DELIVERY")" 'earlier in this chat'

# 6. Size guard: TASK PACKET and DELIVERY DELTA stay compact.
task_chars=$(wc -c < "$TASK_FILE" | awk '{ print $1 }')
delivery_chars=$(wc -c < "$DELIVERY" | awk '{ print $1 }')
# Generous thresholds so honest growth isn't blocked, but enough to catch a
# regression where someone pastes a 5 KiB brief or a full diff into the packet.
max_task=2500
max_delivery=1500
[ "$task_chars" -le "$max_task" ] || fail "task.md is $task_chars chars (> $max_task)"
[ "$delivery_chars" -le "$max_delivery" ] || fail "delivery.md is $delivery_chars chars (> $max_delivery)"

# 7. Reviewer input contains TASK PACKET + DELIVERY DELTA and a diff pointer,
#    without dumping the conversation history.
review_input=$("$ROOT/ccb-template" task review-input "$PROJ" "$BRIEF_ID")
assert_contains "$review_input" 'REVIEW INPUT'
assert_contains "$review_input" 'TASK PACKET'
assert_contains "$review_input" 'DELIVERY DELTA'
assert_contains "$review_input" 'git'
# Review input must NOT contain arbitrary chat markers.
assert_not_contains "$review_input" 'as discussed'
assert_not_contains "$review_input" 'earlier in this chat'

# 8. task review-input fails when the delivery is missing.
rm -rf "$PROJ/.ccb/tasks/$BRIEF_ID/delivery.md"
if "$ROOT/ccb-template" task review-input "$PROJ" "$BRIEF_ID" >/dev/null 2>&1; then
  fail 'task review-input should fail when delivery.md is missing'
fi

# 9. SIMPLE path: no reviewer, very light packet.
SIMPLE_PROJ=$WORK/simple
mkdir -p "$SIMPLE_PROJ/.ccb/briefs"
cat >"$SIMPLE_PROJ/.ccb/briefs/simple.md" <<'BRIEF'
# Brief
Fix typo in README header.
BRIEF
"$ROOT/ccb-template" task create "$SIMPLE_PROJ" simple.md --complexity simple >/dev/null
simple_prompt=$("$ROOT/ccb-template" manager-prompt "$SIMPLE_PROJ" simple.md --complexity simple)
printf '%s\n' "$simple_prompt" | grep -Fq 'Reviewer is NOT mandatory' \
  || fail 'SIMPLE must keep skipping reviewer'
printf '%s\n' "$simple_prompt" | grep -Fq 'Request independent validation from reviewer' \
  && fail 'SIMPLE must not require reviewer'

# 10. doc exists.
[ -f "$ROOT/docs/v2-context-packet.md" ] || fail 'docs/v2-context-packet.md is missing'

# 11. policy + skills mention the packet.
policy=$(cat "$ROOT/assets/AGENT_POLICY.md")
assert_contains "$policy" 'Context Packet'
assert_contains "$policy" '.ccb/tasks/'
dev_skill=$(cat "$ROOT/assets/skills/ccb-developer-delivery/SKILL.md")
assert_contains "$dev_skill" 'task delivery'
rev_skill=$(cat "$ROOT/assets/skills/ccb-reviewer-audit/SKILL.md")
assert_contains "$rev_skill" 'review-input'
mgr_skill=$(cat "$ROOT/assets/skills/ccb-manager-planning/SKILL.md")
assert_contains "$mgr_skill" 'task create'

# 12. Structured brief extraction is deterministic.
SP=$WORK/structured
mkdir -p "$SP/.ccb/briefs"
cat >"$SP/.ccb/briefs/structured.md" <<'BRIEF'
# Goal
Fix login persistence.

# Scope
* src/login.ts
* tests/login.test.ts

# Acceptance
* preserve email
* tests pass

# Constraints
* no new dependency
BRIEF
"$ROOT/ccb-template" task create "$SP" structured.md --complexity normal --id structured >/dev/null
SP_TASK=$SP/.ccb/tasks/structured/task.md
assert_contains "$(cat "$SP_TASK")" 'TASK PACKET'
# Extracted sections appear verbatim.
assert_contains "$(cat "$SP_TASK")" 'Fix login persistence.'
assert_contains "$(cat "$SP_TASK")" 'src/login.ts'
assert_contains "$(cat "$SP_TASK")" 'preserve email'
assert_contains "$(cat "$SP_TASK")" 'no new dependency'

# 13. Sparse packet: when the brief omits Constraints/Known context, the
#     packet must not invent placeholders.
SP2=$WORK/sparse
mkdir -p "$SP2/.ccb/briefs"
cat >"$SP2/.ccb/briefs/sparse.md" <<'BRIEF'
# Goal
Fix typo.
BRIEF
"$ROOT/ccb-template" task create "$SP2" sparse.md --complexity simple --id sparse >/dev/null
SPARSE_TASK=$SP2/.ccb/tasks/sparse/task.md
assert_not_contains "$(cat "$SPARSE_TASK")" 'Constraints:'
assert_not_contains "$(cat "$SPARSE_TASK")" 'Known context:'
assert_not_contains "$(cat "$SPARSE_TASK")" '<to fill'
assert_not_contains "$(cat "$SPARSE_TASK")" 'not specified'

# 14. Legacy brief (no structured headings) still produces a usable packet.
LEG=$WORK/legacy
mkdir -p "$LEG/.ccb/briefs"
cat >"$LEG/.ccb/briefs/legacy.md" <<'BRIEF'
# Brief
Fix typo in README header.
BRIEF
"$ROOT/ccb-template" task create "$LEG" legacy.md --complexity simple --id legacy >/dev/null
LEG_TASK=$LEG/.ccb/tasks/legacy/task.md
assert_contains "$(cat "$LEG_TASK")" 'Fix typo in README header.'
assert_not_contains "$(cat "$LEG_TASK")" '<to fill'

# 15. Sparse delivery: omitted fields are NOT replaced with placeholders.
"$ROOT/ccb-template" task delivery "$LEG" legacy --validation "npm test -> PASS" >/dev/null
LEG_DEL=$LEG/.ccb/tasks/legacy/delivery.md
assert_contains "$(cat "$LEG_DEL")" 'npm test -> PASS'
assert_not_contains "$(cat "$LEG_DEL")" 'one short line summary'
assert_not_contains "$(cat "$LEG_DEL")" 'Summary:'
assert_not_contains "$(cat "$LEG_DEL")" 'Notes:'
assert_not_contains "$(cat "$LEG_DEL")" 'none'

# 16. CLI robustness: TARGET / summary / validation / notes may contain spaces.
WS=$WORK/spaces
mkdir -p "$WS/.ccb/briefs"
cat >"$WS/.ccb/briefs/fix login.md" <<'BRIEF'
# Goal
Fix login persistence.
BRIEF
WS_OUT=$("$ROOT/ccb-template" task create "$WS" "fix login.md" --complexity normal --id "fix login" 2>&1)
echo "$WS_OUT" | grep -Fq 'Task packet created' || fail "create with spaces failed: $WS_OUT"
"$ROOT/ccb-template" task delivery "$WS" "fix login" \
  --changed "src/login.ts|tests/login.test.ts" \
  --validation "npm test -- login -> PASS" \
  --summary "Summary with spaces in it." \
  --notes "Note with spaces and arrows -> here." >/dev/null
WS_DEL="$WS/.ccb/tasks/fix login/delivery.md"
assert_contains "$(cat "$WS_DEL")" 'Summary with spaces in it.'
assert_contains "$(cat "$WS_DEL")" 'Note with spaces and arrows -> here.'
assert_contains "$(cat "$WS_DEL")" 'npm test -- login -> PASS'

# 17. CLI robustness: traversal in --id and unknown flags.
if "$ROOT/ccb-template" task create "$WS" "fix login.md" --id "../escape" >/dev/null 2>&1; then
  fail 'traversal id must be rejected'
fi
if "$ROOT/ccb-template" task create "$WS" "fix login.md" --unknown >/dev/null 2>&1; then
  fail 'unknown flag must be rejected'
fi
if "$ROOT/ccb-template" task delivery "$WS" "fix login" --bogus x >/dev/null 2>&1; then
  fail 'unknown delivery flag must be rejected'
fi

# 18. Symlink guard: task dir must not be followed when symlinked.
SL=$WORK/symlink
mkdir -p "$SL/.ccb/briefs" "$SL/.ccb/tasks" "$SL/target"
cat >"$SL/.ccb/briefs/sl.md" <<'BRIEF'
# Goal
x
BRIEF
ln -s "$SL/target" "$SL/.ccb/tasks/sl"
if "$ROOT/ccb-template" task create "$SL" sl.md --complexity simple --id sl >/dev/null 2>&1; then
  fail 'task create must reject a pre-existing symlinked task dir'
fi

echo '[OK] V2 context-packet tests passed'