#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$ROOT/scripts/v2/common.sh"
. "$ROOT/scripts/v2/preflight.sh"
. "$ROOT/scripts/v2/render-config.sh"
. "$ROOT/scripts/v2/install-assets.sh"

usage() {
  cat <<'EOF'
usage: ./install.sh TARGET --name NAME --profile web --claude-ollama-cloud [--yes|--dry-run]

Prepare a project for the official Claude Code Bridge (CCB) with Claude Code
using Ollama Cloud through its Anthropic-compatible local endpoint.

Options:
  --name NAME              Project name written to shared memory
  --profile web             Required built-in V2 preset (web is the only preset currently supported)
  --claude-ollama-cloud     Enable the required Claude Code + Ollama Cloud layout
  --yes                    Confirm a non-interactive installation
  --dry-run                Show the plan without writing files
  -h, --help               Show this help
EOF
}

target= name= profile= cloud=0 yes=0 dry_run=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --name) shift; [ "$#" -gt 0 ] || v2_die '--name requires a value'; name=$1 ;;
    --profile) shift; [ "$#" -gt 0 ] || v2_die '--profile requires a value'; profile=$1 ;;
    --claude-ollama-cloud) cloud=1 ;;
    --yes) yes=1 ;;
    --dry-run) dry_run=1 ;;
    -*) v2_die "unknown option: $1" ;;
    *) [ -z "$target" ] || v2_die 'only one target is accepted'; target=$1 ;;
  esac
  shift
done

[ -n "$target" ] || { usage >&2; exit 2; }
[ -n "$name" ] || v2_die '--name is required'
[ "$profile" = web ] || v2_die '--profile supports only the built-in web preset'
[ "$cloud" -eq 1 ] || v2_die '--claude-ollama-cloud is required'

if [ "$dry_run" -eq 0 ] && [ "$yes" -ne 1 ]; then
  if [ ! -t 0 ]; then
    v2_die 'non-interactive installation requires --yes or --dry-run'
  fi
  printf 'Plan: install the official CCB web profile for %s into %s. Continue? [y/N] ' "$name" "$target"
  IFS= read -r answer || exit 1
  case "$answer" in y|Y|yes|YES) : ;; *) echo 'Installation cancelled.'; exit 0 ;; esac
fi

v2_preflight "$ROOT"
v2_install_assets "$ROOT" "$target" "$name" "$profile" "$dry_run"

if [ "$dry_run" -eq 1 ]; then
  echo 'DRY RUN — no files were modified.'
else
  cat <<EOF
CCB project prepared: $target

Next steps:
cd $target
ccb config validate
ccb
EOF
fi
