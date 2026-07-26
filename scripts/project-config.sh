#!/bin/sh
set -u
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/model-lib.sh"
. "$SCRIPT_DIR/project-profile-lib.sh"
. "$SCRIPT_DIR/project-config-lib.sh"

usage() { echo 'usage: ccb.sh config TARGET' >&2; exit "${1:-2}"; }
[ "$#" -eq 1 ] || usage 2
target=$1
[ -d "$target" ] && [ ! -L "$target" ] || { echo 'error: target is not a real directory' >&2; exit 1; }
target=$(CDPATH= cd "$target" && pwd) || exit 1
project_conf_parse "$target/.ccb/project.conf" || { echo 'error: invalid or missing project.conf' >&2; exit 1; }
project_models_parse "$target/.ccb/models.conf" || { echo 'error: invalid or missing models.conf' >&2; exit 1; }
printf 'Project: %s\nProfile: %s\nProvider: %s\nDefault model: %s\nPlanner model: %s\nCoder model: %s\nReviewer model: %s\n' "$PROJECT_NAME" "$PROJECT_PROFILE" "$PROJECT_MODEL_PROVIDER" "$PROJECT_MODEL_DEFAULT" "$PROJECT_MODEL_PLANNER" "$PROJECT_MODEL_CODER" "$PROJECT_MODEL_REVIEWER"
