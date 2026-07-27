#!/bin/sh
set -u
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/model-lib.sh"
agent=${1:-}; target=${2:-.}
case "$agent" in manager|graph|graphiste|developer|reviewer|fallback) ;; *) echo 'usage: model-resolve.sh AGENT [TARGET]' >&2; exit 2;; esac
[ "$#" -le 2 ] || { echo 'usage: model-resolve.sh AGENT [TARGET]' >&2; exit 2; }
file="$target/.ccb/models.conf"
models_conf_parse "$file" || { [ -f "$file" ] && exit 2 || exit 1; }
case "$agent" in manager) value=$MODEL_CONF_MANAGER;; graph) value=$MODEL_CONF_GRAPH;; graphiste) value=$MODEL_CONF_GRAPHISTE;; developer) value=$MODEL_CONF_DEVELOPER;; reviewer) value=$MODEL_CONF_REVIEWER;; fallback) value=$MODEL_CONF_FALLBACK;; esac
[ -n "$value" ] || exit 1
printf '%s\n' "$value"
