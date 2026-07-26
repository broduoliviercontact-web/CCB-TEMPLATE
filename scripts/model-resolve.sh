#!/bin/sh
set -u
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/model-lib.sh"
agent=${1:-}; target=${2:-.}
case "$agent" in manager|graph|graphiste|developer|reviewer|fallback) ;; *) echo 'usage: model-resolve.sh AGENT [TARGET]' >&2; exit 2;; esac
[ "$#" -le 2 ] || { echo 'usage: model-resolve.sh AGENT [TARGET]' >&2; exit 2; }
file="$target/.ccb/models.conf"
models_conf_validate "$file" || { [ -f "$file" ] && exit 2 || exit 1; }
if grep -Fqx 'CCB_MODEL_PROVIDER=ollama' "$file" && grep -Fq 'CCB_MODEL_DEFAULT=' "$file"; then
  case "$agent" in manager|graph|graphiste) key=CCB_MODEL_PLANNER;; developer) key=CCB_MODEL_CODER;; reviewer) key=CCB_MODEL_REVIEWER;; fallback) key=CCB_MODEL_DEFAULT;; esac
else
  key=$(printf '%s' "$agent" | tr '[:lower:]' '[:upper:]'); key="CCB_MODEL_$key"
fi
value=$(awk -F= -v key="$key" '$1 == key { print $2 }' "$file")
if [ -z "$value" ] && [ "$agent" != fallback ]; then value=$(awk -F= '$1 == "CCB_MODEL_FALLBACK" { print $2 }' "$file"); fi
[ -n "$value" ] || exit 1
printf '%s\n' "$value"
