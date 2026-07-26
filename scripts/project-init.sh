#!/bin/sh
set -u
usage() { echo 'usage: ccb.sh init TARGET [--project-name NAME] [--profile generic] [--yes] [--dry-run]' >&2; exit "${1:-2}"; }
target= name= profile=generic yes=0 dry=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage 0;; --project-name) shift; name=${1:-};; --profile) shift; profile=${1:-};; --yes) yes=1;; --dry-run) dry=1;;
    --force|--no-models|--single-model|--description|--non-interactive) echo "error: option not supported in bootstrap init: $1" >&2; exit 2;;
    -*) usage;; *) [ -z "$target" ] || usage; target=$1;;
  esac
  shift
done
[ -n "$target" ] || usage
[ "$profile" = generic ] || { echo "Unsupported bootstrap profile: $profile" >&2; exit 2; }
case "$target" in *..*) echo 'error: unsafe target path' >&2; exit 2;; esac
new=0
if [ ! -e "$target" ]; then new=1; else [ -d "$target" ] && [ ! -L "$target" ] || { echo 'error: target is not a real directory' >&2; exit 2; }; fi
if [ "$new" -eq 1 ] && [ "$yes" -ne 1 ] && [ "$dry" -ne 1 ]; then [ -t 0 ] || { echo 'error: --yes is required to create a new target without a TTY' >&2; exit 2; }; fi
if [ "$new" -eq 1 ]; then base=$(basename "$target"); else target=$(CDPATH= cd "$target" && pwd); base=$(basename "$target"); fi
name=${name:-$base}; [ -n "$name" ] || { echo 'error: invalid project name' >&2; exit 2; }
for path in .ccb/project.conf .ccb/context/project.md AGENTS.md; do [ ! -e "$target/$path" ] || { echo "error: managed file already exists: $path" >&2; exit 1; }; done
printf 'Plan:\n  CREATE %s\n  CREATE .ccb/project.conf\n  CREATE .ccb/context/project.md\n  CREATE AGENTS.md\n' "$target"
if [ "$dry" -eq 1 ]; then echo 'DRY RUN — no files were modified'; exit 0; fi
[ "$new" -eq 0 ] || mkdir -p "$target"
mkdir -p "$target/.ccb/context"
printf 'CCB_PROJECT_NAME=%s\nCCB_PROJECT_PROFILE=generic\nCCB_PROJECT_VERSION=1\nCCB_TEMPLATE_VERSION=1.6.0\n' "$name" >"$target/.ccb/project.conf"
chmod 644 "$target/.ccb/project.conf"
printf '# Project context\n\nProject: %s\nProfile: generic\n' "$name" >"$target/.ccb/context/project.md"
printf '# Agent guidance\n\nRead .ccb/context/project.md before modifying files. Follow project safety conventions.\n' >"$target/AGENTS.md"
echo "CCB bootstrap initialized: $target"
