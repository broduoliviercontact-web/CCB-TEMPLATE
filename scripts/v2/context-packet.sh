#!/bin/sh
# Context Packet v1 helpers.
#
# TASK PACKET  = stable task state (complexity, goal, scope, acceptance,
#                constraints, known context).
# DELIVERY DELTA = implementation result (changed, validation, summary, notes).
#
# The packet is a compact pointer to the real repository. It is NOT a copy of
# the conversation, the full diff, full test logs or long Graph reports.
#
# Extraction from the brief is purely mechanical (deterministic Markdown
# parsing). No LLM is invoked.

v2_packet_safe_id() {
  case "$1" in
    ''|.*|*'/'*|*'\\'*|*'..'*) return 1 ;;
  esac
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_' | head -c 96
  printf '\n'
}

# v2_packet_task_dir <project_dir> <task_id>
v2_packet_task_dir() {
  packet_target=$1 packet_id=$2
  v2_packet_safe_id "$packet_id" >/dev/null || {
    printf 'error: invalid task id: %s\n' "$packet_id" >&2
    return 1
  }
  task_dir=$packet_target/.ccb/tasks/$packet_id
  [ ! -L "$task_dir" ] || { printf 'error: unsafe task directory: %s\n' "$task_dir" >&2; return 1; }
  printf '%s\n' "$task_dir"
}

# Internal: print the value of a H2/H3 named section from a Markdown file.
# Section body is everything after the heading up to the next heading of the
# same or higher level. Empty body -> no output. No interpretation.
# Args: file, level (2 or 3), name (matched case-insensitively, ignoring the
# leading "#"s).
_v2_packet_extract_section() {
  _f=$1; _want_name=$2
  # Accept any heading level (# to ######) whose title (case-insensitive)
  # matches. The body is everything after the heading until the next heading
  # of any level.
  want_lower=$(printf '%s' "$_want_name" | tr '[:upper:]' '[:lower:]')
  awk -v want_lower="$want_lower" '
    function lc(s) { return tolower(s) }
    {
      n = 0
      while (substr($0, n + 1, 1) == "#") n++
      if (n > 0 && n <= 6 && substr($0, n + 1, 1) == " ") {
        title = substr($0, n + 2)
        sub(/^[[:space:]]+/, "", title)
        sub(/[[:space:]]+$/, "", title)
        title_lower = lc(title)
        if (title_lower == want_lower) {
          printing = 1
          match_lvl = n
          next
        }
        if (printing && n > 0 && n <= match_lvl) {
          printing = 0
        }
      }
      if (printing) print
    }
  ' "$_f"
}

# Map of brief section name -> TASK PACKET field name.
# Case-insensitive, accepts slight variations.
_v2_packet_alias() {
  case "$1" in
    goal|objectives|summary) printf 'goal' ;;
    scope|files|targets) printf 'scope' ;;
    acceptance|acceptance\ criteria|criteria|tests) printf 'acceptance' ;;
    constraints|constraint|limitations|limits) printf 'constraints' ;;
    known\ context|context|notes|background) printf 'known_context' ;;
    *) return 1 ;;
  esac
}

# Print space-separated aliases for a canonical field (used during extraction).
v2_packet_alias_canon() {
  case "$1" in
    goal)            printf '%s' "goal objectives summary" ;;
    scope)           printf '%s' "scope files targets" ;;
    acceptance)      printf '%s' "acceptance criteria 'acceptance criteria' tests" ;;
    constraints)     printf '%s' "constraints limitations limits" ;;
    known_context)   printf '%s' "'known context' context background notes" ;;
    *) return 1 ;;
  esac
}

# Extract every recognised section from the brief into a tempfile and print
# its path. Caller reads the file with the field-prefix format:
#   # <field>
#   body
# Sections that were not present are absent (no placeholders).
_v2_packet_parse_brief() {
  _brief=$1
  _tmp=$(mktemp 2>/dev/null) || return 1
  # Try the canonical name first, then known aliases.
  for canon in goal scope acceptance constraints known_context; do
    found=0
    for alias in \
      "goal" "objectives" "summary" \
      "scope" "files" "targets" \
      "acceptance" "criteria" "acceptance criteria" "tests" \
      "constraints" "limitations" "limits" \
      "known context" "context" "background" "notes"; do
      [ "$found" -eq 1 ] && continue
      # Quick reject: if the alias doesn't match the current canon family.
      case "$canon" in
        goal)            want_alias=goal           ;;
        scope)           want_alias=scope          ;;
        acceptance)      want_alias=acceptance     ;;
        constraints)     want_alias=constraints    ;;
        known_context)   want_alias=known_context_alias ;;
      esac
      # Accept the alias only if it actually belongs to the current canon.
      case "$canon:$alias" in
        goal:goal|goal:objectives|goal:summary) : ;;
        scope:scope|scope:files|scope:targets) : ;;
        acceptance:acceptance|acceptance:criteria|acceptance:'acceptance criteria'|acceptance:tests) : ;;
        constraints:constraints|constraints:limitations|constraints:limits) : ;;
        known_context:'known context'|known_context:context|known_context:background|known_context:notes) : ;;
        *) continue ;;
      esac
      body=$(_v2_packet_extract_section "$_brief" "$alias" | sed '/./,$!d')
      if [ -n "$body" ]; then
        printf '# %s\n%s\n\n' "$canon" "$body" >>"$_tmp"
        found=1
        break
      fi
    done
  done

  # Goal fallback: if no recognised Goal section, use the first non-empty,
  # non-heading block of the brief (a legacy unstructured brief).
  if ! grep -q '^# goal$' "$_tmp"; then
    fallback=$(awk '
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*$/ { if (got_blank) next; got_blank = 1; next }
      { got_blank = 0; print }
    ' "$_brief" | head -5)
    if [ -n "$fallback" ]; then
      printf '# goal\n%s\n\n' "$fallback" >>"$_tmp"
    fi
  fi

  printf '%s\n' "$_tmp"
}

# v2_packet_create <project_dir> <task_id> <complexity> <brief_file>
v2_packet_create() {
  packet_target=$1 packet_id=$2 packet_complexity=$3 packet_brief=$4
  v2_complexity_is_valid "$packet_complexity" || {
    printf 'error: unknown complexity level: %s\n' "$packet_complexity" >&2
    return 1
  }
  [ -d "$packet_target/.ccb" ] && [ ! -L "$packet_target/.ccb" ] || {
    printf 'error: not a CCB project: %s\n' "$packet_target" >&2
    return 1
  }
  brief_path=$packet_target/.ccb/briefs/$packet_brief
  [ -f "$brief_path" ] && [ ! -L "$brief_path" ] || {
    printf 'error: brief not found: %s\n' "$brief_path" >&2
    return 1
  }
  task_dir=$(v2_packet_task_dir "$packet_target" "$packet_id") || return 1
  mkdir -p "$task_dir" || return 1
  task_file=$task_dir/task.md
  [ ! -e "$task_file" ] || {
    printf 'error: task packet already exists: %s\n' "$task_file" >&2
    return 1
  }
  parsed=$(_v2_packet_parse_brief "$brief_path") || return 1
  tmp=$(mktemp "$task_dir/.task.XXXXXX") || { rm -f "$parsed"; return 1; }
  trap 'rm -f "$tmp" "$parsed"' EXIT HUP INT TERM
  {
    printf '# TASK PACKET\n\n'
    printf 'Task id: %s\n' "$packet_id"
    printf 'Complexity: %s\n\n' "$packet_complexity"
    cat "$parsed"
  } >"$tmp"
  chmod 600 "$tmp" && mv "$tmp" "$task_file"
  trap - EXIT HUP INT TERM
  rm -f "$parsed"
  printf 'Task packet created: %s\n' "$task_file"
}

# v2_packet_show <project_dir> <task_id>
v2_packet_show() {
  packet_target=$1 packet_id=$2
  task_dir=$(v2_packet_task_dir "$packet_target" "$packet_id") || return 1
  if [ -f "$task_dir/task.md" ] && [ ! -L "$task_dir/task.md" ]; then
    printf '%s\n' '--- TASK PACKET ---'
    cat "$task_dir/task.md"
  else
    printf '%s\n' 'no task.md'
  fi
  if [ -f "$task_dir/delivery.md" ] && [ ! -L "$task_dir/delivery.md" ]; then
    printf '\n%s\n' '--- DELIVERY DELTA ---'
    cat "$task_dir/delivery.md"
  else
    printf '\n%s\n' 'no delivery.md yet'
  fi
}

# Internal: write the delivery body to <task_dir>/delivery.md.
# Args: task_dir, changed, validation, summary, notes (any of these may be empty).
_v2_packet_write_delivery() {
  _td=$1 _changed=$2 _validation=$3 _summary=$4 _notes=$5
  delivery_file=$_td/delivery.md
  [ ! -e "$delivery_file" ] || {
    printf 'error: delivery already exists: %s\n' "$delivery_file" >&2
    return 1
  }
  tmp=$(mktemp "$_td/.delivery.XXXXXX") || return 1
  trap 'rm -f "$tmp"' EXIT HUP INT TERM
  {
    printf '# DELIVERY DELTA\n\n'
    if [ -n "$_changed" ]; then
      printf 'Changed:\n'
      printf '%s' "$_changed" | tr '|' '\n' | sed 's/^/- /'
      printf '\n'
    fi
    if [ -n "$_validation" ]; then
      printf '\nValidation:\n'
      printf '%s' "$_validation" | tr '|' '\n' | sed 's/^/- /'
      printf '\n'
    fi
    if [ -n "$_summary" ]; then
      printf '\nSummary:\n%s\n' "$_summary"
    fi
    if [ -n "$_notes" ]; then
      printf '\nNotes:\n%s\n' "$_notes"
    fi
  } >"$tmp"
  chmod 600 "$tmp" && mv "$tmp" "$delivery_file"
  trap - EXIT HUP INT TERM
}

# v2_packet_delivery <project_dir> <task_id> <changed> <validation> <summary> <notes>
# Any field may be the empty string; absent fields are omitted (no placeholders).
v2_packet_delivery() {
  packet_target=$1 packet_id=$2 changed=$3 validation=$4 summary=$5 notes=$6
  task_dir=$(v2_packet_task_dir "$packet_target" "$packet_id") || return 1
  task_file=$task_dir/task.md
  [ -f "$task_file" ] && [ ! -L "$task_file" ] || {
    printf 'error: task packet is missing: %s\n' "$task_file" >&2
    return 1
  }
  _v2_packet_write_delivery "$task_dir" "$changed" "$validation" "$summary" "$notes"
  printf 'Delivery delta written: %s/delivery.md\n' "$task_dir"
}

# v2_packet_git_changed <project_dir>
# Returns a "|" separated list of changed files relative to HEAD, or empty
# string if no changes / no git.
v2_packet_git_changed() {
  packet_target=$1
  if command -v git >/dev/null 2>&1 && [ -d "$packet_target/.git" ]; then
    git -C "$packet_target" diff --name-only HEAD 2>/dev/null \
      | sed '/^$/d' | tr '\n' '|' | sed 's/|$//'
  fi
}

# v2_packet_review_input <project_dir> <task_id>
v2_packet_review_input() {
  packet_target=$1 packet_id=$2
  task_dir=$(v2_packet_task_dir "$packet_target" "$packet_id") || return 1
  task_file=$task_dir/task.md
  delivery_file=$task_dir/delivery.md
  [ -f "$task_file" ] && [ ! -L "$task_file" ] || {
    printf 'error: task packet is missing: %s\n' "$task_file" >&2
    return 1
  }
  [ -f "$delivery_file" ] && [ ! -L "$delivery_file" ] || {
    printf 'error: delivery delta is missing: %s\n' "$delivery_file" >&2
    return 1
  }
  printf '%s\n\n' 'REVIEW INPUT'
  printf '%s\n' '--- TASK PACKET ---'
  cat "$task_file"
  printf '\n%s\n' '--- DELIVERY DELTA ---'
  cat "$delivery_file"
  printf '\n%s\n' '--- DIFF SOURCE ---'
  if command -v git >/dev/null 2>&1 && [ -d "$packet_target/.git" ]; then
    printf 'git -C %s diff\n' "$packet_target"
  else
    printf 'no git repository available; use the file paths listed above\n'
  fi
}