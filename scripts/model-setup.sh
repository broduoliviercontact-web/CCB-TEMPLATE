#!/bin/sh
set -u
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/model-lib.sh"

target= mode=local-proxy preset= manual=0 single= fallback= yes=0 dry=0
manager= graph= graphiste= developer= reviewer=
interactive=0
[ "$#" -eq 0 ] && interactive=1
while [ "$#" -gt 0 ]; do
  case "$1" in --preset) shift; preset=${1:-};; --single-model) shift; single=${1:-};; --manager) shift; manager=${1:-};; --graph) shift; graph=${1:-};; --graphiste) shift; graphiste=${1:-};; --developer) shift; developer=${1:-};; --reviewer) shift; reviewer=${1:-};; --fallback) shift; fallback=${1:-};; --mode) shift; mode=${1:-};; --yes) yes=1;; --dry-run) dry=1;; --manual) manual=1;; -*) echo "error: unknown option: $1" >&2; exit 2;; *) [ -z "$target" ] || { echo 'error: one target expected' >&2; exit 2; }; target=$1;; esac
  shift
done
if [ "$interactive" -eq 1 ]; then
  [ -t 0 ] || { echo 'error: models setup needs a target or an interactive terminal' >&2; exit 2; }
  printf 'Step 1/6 — Project target [.]: '; IFS= read -r target || exit 0; target=${target:-.}
  printf '%s\n' 'Step 2/6 — Ollama detection'
  if command -v ollama >/dev/null 2>&1; then ollama --version 2>/dev/null || :; ollama list 2>/dev/null || :; else echo '[WARN] Ollama was not detected; recommended models remain usable.'; fi
  printf '%s\n' 'Step 3/6 — Strategy: [1] Balanced [2] Coding [3] Reasoning [4] Creative [5] Local [6] One model [Q] Quit'
  printf 'Selection: '; IFS= read -r choice || exit 0
  case "$choice" in 1) preset=balanced-cloud;; 2) preset=coding-cloud;; 3) preset=reasoning-cloud;; 4) preset=creative-cloud;; 5) preset=local-light;; 6) printf 'Model name: '; IFS= read -r single || exit 0;; q|Q) echo 'Model setup cancelled.'; exit 0;; *) echo 'error: invalid strategy' >&2; exit 2;; esac
fi
target=${target:-.}; [ -d "$target/.ccb" ] && [ ! -L "$target/.ccb" ] || { echo 'error: CCB is not installed or is unsafe' >&2; exit 1; }
target=$(CDPATH= cd "$target" && pwd); model_mode_is_valid "$mode" || { echo 'error: invalid Ollama mode' >&2; exit 2; }
if [ -n "$preset" ]; then
  model_preset_is_safe "$preset" && model_preset_parse "$TEMPLATE_ROOT/model-presets/$preset/preset.conf" && [ "$PRESET_ID" = "$preset" ] || { echo 'error: invalid preset' >&2; exit 2; }
  manager=$MANAGER_MODEL; graph=$GRAPH_MODEL; graphiste=$GRAPHISTE_MODEL; developer=$DEVELOPER_MODEL; reviewer=$REVIEWER_MODEL; fallback=$FALLBACK_MODEL
fi
if [ -n "$single" ]; then model_name_is_safe "$single" || { echo 'error: invalid model' >&2; exit 2; }; manager=$single; graph=$single; graphiste=$single; developer=$single; reviewer=$single; [ -n "$fallback" ] || fallback=$single; preset=single-model; fi
if [ "$manual" -eq 1 ] && [ "$yes" -ne 1 ]; then echo 'error: manual setup requires explicit values and --yes in non-interactive mode' >&2; exit 2; fi
for value in "$manager" "$graph" "$graphiste" "$developer" "$reviewer" "$fallback"; do model_name_is_safe "$value" || { echo 'error: incomplete or invalid model configuration' >&2; exit 2; }; done
host=http://localhost:11434; [ "$mode" = cloud-api ] && host=https://ollama.com/api
printf 'Provider: ollama\nMode: %s\nPreset: %s\nManager: %s\nGraph: %s\nGraphiste: %s\nDeveloper: %s\nReviewer: %s\nFallback: %s\n' "$mode" "${preset:-manual}" "$manager" "$graph" "$graphiste" "$developer" "$reviewer" "$fallback"
if [ "$dry" -eq 1 ]; then echo 'DRY RUN — no files were modified'; exit 0; fi
[ "$yes" -eq 1 ] || { [ -t 0 ] || { echo 'error: --yes is required without a TTY' >&2; exit 2; }; printf 'Write this configuration? [y/N] '; IFS= read -r answer || exit 0; case "$answer" in y|Y|yes|YES);; *) echo 'Model setup cancelled.'; exit 0;; esac; }
conf_file="$target/.ccb/models.conf"; [ ! -L "$conf_file" ] || { echo 'error: models.conf symlink refused' >&2; exit 1; }
tmp=$(mktemp "$target/.ccb/.models.conf.XXXXXX") || exit 1; trap 'rm -f "$tmp"' EXIT HUP INT TERM
cat >"$tmp" <<EOF
# CCB agent model configuration (non-secret).
# Never store API keys or authentication tokens in this file.
CCB_MODEL_PROVIDER=ollama
CCB_OLLAMA_MODE=$mode
CCB_OLLAMA_HOST=$host
CCB_MODEL_PRESET=${preset:-manual}
CCB_MODEL_MANAGER=$manager
CCB_MODEL_GRAPH=$graph
CCB_MODEL_GRAPHISTE=$graphiste
CCB_MODEL_DEVELOPER=$developer
CCB_MODEL_REVIEWER=$reviewer
CCB_MODEL_FALLBACK=$fallback
EOF
models_conf_validate "$tmp" || { echo 'error: generated configuration is invalid' >&2; exit 1; }; chmod 644 "$tmp"
if [ -f "$conf_file" ]; then cp "$conf_file" "$target/.ccb/models.conf.backup-$(date +%Y%m%d-%H%M%S)"; fi
mv "$tmp" "$conf_file"; trap - EXIT HUP INT TERM; echo "updated: $conf_file"
