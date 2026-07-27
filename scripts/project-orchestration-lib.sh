#!/bin/sh

project_orchestration_value_is_safe() {
  value=$1 max=$2
  [ "${#value}" -le "$max" ] || return 1
  case "$value" in *'
'*|*''*|*'=') return 1;; esac
}

project_orchestration_parse_conf() {
  file=$1
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  [ "$(wc -c <"$file" | tr -d ' ')" -le 4096 ] || return 1
  ORCHESTRATION_STATUS= ORCHESTRATION_MODE= ORCHESTRATION_STARTED= ORCHESTRATION_UPDATED=
  ORCHESTRATION_COMPLETED= ORCHESTRATION_CURRENT= ORCHESTRATION_STEPS_COMPLETED=
  ORCHESTRATION_STEP_COUNT= ORCHESTRATION_ACTIONS= ORCHESTRATION_ERROR=
  seen=' '
  while IFS= read -r line || [ -n "$line" ]; do
    key=${line%%=*}; value=${line#*=}
    [ "$line" != "$key" ] || return 1
    case "$seen" in *" $key "*) return 1;; *) seen="$seen$key ";; esac
    case "$key" in
      CCB_ORCHESTRATION_VERSION) [ "$value" = 1 ] || return 1;;
      CCB_ORCHESTRATION_STATUS) ORCHESTRATION_STATUS=$value;;
      CCB_ORCHESTRATION_MODE) ORCHESTRATION_MODE=$value;;
      CCB_ORCHESTRATION_STARTED_AT) ORCHESTRATION_STARTED=$value;;
      CCB_ORCHESTRATION_UPDATED_AT) ORCHESTRATION_UPDATED=$value;;
      CCB_ORCHESTRATION_COMPLETED_AT) ORCHESTRATION_COMPLETED=$value;;
      CCB_ORCHESTRATION_CURRENT_STEP) ORCHESTRATION_CURRENT=$value;;
      CCB_ORCHESTRATION_STEPS_COMPLETED) ORCHESTRATION_STEPS_COMPLETED=$value;;
      CCB_ORCHESTRATION_STEP_COUNT) ORCHESTRATION_STEP_COUNT=$value;;
      CCB_ORCHESTRATION_ACTIONS) ORCHESTRATION_ACTIONS=$value;;
      CCB_ORCHESTRATION_ERROR) ORCHESTRATION_ERROR=$value;;
      *) return 1;;
    esac
  done <"$file"
  for key in CCB_ORCHESTRATION_VERSION CCB_ORCHESTRATION_STATUS CCB_ORCHESTRATION_MODE CCB_ORCHESTRATION_STARTED_AT CCB_ORCHESTRATION_UPDATED_AT CCB_ORCHESTRATION_COMPLETED_AT CCB_ORCHESTRATION_CURRENT_STEP CCB_ORCHESTRATION_STEPS_COMPLETED CCB_ORCHESTRATION_STEP_COUNT CCB_ORCHESTRATION_ACTIONS CCB_ORCHESTRATION_ERROR; do
    case "$seen" in *" $key "*) :;; *) return 1;; esac
  done
  case "$ORCHESTRATION_STATUS" in running|succeeded|failed|interrupted) :;; *) return 1;; esac
  [ "$ORCHESTRATION_MODE" = sequential ] || return 1
  for value in "$ORCHESTRATION_CURRENT" "$ORCHESTRATION_STEPS_COMPLETED" "$ORCHESTRATION_STEP_COUNT" "$ORCHESTRATION_ACTIONS"; do
    case "$value" in ''|*[!0-9]*) return 1;; esac
  done
  [ "$ORCHESTRATION_STEP_COUNT" -gt 0 ] && [ "$ORCHESTRATION_CURRENT" -gt 0 ] &&
    [ "$ORCHESTRATION_CURRENT" -le "$ORCHESTRATION_STEP_COUNT" ] &&
    [ "$ORCHESTRATION_STEPS_COMPLETED" -le "$ORCHESTRATION_STEP_COUNT" ] &&
    [ "$ORCHESTRATION_ACTIONS" -le $((ORCHESTRATION_STEP_COUNT * 3 + 3)) ] || return 1
  project_orchestration_value_is_safe "$ORCHESTRATION_ERROR" 160 || return 1
  case "$ORCHESTRATION_ERROR" in *[!a-z0-9-]*) return 1;; esac
  case "$ORCHESTRATION_STARTED" in ????-??-??T??:??:??[+-]????) :;; *) return 1;; esac
  case "$ORCHESTRATION_UPDATED" in ????-??-??T??:??:??[+-]????) :;; *) return 1;; esac
  LC_ALL=C; export LC_ALL
  if [ "$ORCHESTRATION_UPDATED" \< "$ORCHESTRATION_STARTED" ]; then return 1; fi
  if [ "$ORCHESTRATION_STATUS" = running ]; then
    [ -z "$ORCHESTRATION_COMPLETED" ] || return 1
  else
    case "$ORCHESTRATION_COMPLETED" in ????-??-??T??:??:??[+-]????) :;; *) return 1;; esac
    if [ "$ORCHESTRATION_COMPLETED" \< "$ORCHESTRATION_UPDATED" ]; then return 1; fi
  fi
}

project_orchestration_write_conf() {
  target=$1 status=$2 started=$3 updated=$4 completed=$5 current=$6 done_count=$7 count=$8 actions=$9
  shift 9; error=${1:-}
  case "$status" in running|succeeded|failed|interrupted) :;; *) return 1;; esac
  project_orchestration_value_is_safe "$error" 160 || return 1
  case "$error" in *[!a-z0-9-]*) return 1;; esac
  parent=$(dirname "$target")
  [ -d "$parent" ] && [ ! -L "$parent" ] && [ ! -L "$target" ] || return 1
  temp=$(mktemp "$parent/.orchestration.conf.tmp.XXXXXX") || return 1
  if printf 'CCB_ORCHESTRATION_VERSION=1\nCCB_ORCHESTRATION_STATUS=%s\nCCB_ORCHESTRATION_MODE=sequential\nCCB_ORCHESTRATION_STARTED_AT=%s\nCCB_ORCHESTRATION_UPDATED_AT=%s\nCCB_ORCHESTRATION_COMPLETED_AT=%s\nCCB_ORCHESTRATION_CURRENT_STEP=%s\nCCB_ORCHESTRATION_STEPS_COMPLETED=%s\nCCB_ORCHESTRATION_STEP_COUNT=%s\nCCB_ORCHESTRATION_ACTIONS=%s\nCCB_ORCHESTRATION_ERROR=%s\n' "$status" "$started" "$updated" "$completed" "$current" "$done_count" "$count" "$actions" "$error" >"$temp" && chmod 644 "$temp" && mv "$temp" "$target"; then return 0; fi
  rm -f "$temp"; return 1
}

project_orchestration_count_completed() {
  run_dir=$1 count=$2 i=1 total=0
  while [ "$i" -le "$count" ]; do
    step_path=$(find "$run_dir" -maxdepth 1 -type d -name "$(printf '%02d' "$i")-*" -print)
    run_step_parse "$step_path/step.conf" || return 1
    [ "$STEP_STATUS" != completed ] || total=$((total + 1))
    i=$((i + 1))
  done
  printf '%s\n' "$total"
}

project_orchestration_fail_point_is_valid() {
  [ "${CCB_TEST_MODE:-0}" = 1 ] || { [ -z "${CCB_TEST_ORCHESTRATION_FAIL_POINT:-}" ]; return; }
  case "${CCB_TEST_ORCHESTRATION_FAIL_POINT:-}" in ''|after-resume|after-execute|after-complete|before-next-step|before-success) return 0;; *) return 1;; esac
}

project_orchestration_test_interrupt() {
  [ "${CCB_TEST_MODE:-0}" = 1 ] && [ "${CCB_TEST_ORCHESTRATION_FAIL_POINT:-}" = "$1" ] || return 0
  orchestration_exit_status=interrupted
  orchestration_exit_error="test-interruption-$1"
  return 1
}
