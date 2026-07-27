#!/bin/sh

run_id_is_valid() {
  value=$1
  case "$value" in *[!0-9a-z-]*|*..*|*--*|????????-??????-|????????-??????-*[!0-9a-z-]*|'') return 1;; esac
  date_part=${value%%-*}; rest=${value#*-}; time_part=${rest%%-*}; workflow=${rest#*-}
  [ "${#date_part}" -eq 8 ] && [ "${#time_part}" -eq 6 ] || return 1
  case "$workflow" in [a-z]|[a-z][a-z0-9-]* ) :;; *) return 1;; esac
}
run_status_is_valid() { case "$1" in pending|in-progress|blocked|completed|cancelled) return 0;; *) return 1;; esac; }
run_integer_is_valid() { case "$1" in ''|*[!0-9]*|0) return 1;; *) return 0;; esac; }
run_timestamp() { date '+%Y-%m-%dT%H:%M:%S%z'; }
run_identifier() { printf '%s-%s\n' "$(date '+%Y%m%d-%H%M%S')" "$1"; }
run_write_conf() { file=$1; temp=$(mktemp "$(dirname "$file")/.run.conf.tmp.XXXXXX") || return 1; printf 'CCB_RUN_VERSION=1\nCCB_RUN_ID=%s\nCCB_RUN_WORKFLOW=%s\nCCB_RUN_STATUS=%s\nCCB_RUN_CURRENT_STEP=%s\nCCB_RUN_STEP_COUNT=%s\nCCB_RUN_CREATED_AT=%s\nCCB_RUN_UPDATED_AT=%s\nCCB_RUN_COMPLETED_AT=\nCCB_RUN_SOURCE_TEMPLATE_VERSION=1.7.0\nCCB_RUN_SOURCE_WORKFLOWS_VERSION=1\nCCB_RUN_SOURCE_AGENTS_VERSION=1\nCCB_RUN_SOURCE_MODELS_VERSION=1\n' "$RUN_ID" "$RUN_WORKFLOW" "$RUN_STATUS" "$RUN_CURRENT" "$RUN_COUNT" "$RUN_CREATED" "$RUN_UPDATED" >"$temp" && chmod 644 "$temp" && mv "$temp" "$file"; }
run_parse_conf() { file=$1; [ -f "$file" ] && [ ! -L "$file" ] || return 1; RUN_ID= RUN_WORKFLOW= RUN_STATUS= RUN_CURRENT= RUN_COUNT= RUN_CREATED= RUN_UPDATED= RUN_COMPLETED=; seen=' '; while IFS= read -r line || [ -n "$line" ]; do case "$line" in CCB_RUN_VERSION=1|CCB_RUN_SOURCE_TEMPLATE_VERSION=1.7.0|CCB_RUN_SOURCE_WORKFLOWS_VERSION=1|CCB_RUN_SOURCE_AGENTS_VERSION=1|CCB_RUN_SOURCE_MODELS_VERSION=1) key=${line%%=*};; CCB_RUN_COMPLETED_AT=*|CCB_RUN_ID=*|CCB_RUN_WORKFLOW=*|CCB_RUN_STATUS=*|CCB_RUN_CURRENT_STEP=*|CCB_RUN_STEP_COUNT=*|CCB_RUN_CREATED_AT=*|CCB_RUN_UPDATED_AT=*) key=${line%%=*}; value=${line#*=};; *) return 1;; esac; case "$seen" in *" $key "*) return 1;; *) seen="$seen$key ";; esac; case "$key" in CCB_RUN_ID) RUN_ID=$value;; CCB_RUN_WORKFLOW) RUN_WORKFLOW=$value;; CCB_RUN_STATUS) RUN_STATUS=$value;; CCB_RUN_CURRENT_STEP) RUN_CURRENT=$value;; CCB_RUN_STEP_COUNT) RUN_COUNT=$value;; CCB_RUN_CREATED_AT) RUN_CREATED=$value;; CCB_RUN_UPDATED_AT) RUN_UPDATED=$value;; CCB_RUN_COMPLETED_AT) RUN_COMPLETED=$value;; esac; done <"$file"; run_id_is_valid "$RUN_ID" && project_workflow_name_is_safe "$RUN_WORKFLOW" && run_status_is_valid "$RUN_STATUS" && run_integer_is_valid "$RUN_CURRENT" && run_integer_is_valid "$RUN_COUNT"; }
run_write_step() { dir=$1 number=$2 role=$3 status=$4; project_agent_details "$role"; model=$(project_agent_model_value "$PROJECT_AGENT_MODEL_ROLE") || return 1; printf 'CCB_STEP_VERSION=1\nCCB_STEP_NUMBER=%s\nCCB_STEP_ROLE=%s\nCCB_STEP_STATUS=%s\nCCB_STEP_ACCESS=%s\nCCB_STEP_MODEL_ROLE=%s\nCCB_STEP_PROVIDER=%s\nCCB_STEP_MODEL=%s\nCCB_STEP_DESCRIPTION=%s\nCCB_STEP_STARTED_AT=\nCCB_STEP_COMPLETED_AT=\n' "$number" "$role" "$status" "$PROJECT_AGENT_ACCESS" "$PROJECT_AGENT_MODEL_ROLE" "$PROJECT_MODEL_PROVIDER" "$model" "$PROJECT_AGENT_DESCRIPTION" >"$dir/step.conf"; }
run_step_parse() { file=$1; [ -f "$file" ] && [ ! -L "$file" ] || return 1; STEP_NUMBER= STEP_ROLE= STEP_STATUS= STEP_ACCESS= STEP_MODEL_ROLE= STEP_PROVIDER= STEP_MODEL= STEP_DESCRIPTION= STEP_STARTED= STEP_COMPLETED=; seen=' '; while IFS= read -r line || [ -n "$line" ]; do case "$line" in CCB_STEP_VERSION=1) key=${line%%=*};; CCB_STEP_STARTED_AT=*|CCB_STEP_COMPLETED_AT=*|CCB_STEP_NUMBER=*|CCB_STEP_ROLE=*|CCB_STEP_STATUS=*|CCB_STEP_ACCESS=*|CCB_STEP_MODEL_ROLE=*|CCB_STEP_PROVIDER=*|CCB_STEP_MODEL=*|CCB_STEP_DESCRIPTION=*) key=${line%%=*}; value=${line#*=};; *) return 1;; esac; case "$seen" in *" $key "*) return 1;; *) seen="$seen$key ";; esac; case "$key" in CCB_STEP_NUMBER) STEP_NUMBER=$value;; CCB_STEP_ROLE) STEP_ROLE=$value;; CCB_STEP_STATUS) STEP_STATUS=$value;; CCB_STEP_ACCESS) STEP_ACCESS=$value;; CCB_STEP_MODEL_ROLE) STEP_MODEL_ROLE=$value;; CCB_STEP_PROVIDER) STEP_PROVIDER=$value;; CCB_STEP_MODEL) STEP_MODEL=$value;; CCB_STEP_DESCRIPTION) STEP_DESCRIPTION=$value;; CCB_STEP_STARTED_AT) STEP_STARTED=$value;; CCB_STEP_COMPLETED_AT) STEP_COMPLETED=$value;; esac; done <"$file"; run_integer_is_valid "$STEP_NUMBER" && project_agent_role_is_safe "$STEP_ROLE" && case "$STEP_STATUS" in pending|ready|in-progress|completed|blocked|skipped) :;; *) return 1;; esac; project_agent_access_is_valid "$STEP_ACCESS" && project_agent_model_role_is_valid "$STEP_MODEL_ROLE" && [ -n "$STEP_PROVIDER" ] && [ -n "$STEP_MODEL" ] && [ -n "$STEP_DESCRIPTION" ]; }
run_write_step_conf() { file=$1; temp=$(mktemp "$(dirname "$file")/.step.conf.tmp.XXXXXX") || return 1; printf 'CCB_STEP_VERSION=1\nCCB_STEP_NUMBER=%s\nCCB_STEP_ROLE=%s\nCCB_STEP_STATUS=%s\nCCB_STEP_ACCESS=%s\nCCB_STEP_MODEL_ROLE=%s\nCCB_STEP_PROVIDER=%s\nCCB_STEP_MODEL=%s\nCCB_STEP_DESCRIPTION=%s\nCCB_STEP_STARTED_AT=%s\nCCB_STEP_COMPLETED_AT=%s\n' "$STEP_NUMBER" "$STEP_ROLE" "$STEP_STATUS" "$STEP_ACCESS" "$STEP_MODEL_ROLE" "$STEP_PROVIDER" "$STEP_MODEL" "$STEP_DESCRIPTION" "$STEP_STARTED" "$STEP_COMPLETED" >"$temp" && chmod 644 "$temp" && mv "$temp" "$file"; }
run_validate_directory() { dir=$1; [ -d "$dir" ] && [ ! -L "$dir" ] || return 1; run_parse_conf "$dir/run.conf" || return 1; [ "$(basename "$dir")" = "$RUN_ID" ] || return 1; [ -f "$dir/context.md" ] && [ ! -L "$dir/context.md" ] || return 1; [ "$RUN_COUNT" -le 99 ] 2>/dev/null || return 1; i=1; while [ "$i" -le "$RUN_COUNT" ]; do matches=$(find "$dir" -maxdepth 1 -type d -name "$(printf '%02d' "$i")-*" ! -type l -print); [ "$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || return 1; stepdir=$matches; run_step_parse "$stepdir/step.conf" || return 1; [ "$STEP_NUMBER" = "$i" ] && [ "$(basename "$stepdir")" = "$(printf '%02d-%s' "$i" "$STEP_ROLE")" ] && [ -f "$stepdir/input.md" ] && [ ! -L "$stepdir/input.md" ] && [ -f "$stepdir/result.md" ] && [ ! -L "$stepdir/result.md" ] || return 1; i=$((i+1)); done; }
run_latest_id() { runs=$1; best=; bestkey=; for candidate in "$runs"/*; do [ -d "$candidate" ] && [ ! -L "$candidate" ] || continue; name=$(basename "$candidate"); run_id_is_valid "$name" || continue; key=$(printf '%s\n' "$name" | awk -F- '{suffix=1; if (NF>3) suffix=$NF; printf "%s%s%06d",$1,$2,suffix}'); if [ -z "$bestkey" ] || [ "$key" \> "$bestkey" ]; then best=$name; bestkey=$key; fi; done; [ -n "$best" ] && printf '%s\n' "$best"; }
project_run_validate_pending_result() {
  file=$1
  [ -f "$file" ] && [ ! -L "$file" ] || { echo 'error: unsafe current step result file' >&2; return 1; }
  size=$(wc -c <"$file" | tr -d ' '); [ "$size" -le 262144 ] || { echo 'error: current step result is too large' >&2; return 1; }
  header=$(sed -n '1,3p' "$file"); [ "$header" = '# Step Result

Status: pending' ] || { echo 'error: invalid current step result header' >&2; return 1; }
  [ "$(grep -c '^Status: ' "$file")" = 1 ] || { echo 'error: ambiguous current step result status' >&2; return 1; }
  body=$(sed -n '5,$p' "$file" | tr -d '[:space:]')
  [ -n "$body" ] && [ "$(cat "$file")" != '# Step Result

Status: pending

Record the result of this step below.' ] || { echo 'error: current step result is still pending' >&2; return 1; }
}
project_run_prepare_completed_result() {
  source=$1; output=$2
  project_run_validate_pending_result "$source" || return 1
  { sed -n '1,2p' "$source"; echo 'Status: completed'; sed -n '4,$p' "$source"; } >"$output" || return 1
  chmod 644 "$output" && [ -f "$output" ] && [ ! -L "$output" ] && [ "$(grep -c '^Status: completed$' "$output")" = 1 ]
}

project_run_write_step_prepared() {
  file=$1
  printf 'CCB_STEP_VERSION=1\nCCB_STEP_NUMBER=%s\nCCB_STEP_ROLE=%s\nCCB_STEP_STATUS=%s\nCCB_STEP_ACCESS=%s\nCCB_STEP_MODEL_ROLE=%s\nCCB_STEP_PROVIDER=%s\nCCB_STEP_MODEL=%s\nCCB_STEP_DESCRIPTION=%s\nCCB_STEP_STARTED_AT=%s\nCCB_STEP_COMPLETED_AT=%s\n' \
    "$STEP_NUMBER" "$STEP_ROLE" "$STEP_STATUS" "$STEP_ACCESS" "$STEP_MODEL_ROLE" \
    "$STEP_PROVIDER" "$STEP_MODEL" "$STEP_DESCRIPTION" "$STEP_STARTED" "$STEP_COMPLETED" >"$file" &&
    chmod 600 "$file"
}

project_run_write_run_prepared() {
  file=$1
  printf 'CCB_RUN_VERSION=1\nCCB_RUN_ID=%s\nCCB_RUN_WORKFLOW=%s\nCCB_RUN_STATUS=%s\nCCB_RUN_CURRENT_STEP=%s\nCCB_RUN_STEP_COUNT=%s\nCCB_RUN_CREATED_AT=%s\nCCB_RUN_UPDATED_AT=%s\nCCB_RUN_COMPLETED_AT=%s\nCCB_RUN_SOURCE_TEMPLATE_VERSION=1.7.0\nCCB_RUN_SOURCE_WORKFLOWS_VERSION=1\nCCB_RUN_SOURCE_AGENTS_VERSION=1\nCCB_RUN_SOURCE_MODELS_VERSION=1\n' \
    "$RUN_ID" "$RUN_WORKFLOW" "$RUN_STATUS" "$RUN_CURRENT" "$RUN_COUNT" \
    "$RUN_CREATED" "$RUN_UPDATED" "$RUN_COMPLETED" >"$file" && chmod 600 "$file"
}

project_run_transaction_create() {
  run_dir=$1
  [ -d "$run_dir" ] && [ ! -L "$run_dir" ] || return 1
  old_umask=$(umask); umask 077
  transaction_dir=
  transaction_index=0
  while [ "$transaction_index" -lt 100 ]; do
    transaction_suffix="$$.$transaction_index"
    candidate="$run_dir/.ccb-transaction.$transaction_suffix"
    if mkdir "$candidate" 2>/dev/null; then transaction_dir=$candidate; break; fi
    transaction_index=$((transaction_index + 1))
  done
  umask "$old_umask"
  [ -n "$transaction_dir" ] && [ -d "$transaction_dir" ] && [ ! -L "$transaction_dir" ]
}

project_run_transaction_cleanup() {
  transaction=$1; run_dir=$2
  [ -n "$transaction" ] && [ -d "$transaction" ] && [ ! -L "$transaction" ] || return 1
  [ "$(dirname "$transaction")" = "$run_dir" ] || return 1
  case "$(basename "$transaction")" in .ccb-transaction.*) :;; *) return 1;; esac
  find "$transaction" -type f -exec rm -f {} \; || return 1
  rmdir "$transaction"
}

project_run_transaction_copy() {
  source=$1; destination=$2
  [ -f "$source" ] && [ ! -L "$source" ] || return 1
  [ -d "$(dirname "$destination")" ] && [ ! -L "$(dirname "$destination")" ] || return 1
  cp "$source" "$destination" && chmod 600 "$destination" &&
    [ -f "$destination" ] && [ ! -L "$destination" ]
}

project_run_transaction_publish() {
  source=$1; target=$2
  parent=$(dirname "$target")
  [ -f "$source" ] && [ ! -L "$source" ] && [ -d "$parent" ] && [ ! -L "$parent" ] &&
    [ -f "$target" ] && [ ! -L "$target" ] || return 1
  publish_tmp=$(mktemp "$parent/.ccb-publish.XXXXXX") || return 1
  if cp "$source" "$publish_tmp" && chmod 644 "$publish_tmp" && mv "$publish_tmp" "$target"; then return 0; fi
  rm -f "$publish_tmp"
  return 1
}

project_run_transaction_restore() {
  backup=$1; target=$2
  project_run_transaction_publish "$backup" "$target"
}

project_run_test_fail_point_is_valid() {
  case "${CCB_TEST_FAIL_POINT:-}" in ''|before-publish|after-current-step|after-result|after-next-input|after-next-step|before-run|after-run) return 0;; *) echo 'error: invalid workflow transaction fail point' >&2; return 1;; esac
}

project_run_test_fail_point() {
  point=$1
  if [ "${CCB_TEST_FAIL_POINT:-}" = "$point" ]; then
    echo "error: injected workflow transaction failure: $point" >&2
    return 1
  fi
}

project_run_validate_completed_result() {
  file=$1
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  [ "$(sed -n '1,3p' "$file")" = '# Step Result

Status: completed' ] && [ "$(grep -c '^Status: completed$' "$file")" = 1 ] &&
    [ "$(grep -c '^Status: ' "$file")" = 1 ]
}

project_run_validate_current_step_prepared() (
  file=$1; expected_number=$2; expected_role=$3
  run_step_parse "$file" && [ "$STEP_NUMBER" = "$expected_number" ] &&
    [ "$STEP_ROLE" = "$expected_role" ] && [ "$STEP_STATUS" = completed ] &&
    [ -n "$STEP_STARTED" ] && [ -n "$STEP_COMPLETED" ]
)

project_run_validate_next_step_prepared() (
  file=$1; expected_number=$2; expected_role=$3
  run_step_parse "$file" && [ "$STEP_NUMBER" = "$expected_number" ] &&
    [ "$STEP_ROLE" = "$expected_role" ] && [ "$STEP_STATUS" = ready ] &&
    [ -z "$STEP_STARTED" ] && [ -z "$STEP_COMPLETED" ]
)

project_run_validate_transmission() {
  input=$1; source_name=$2; result=$3; scratch=$4
  [ -f "$input" ] && [ ! -L "$input" ] || return 1
  input_size=$(wc -c <"$input" | tr -d ' '); [ "$input_size" -le 524288 ] || return 1
  [ "$(grep -Fxc "Source: ../$source_name/result.md" "$input")" = 1 ] || return 1
  [ "$(grep -Fxc -- '----- BEGIN PREVIOUS RESULT -----' "$input")" = 1 ] || return 1
  [ "$(grep -Fxc -- '----- END PREVIOUS RESULT -----' "$input")" = 1 ] || return 1
  sed -n '/^----- BEGIN PREVIOUS RESULT -----$/,/^----- END PREVIOUS RESULT -----$/p' "$input" |
    sed '1d;$d' >"$scratch" || return 1
  cmp -s "$scratch" "$result"
}

project_run_validate_run_prepared() (
  file=$1; expected_current=$2; expected_status=$3; completion=$4
  run_parse_conf "$file" && [ "$RUN_CURRENT" = "$expected_current" ] &&
    [ "$RUN_STATUS" = "$expected_status" ] && [ -n "$RUN_UPDATED" ] || exit 1
  if [ "$completion" = required ]; then [ -n "$RUN_COMPLETED" ]; else [ -z "$RUN_COMPLETED" ]; fi
)

project_run_summary() {
  runs_dir=$1
  RUNS_DIRECTORY=absent; RUNS_TOTAL=0; RUNS_VALID=0; RUNS_INVALID=0
  RUNS_PENDING=0; RUNS_IN_PROGRESS=0; RUNS_BLOCKED=0; RUNS_COMPLETED=0; RUNS_CANCELLED=0
  RUNS_EXECUTION_SUCCEEDED=0; RUNS_EXECUTION_FAILED=0
  RUNS_LATEST=none; RUNS_LATEST_STATUS=none; latest_key=
  [ ! -e "$runs_dir" ] && [ ! -L "$runs_dir" ] && return 0
  RUNS_DIRECTORY=present
  if [ ! -d "$runs_dir" ] || [ -L "$runs_dir" ]; then RUNS_TOTAL=1; RUNS_INVALID=1; return 0; fi
  for candidate in "$runs_dir"/*; do
    [ -e "$candidate" ] || [ -L "$candidate" ] || continue
    case "$(basename "$candidate")" in .ccb-transaction.*) continue;; esac
    RUNS_TOTAL=$((RUNS_TOTAL + 1))
    if run_validate_directory "$candidate"; then
      RUNS_VALID=$((RUNS_VALID + 1))
      case "$RUN_STATUS" in
        pending) RUNS_PENDING=$((RUNS_PENDING + 1));;
        in-progress) RUNS_IN_PROGRESS=$((RUNS_IN_PROGRESS + 1));;
        blocked) RUNS_BLOCKED=$((RUNS_BLOCKED + 1));;
        completed) RUNS_COMPLETED=$((RUNS_COMPLETED + 1));;
        cancelled) RUNS_CANCELLED=$((RUNS_CANCELLED + 1));;
      esac
      candidate_id=$(basename "$candidate")
      candidate_succeeded=0; candidate_failed=0
      for execution_candidate in "$candidate"/*/execution.conf; do
        [ -e "$execution_candidate" ] || [ -L "$execution_candidate" ] || continue
        if project_execution_parse_conf "$execution_candidate"; then
          [ "$EXECUTION_STATUS" = succeeded ] && candidate_succeeded=1
          [ "$EXECUTION_STATUS" = failed ] && candidate_failed=1
        fi
      done
      RUNS_EXECUTION_SUCCEEDED=$((RUNS_EXECUTION_SUCCEEDED + candidate_succeeded))
      RUNS_EXECUTION_FAILED=$((RUNS_EXECUTION_FAILED + candidate_failed))
      candidate_key=$(printf '%s\n' "$candidate_id" | awk -F- '{suffix=1; if (NF>3) suffix=$NF; printf "%s%s%06d",$1,$2,suffix}')
      if [ -z "$latest_key" ] || [ "$candidate_key" \> "$latest_key" ]; then
        latest_key=$candidate_key; RUNS_LATEST=$candidate_id; RUNS_LATEST_STATUS=$RUN_STATUS
      fi
    else
      RUNS_INVALID=$((RUNS_INVALID + 1))
    fi
  done
}
