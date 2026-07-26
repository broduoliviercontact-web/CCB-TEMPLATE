#!/bin/sh
set -u
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/project-skills-lib.sh"
usage() { echo 'usage: ccb.sh skills TARGET [--agent generic|codex|claude-code|copilot|opencode|gemini]' >&2; exit "${1:-2}"; }
target= agent=generic
while [ "$#" -gt 0 ]; do case "$1" in --help|-h) usage 0;; --agent) shift; [ "$#" -gt 0 ] || usage 2; agent=$1;; -*) usage 2;; *) [ -z "$target" ] || usage 2; target=$1;; esac; shift; done
[ -n "$target" ] || usage 2
case "$agent" in generic|codex|claude-code|copilot|opencode|gemini) :;; *) echo "error: unsupported agent: $agent" >&2; exit 2;; esac
[ -d "$target" ] && [ ! -L "$target" ] || { echo 'error: target is not a real directory' >&2; exit 1; }
project_skills_parse "$target/.ccb/skills.conf" || { echo 'error: invalid or missing skills.conf' >&2; exit 1; }
printf 'Ponytail\nStatus: %s\nMode: %s\nSource: %s\nRef: %s\n\nRules: active through AGENTS.md\nExternal plugin: optional\n' "$PROJECT_SKILL_PONYTAIL" "$PROJECT_SKILL_PONYTAIL_MODE" "$PROJECT_SKILL_PONYTAIL_SOURCE" "$PROJECT_SKILL_PONYTAIL_REF"
case "$agent" in codex) printf '\nOptional official Codex plugin installation:\n\ncodex plugin marketplace add DietrichGebert/ponytail\ncodex plugin add ponytail@ponytail\n\nReview and trust plugin hooks before using them. Restart afterward.\n';; claude-code) printf '\nOptional Claude Code installation (send separately):\n\n/plugin marketplace add DietrichGebert/ponytail\n/plugin install ponytail@ponytail\n';; generic) :;; *) printf '\nUse AGENTS.md as the portable Ponytail rules source for this agent.\n';; esac
