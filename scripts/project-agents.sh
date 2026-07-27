#!/bin/sh
set -u
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/model-lib.sh"
. "$SCRIPT_DIR/project-config-lib.sh"
. "$SCRIPT_DIR/project-agents-lib.sh"
usage() { echo 'usage: ccb.sh agents [TARGET] | ccb.sh agent show ROLE [TARGET] | ccb.sh agent validate [TARGET]' >&2; exit "${1:-2}"; }
action=${1:-list}; case "$action" in list|show|validate|--help|-h) :;; *) usage 2;; esac
[ "$action" != --help ] && [ "$action" != -h ] || usage 0
if [ "$action" = show ]; then requested_role=${2:-}; [ -n "$requested_role" ] || usage 2; project_agent_role_is_safe "$requested_role" || { echo "error: invalid agent role: $requested_role" >&2; exit 2; }; target=${3:-.}; [ "$#" -le 3 ] || usage 2; else target=${2:-.}; [ "$#" -le 2 ] || usage 2; fi
[ -d "$target" ] && [ ! -L "$target" ] || { echo 'error: target is not a real directory' >&2; exit 1; }; target=$(CDPATH= cd "$target" && pwd) || exit 1
project_models_parse "$target/.ccb/models.conf" || { echo 'error: invalid or missing models.conf' >&2; exit 1; }
project_agents_parse "$target/.ccb/agents.conf" || { echo 'error: invalid or missing agents.conf' >&2; exit 1; }
if [ "$action" = validate ]; then echo '[OK] agents.conf is valid'; echo '[OK] 5 agent roles are configured'; printf '[OK] default agent role: %s\n' "$PROJECT_AGENT_DEFAULT"; echo '[OK] model references are valid'; echo '[INFO] access enforcement is declarative only'; exit 0; fi
if [ "$action" = show ]; then
  case ",$PROJECT_AGENT_ROLES," in *,"$requested_role",*) :;; *) echo "error: unknown agent role: $requested_role" >&2; echo "Available roles: $PROJECT_AGENT_ROLES" >&2; exit 1;; esac
  project_agent_details "$requested_role"; model=$(project_agent_role_model_value "$requested_role") || exit 1
  printf 'Role: %s\nDescription: %s\nAccess: %s\nEnforcement: declarative only\nModel role: %s\nProvider: %s\nModel: %s\n' "$requested_role" "$PROJECT_AGENT_DESCRIPTION" "$PROJECT_AGENT_ACCESS" "$PROJECT_AGENT_MODEL_ROLE" "$PROJECT_MODEL_PROVIDER" "$model"; exit 0
fi
printf 'CCB Project Agents\nTarget: %s\nSchema: %s\nDefault: %s\nEnforcement: declarative only\n\n%-12s %-12s %-10s %s\n' "$target" "$PROJECT_AGENTS_VERSION" "$PROJECT_AGENT_DEFAULT" ROLE ACCESS PROVIDER MODEL
for role in manager graph graphiste developer reviewer; do project_agent_details "$role"; model=$(project_agent_role_model_value "$role") || exit 1; printf '%-12s %-12s %-10s %s\n' "$role" "$PROJECT_AGENT_ACCESS" "$PROJECT_MODEL_PROVIDER" "$model"; done
