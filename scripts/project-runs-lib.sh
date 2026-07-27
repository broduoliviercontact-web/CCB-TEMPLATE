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
run_parse_conf() { file=$1; [ -f "$file" ] && [ ! -L "$file" ] || return 1; RUN_ID= RUN_WORKFLOW= RUN_STATUS= RUN_CURRENT= RUN_COUNT= RUN_CREATED= RUN_UPDATED=; seen=' '; while IFS= read -r line || [ -n "$line" ]; do case "$line" in CCB_RUN_VERSION=1|CCB_RUN_SOURCE_TEMPLATE_VERSION=1.7.0|CCB_RUN_SOURCE_WORKFLOWS_VERSION=1|CCB_RUN_SOURCE_AGENTS_VERSION=1|CCB_RUN_SOURCE_MODELS_VERSION=1|CCB_RUN_COMPLETED_AT=) key=${line%%=*};; CCB_RUN_ID=*|CCB_RUN_WORKFLOW=*|CCB_RUN_STATUS=*|CCB_RUN_CURRENT_STEP=*|CCB_RUN_STEP_COUNT=*|CCB_RUN_CREATED_AT=*|CCB_RUN_UPDATED_AT=*) key=${line%%=*}; value=${line#*=};; *) return 1;; esac; case "$seen" in *" $key "*) return 1;; *) seen="$seen$key ";; esac; case "$key" in CCB_RUN_ID) RUN_ID=$value;; CCB_RUN_WORKFLOW) RUN_WORKFLOW=$value;; CCB_RUN_STATUS) RUN_STATUS=$value;; CCB_RUN_CURRENT_STEP) RUN_CURRENT=$value;; CCB_RUN_STEP_COUNT) RUN_COUNT=$value;; CCB_RUN_CREATED_AT) RUN_CREATED=$value;; CCB_RUN_UPDATED_AT) RUN_UPDATED=$value;; esac; done <"$file"; run_id_is_valid "$RUN_ID" && project_workflow_name_is_safe "$RUN_WORKFLOW" && run_status_is_valid "$RUN_STATUS" && run_integer_is_valid "$RUN_CURRENT" && run_integer_is_valid "$RUN_COUNT"; }
run_write_step() { dir=$1 number=$2 role=$3 status=$4; project_agent_details "$role"; model=$(project_agent_model_value "$PROJECT_AGENT_MODEL_ROLE") || return 1; printf 'CCB_STEP_VERSION=1\nCCB_STEP_NUMBER=%s\nCCB_STEP_ROLE=%s\nCCB_STEP_STATUS=%s\nCCB_STEP_ACCESS=%s\nCCB_STEP_MODEL_ROLE=%s\nCCB_STEP_PROVIDER=%s\nCCB_STEP_MODEL=%s\nCCB_STEP_DESCRIPTION=%s\nCCB_STEP_STARTED_AT=\nCCB_STEP_COMPLETED_AT=\n' "$number" "$role" "$status" "$PROJECT_AGENT_ACCESS" "$PROJECT_AGENT_MODEL_ROLE" "$PROJECT_MODEL_PROVIDER" "$model" "$PROJECT_AGENT_DESCRIPTION" >"$dir/step.conf"; }
