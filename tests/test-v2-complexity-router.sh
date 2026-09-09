#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-v2-router.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { printf '%s\n' "$1" | grep -Fq -- "$2" || fail "missing: $2"; }
assert_not_contains() { printf '%s\n' "$1" | grep -Fq -- "$2" && fail "unexpected: $2" || return 0; }

sh -n "$ROOT/scripts/v2/complexity-router.sh" || fail 'complexity-router.sh has syntax errors'

# 1. usage advertises the new commands
usage_output=$("$ROOT/ccb-template" 2>&1 || true)
assert_contains "$usage_output" 'manager-prompt TARGET BRIEF_FILE [--complexity simple|normal|complex]'
assert_contains "$usage_output" 'classify TARGET BRIEF_FILE'
assert_contains "$usage_output" 'route [simple|normal|complex]'

# 2. route subcommand for each level
for level in simple normal complex; do
  route_output=$("$ROOT/ccb-template" route "$level")
  case "$level" in
    simple)
      assert_contains "$route_output" 'SIMPLE routing'
      assert_contains "$route_output" 'Reviewer: NOT required by default'
      assert_contains "$route_output" 'Graph: NOT invoked'
      ;;
    normal)
      assert_contains "$route_output" 'NORMAL routing'
      assert_contains "$route_output" 'Graph:'
      assert_not_contains "$route_output" 'Graph: invoked by default'
      ;;
    complex)
      assert_contains "$route_output" 'COMPLEX routing'
      assert_contains "$route_output" 'Graph: invoke explicitly'
      ;;
  esac
done

# 3. unknown route level must error
if "$ROOT/ccb-template" route banana >/dev/null 2>&1; then fail 'route banana should fail'; fi

# 4. classify heuristic: semantic-first, length is a secondary signal only.
mkdir -p "$WORK/proj/.ccb/briefs"

# 4a. A short "database migration" brief is COMPLEX even when the text is tiny.
cat >"$WORK/proj/.ccb/briefs/db-migration.md" <<'BRIEF'
# Brief
database migration.
BRIEF
[ "$("$ROOT/ccb-template" classify "$WORK/proj" db-migration.md)" = complex ] \
  || fail 'a short brief mentioning database migration must be COMPLEX'

# 4b. A short ambiguous brief falls back to NORMAL (not SIMPLE).
cat >"$WORK/proj/.ccb/briefs/ambiguous.md" <<'BRIEF'
# Brief
Fix the issue.
BRIEF
[ "$("$ROOT/ccb-template" classify "$WORK/proj" ambiguous.md)" = normal ] \
  || fail 'a short ambiguous brief must fall back to NORMAL'

# 4c. An explicit local typo is SIMPLE.
cat >"$WORK/proj/.ccb/briefs/typo.md" <<'BRIEF'
# Brief
Fix typo in the header.
BRIEF
[ "$("$ROOT/ccb-template" classify "$WORK/proj" typo.md)" = simple ] \
  || fail 'explicit local typo must be SIMPLE'

# 4d. An explicit local doc change is SIMPLE.
cat >"$WORK/proj/.ccb/briefs/doc.md" <<'BRIEF'
# Brief
Update README installation steps.
BRIEF
[ "$("$ROOT/ccb-template" classify "$WORK/proj" doc.md)" = simple ] \
  || fail 'explicit local doc change must be SIMPLE'

# 4e. Strong COMPLEX signals stay COMPLEX.
cat >"$WORK/proj/.ccb/briefs/refactor.md" <<'BRIEF'
# Brief
Refactor the authentication layer and migrate the user schema.
Cross-cutting security review required before merging.
BRIEF
[ "$("$ROOT/ccb-template" classify "$WORK/proj" refactor.md)" = complex ] \
  || fail 'refactor brief must be COMPLEX'

cat >"$WORK/proj/.ccb/briefs/auth.md" <<'BRIEF'
# Brief
Add the new permissions model on top of the existing API.
BRIEF
[ "$("$ROOT/ccb-template" classify "$WORK/proj" auth.md)" = complex ] \
  || fail 'auth brief must be COMPLEX'

# 4f. An unknown-scope bug with no risky keyword falls back to NORMAL.
cat >"$WORK/proj/.ccb/briefs/bug.md" <<'BRIEF'
# Brief
The login form forgets the email address when the user navigates back
from the password reset page. Reproducible in two browsers and on the
mobile build as well. The issue appears after a successful reset and
the redirect back to the login screen, so the saved email field is
cleared instead of being preserved for the next attempt.
BRIEF
[ "$("$ROOT/ccb-template" classify "$WORK/proj" bug.md)" = normal ] \
  || fail 'medium bug brief must be NORMAL'

# 5. legacy manager-prompt keeps existing behaviour and does NOT inject routing rules.
mkdir -p "$WORK/proj2/.ccb/briefs"
printf '# Brief\nfix typo\n' >"$WORK/proj2/.ccb/briefs/brief.md"
legacy=$("$ROOT/ccb-template" manager-prompt "$WORK/proj2" brief.md)
assert_contains "$legacy" 'You are the CCB manager for this project.'
assert_contains "$legacy" 'developer is the only agent'
assert_not_contains "$legacy" '## Routing level: SIMPLE'
assert_not_contains "$legacy" '## Routing level: NORMAL'
assert_not_contains "$legacy" '## Routing level: COMPLEX'

# 6. manager-prompt --complexity injects the matching block.
for level in simple normal complex; do
  out=$("$ROOT/ccb-template" manager-prompt "$WORK/proj2" brief.md --complexity "$level")
  assert_contains "$out" "## Routing level: $(printf '%s' "$level" | tr '[:lower:]' '[:upper:]')"
done
if "$ROOT/ccb-template" manager-prompt "$WORK/proj2" brief.md --complexity banana >/dev/null 2>&1; then
  fail 'unknown complexity level should fail'
fi

# 7. Routing rules for each level: SIMPLE skips reviewer, NORMAL and COMPLEX
#    require reviewer, Graph is forbidden in SIMPLE.
simple_prompt=$("$ROOT/ccb-template" manager-prompt "$WORK/proj2" brief.md --complexity simple)
normal_prompt=$("$ROOT/ccb-template" manager-prompt "$WORK/proj2" brief.md --complexity normal)
complex_prompt=$("$ROOT/ccb-template" manager-prompt "$WORK/proj2" brief.md --complexity complex)

# SIMPLE: Reviewer is NOT required, Graph is forbidden.
assert_contains "$simple_prompt" 'Reviewer is NOT mandatory'
assert_contains "$simple_prompt" 'MUST NOT be invoked for SIMPLE'
# SIMPLE must not require reviewer in its routing block.
assert_not_contains "$simple_prompt" 'Request independent validation from reviewer'

# NORMAL: Reviewer is required.
assert_contains "$normal_prompt" 'Request independent validation from reviewer'

# COMPLEX: Reviewer is required, Graph is on demand.
assert_contains "$complex_prompt" 'Request independent validation from reviewer'
assert_contains "$complex_prompt" 'Invoke Graph'

# 8. Shared policy and manager skill encode the routing rules.
assert_contains "$(cat "$ROOT/assets/AGENT_POLICY.md")" 'on demand'
assert_contains "$(cat "$ROOT/assets/skills/ccb-manager-planning/SKILL.md")" 'SIMPLE'
assert_contains "$(cat "$ROOT/assets/skills/ccb-manager-planning/SKILL.md")" 'NORMAL'
assert_contains "$(cat "$ROOT/assets/skills/ccb-manager-planning/SKILL.md")" 'COMPLEX'

# 9. Policy contradiction is gone: it no longer states that every implementation
#    requires the reviewer. The replacement must explicitly tie reviewer
#    requirements to the complexity level.
policy=$(cat "$ROOT/assets/AGENT_POLICY.md")
if printf '%s\n' "$policy" | grep -Eqi 'every implementation|each implementation|all implementations|tout impl' \
  && ! printf '%s\n' "$policy" | grep -Fq 'depend on the selected complexity level'; then
  fail 'policy still demands reviewer for every implementation'
fi
# Also reject the legacy wording "request independent validation from reviewer before reporting completion"
assert_not_contains "$policy" 'request independent validation from reviewer before reporting completion'
policy_flat=$(printf '%s\n' "$policy" | tr '\n' ' ')
assert_contains "$policy_flat" 'required for NORMAL and COMPLEX'
assert_contains "$policy_flat" 'optional for SIMPLE'
assert_contains "$policy" 'only agent authorised to implement'

# 10. Escalation rule: SIMPLE -> NORMAL on developer signals.
dev_skill=$(cat "$ROOT/assets/skills/ccb-developer-delivery/SKILL.md")
assert_contains "$dev_skill" 'ESCALATE: SIMPLE -> NORMAL'
dev_skill_flat=$(printf '%s\n' "$dev_skill" | tr '\n' ' ')
assert_contains "$dev_skill_flat" 'unexpected side effects'
assert_contains "$dev_skill_flat" 'meaningfully outside the approved scope'
assert_contains "$dev_skill_flat" 'transversal dependency'
assert_contains "$dev_skill_flat" 'actual risk'
assert_contains "$policy" 'ESCALATE: SIMPLE -> NORMAL'

# 11. Document exists.
[ -f "$ROOT/docs/v2-complexity-router.md" ] || fail 'docs/v2-complexity-router.md is missing'

echo '[OK] V2 complexity-router tests passed'