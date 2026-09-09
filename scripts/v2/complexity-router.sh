#!/bin/sh
# Minimal Complexity Router for CCB V2.
#
# Goal: keep behavior backward compatible while allowing the manager prompt to
# select the smallest agent set that reaches the required confidence level.
#
# Three levels:
#   SIMPLE  -> Manager / Router -> Developer -> deterministic checks
#   NORMAL  -> Manager -> Developer -> Reviewer -> Manager
#   COMPLEX -> Manager -> [Graph on demand] -> Developer -> Reviewer -> Manager
#
# This file is intentionally side-effect free: it only exposes helpers used by
# `ccb-template classify` and `ccb-template manager-prompt --complexity ...`.

v2_complexity_levels() {
  printf '%s\n' simple normal complex
}

v2_complexity_is_valid() {
  case "$1" in simple|normal|complex) return 0 ;; *) return 1 ;; esac
}

# Heuristic classification from a brief file.
#
# Decision is semantic-first: COMPLEX beats SIMPLE beats the safe NORMAL fallback.
# Brief length is a secondary signal only, never sufficient on its own.
# When the shell heuristic cannot determine SIMPLE with enough confidence, it
# returns `normal`. A few false NORMAL are preferable to false SIMPLE.
v2_complexity_classify_brief() {
  brief_file=$1
  [ -f "$brief_file" ] && [ ! -L "$brief_file" ] || {
    printf 'error: brief file is missing or unsafe: %s\n' "$brief_file" >&2
    return 1
  }
  text=$(sed -e 's/^#.*$//' "$brief_file" | tr '[:upper:]' '[:lower:]')
  lines=$(printf '%s\n' "$text" | sed '/^$/d' | wc -l | awk '{ print $1 }')

  # 1. Structural / risk keywords always win. A short "database migration" brief
  #    is COMPLEX regardless of length.
  if printf '%s\n' "$text" | grep -Eq \
    'refactor|architect|architectur|auth|permission|transversal|cross.cutting|cross-cutting|breaking|migration|upgrade|security|api contract|schema|database|deploy|deployment|backend|frontend.*interaction|infrastructure'; then
    printf '%s\n' complex
    return 0
  fi

  # 2. Anything explicitly framed as touching multiple files, several modules,
  #    several components, or with a regression risk stays NORMAL or COMPLEX.
  if printf '%s\n' "$text" | grep -Eq \
    'multiple files|several files|many files|several modules|several components|across|regression risk|risky|risque'; then
    printf '%s\n' normal
    return 0
  fi

  # 3. SIMPLE requires strong semantic evidence: an explicit isolated change
  #    type AND no risky keyword AND no unknown scope AND a small, bounded brief.
  has_simple_kind=0
  if printf '%s\n' "$text" | grep -Eq \
    '^(typo|fix typo|comment|commentaire|rename|renommer|doc|documentation|readme|update readme|update documentation|update doc|whitespace|formatting|format|small css|simple css)'; then
    has_simple_kind=1
  fi

  if [ "$has_simple_kind" -eq 1 ] && [ "$lines" -le 10 ]; then
    # Even with a small-edit keyword, escalate if the brief mentions anything
    # risky or unknown.
    if printf '%s\n' "$text" | grep -Eq 'depend|integration|impact|risk|breaking|config|permission'; then
      printf '%s\n' normal
      return 0
    fi
    printf '%s\n' simple
    return 0
  fi

  # 4. Default: NORMAL. Safer than a wrong SIMPLE.
  printf '%s\n' normal
}

# Print the routing summary line for a complexity level. Kept short so it can
# be embedded in the manager prompt without inflating tokens.
v2_complexity_route() {
  level=$1
  case "$level" in
    simple)
      cat <<'ROUTE'
SIMPLE routing:
  Manager (router) -> Developer -> deterministic checks
  Reviewer: NOT required by default.
  Graph: NOT invoked. Forbidden unless the task is reclassified.
  Escalation: developer reports ESCALATE: SIMPLE -> NORMAL on unexpected
    side effects, out-of-scope files, transversal dependencies or higher
    actual risk. Manager then applies the NORMAL workflow (reviewer required).
  Use when the change is local, isolated, low risk and the affected files
  are already known (typo, doc, simple CSS, rename, isolated fix, local test).
ROUTE
      ;;
    normal)
      cat <<'ROUTE'
NORMAL routing:
  Manager -> Developer -> Reviewer -> Manager
  Graph: invoked only if the manager needs to clarify dependencies.
  Use when the change is a non-trivial bug fix or feature that may span a
  handful of files with a reasonable regression risk.
ROUTE
      ;;
    complex)
      cat <<'ROUTE'
COMPLEX routing:
  Manager -> [Graph on demand] -> Developer -> Reviewer -> Manager
  Graph: invoke explicitly to map dependencies and structural risks before
  delegating implementation.
  Use for refactors, architecture changes, auth/permissions, cross-cutting
  concerns, or tasks where the affected files are not yet known.
ROUTE
      ;;
    *)
      printf 'error: unknown complexity level: %s\n' "$level" >&2
      return 1
      ;;
  esac
}

# Print the additional instructions to append to the manager prompt when a
# complexity level is supplied. Existing prompt content is preserved; this block
# only adds the routing rules and the "graph on demand" guard.
v2_complexity_prompt_block() {
  level=$1
  case "$level" in
    simple)
      cat <<'BLOCK'

## Routing level: SIMPLE

Use the minimum agent set that reaches the required confidence.

- Delegate implementation directly to developer.
- Reviewer is NOT mandatory; skip it unless a deterministic check fails or
  unexpected side effects appear, in which case the developer must escalate
  with `ESCALATE: SIMPLE -> NORMAL`.
- Graph is on demand and MUST NOT be invoked for SIMPLE tasks. Graph is
  forbidden unless the task is reclassified.
- Treat the task as complete after the developer report and the targeted
  deterministic checks succeed.
BLOCK
      ;;
    normal)
      cat <<'BLOCK'

## Routing level: NORMAL

Use developer plus reviewer. Graph stays optional and on demand.

- Delegate implementation to developer.
- Request independent validation from reviewer before reporting completion.
- Invoke Graph only when a real ambiguity remains about dependencies or impact.
- Treat the task as complete after the reviewer report consolidates without
  blocking findings.
BLOCK
      ;;
    complex)
      cat <<'BLOCK'

## Routing level: COMPLEX

Use graph when useful, then developer, then reviewer.

- Invoke Graph first when the affected components, dependencies or structural
  risks are not already known. Skip Graph only if the architecture has been
  mapped earlier in this same task.
- Delegate implementation to developer using the Graph findings as scope.
- Request independent validation from reviewer.
- Treat the task as complete after Graph (when used), developer and reviewer
  have all reported.
BLOCK
      ;;
    *)
      printf 'error: unknown complexity level: %s\n' "$level" >&2
      return 1
      ;;
  esac
}