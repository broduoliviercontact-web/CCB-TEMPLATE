#!/bin/sh
set -u
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/model-lib.sh"
. "$SCRIPT_DIR/project-profile-lib.sh"
. "$SCRIPT_DIR/project-config-lib.sh"
. "$SCRIPT_DIR/project-skills-lib.sh"
. "$SCRIPT_DIR/project-agents-lib.sh"
. "$SCRIPT_DIR/project-workflows-lib.sh"

usage() { echo 'usage: ccb.sh config TARGET' >&2; exit "${1:-2}"; }
[ "$#" -eq 1 ] || usage 2
target=$1
[ -d "$target" ] && [ ! -L "$target" ] || { echo 'error: target is not a real directory' >&2; exit 1; }
target=$(CDPATH= cd "$target" && pwd) || exit 1
project_conf_parse "$target/.ccb/project.conf" || { echo 'error: invalid or missing project.conf' >&2; exit 1; }
project_models_parse "$target/.ccb/models.conf" || { echo 'error: invalid or missing models.conf' >&2; exit 1; }
if project_skills_parse "$target/.ccb/skills.conf"; then
  skills_output=$(printf 'Ponytail: %s\nPonytail mode: %s\nPonytail source: %s\nPonytail ref: %s\n' "$PROJECT_SKILL_PONYTAIL" "$PROJECT_SKILL_PONYTAIL_MODE" "$PROJECT_SKILL_PONYTAIL_SOURCE" "$PROJECT_SKILL_PONYTAIL_REF")
else
  template_version=$(awk -F= '$1=="CCB_TEMPLATE_VERSION" {print $2}' "$target/.ccb/project.conf")
  [ "$template_version" = 1.6.0 ] || { echo 'error: invalid or missing skills.conf' >&2; exit 1; }
  skills_output='Ponytail: not configured'
fi
if project_agents_parse "$target/.ccb/agents.conf"; then
  agents_output=$(printf 'Agents:\n  Schema: %s\n  Roles: %s\n  Default: %s\n  Read-only: manager,graph,reviewer\n  Write: graphiste,developer\n  Enforcement: declarative only' "$PROJECT_AGENTS_VERSION" "$PROJECT_AGENT_ROLES" "$PROJECT_AGENT_DEFAULT")
else
  template_version=$(awk -F= '$1=="CCB_TEMPLATE_VERSION" {print $2}' "$target/.ccb/project.conf")
  case "$template_version" in 1.6.0|1.6.1) agents_output=$(printf 'Agents:\n  Status: not configured\n  Project template: %s\n  Upgrade required for V1.7.0 agents' "$template_version");; *) echo 'error: invalid or missing agents.conf' >&2; exit 1;; esac
fi
if project_workflows_parse "$target/.ccb/workflows.conf"; then workflows_output=$(printf 'Workflows:\n  Schema: %s\n  Names: %s\n  Default: %s\n  Execution: disabled\n  Enforcement: declarative only' "$PROJECT_WORKFLOWS_VERSION" "$PROJECT_WORKFLOW_NAMES" "$PROJECT_WORKFLOW_DEFAULT"); else workflows_output='Workflows:
  Status: not configured
  Project template: 1.7.0
  Capability: declarative workflows unavailable'; fi
printf 'Project: %s\nProfile: %s\nProvider: %s\nDefault model: %s\nPlanner model: %s\nCoder model: %s\nReviewer model: %s\n%s\n%s\n%s\n' "$PROJECT_NAME" "$PROJECT_PROFILE" "$PROJECT_MODEL_PROVIDER" "$PROJECT_MODEL_DEFAULT" "$PROJECT_MODEL_PLANNER" "$PROJECT_MODEL_CODER" "$PROJECT_MODEL_REVIEWER" "$skills_output" "$agents_output" "$workflows_output"
