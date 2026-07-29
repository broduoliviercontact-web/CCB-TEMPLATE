#!/bin/sh

v2_install_one() {
  source=$1 destination=$2 dry_run=$3
  v2_require_safe_path "$destination"
  if [ -e "$destination" ]; then
    v2_info "preserved: $destination"
    return 0
  fi
  if [ "$dry_run" -eq 1 ]; then
    printf '[PLAN] create: %s\n' "$destination"
    return 0
  fi
  parent=$(dirname "$destination")
  mkdir -p "$parent"
  temp=$(mktemp "$parent/.ccb-template.XXXXXX") || v2_die "cannot prepare $destination"
  cp "$source" "$temp" && chmod 600 "$temp" && mv "$temp" "$destination" || { rm -f "$temp"; v2_die "cannot install $destination"; }
  v2_info "installed: $destination"
}

v2_validate_mcp_json() {
  mcp_file=$1
  "$CCB_TEMPLATE_PYTHON" -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    document = json.load(source)
if not isinstance(document, dict):
    raise ValueError("the top-level JSON value must be an object")
servers = document.get("mcpServers")
if servers is not None and not isinstance(servers, dict):
    raise ValueError("mcpServers must be an object")
' "$mcp_file" >/dev/null 2>&1
}

v2_write_tilth_mcp_json() {
  source_file=$1 temporary_file=$2
  "$CCB_TEMPLATE_PYTHON" -c '
import json
import sys

source_path, destination_path = sys.argv[1:]
if source_path == "-":
    document = {}
else:
    with open(source_path, encoding="utf-8") as source:
        document = json.load(source)
if not isinstance(document, dict):
    raise ValueError("the top-level JSON value must be an object")
servers = document.get("mcpServers")
if servers is None:
    servers = {}
    document["mcpServers"] = servers
elif not isinstance(servers, dict):
    raise ValueError("mcpServers must be an object")
servers["tilth"] = {
    "command": "npx",
    "args": ["-y", "tilth@0.9.0", "--mcp"],
}
with open(destination_path, "w", encoding="utf-8", newline="\n") as destination:
    json.dump(document, destination, ensure_ascii=False, indent=2)
    destination.write("\n")
' "$source_file" "$temporary_file"
}

v2_install_tilth_mcp() {
  target=$1 dry_run=$2
  destination=$target/.mcp.json
  v2_require_safe_path "$destination"
  if [ -e "$destination" ] && [ ! -f "$destination" ]; then
    v2_die "MCP configuration must be a regular file: $destination"
  fi
  if [ -e "$destination" ]; then
    v2_validate_mcp_json "$destination" || v2_die "refusing invalid or incompatible MCP configuration: $destination"
    if [ "$dry_run" -eq 1 ]; then
      printf '[PLAN] merge Tilth MCP server: %s\n' "$destination"
      return 0
    fi
    source_file=$destination
    action=updated
  else
    if [ "$dry_run" -eq 1 ]; then
      printf '[PLAN] create Tilth MCP configuration: %s\n' "$destination"
      return 0
    fi
    source_file=-
    action=installed
  fi
  temporary=$(mktemp "$target/.ccb-template-mcp.XXXXXX") || v2_die "cannot prepare $destination"
  v2_write_tilth_mcp_json "$source_file" "$temporary" || { rm -f "$temporary"; v2_die "cannot prepare Tilth MCP configuration: $destination"; }
  chmod 600 "$temporary" && mv "$temporary" "$destination" || { rm -f "$temporary"; v2_die "cannot install $destination"; }
  v2_info "$action Tilth MCP configuration: $destination"
}

v2_install_assets() {
  root=$1 target=$2 name=$3 profile=$4 dry_run=$5 token_optimization=${6:-0} manager_model=${7:-glm-5.2:cloud} graph_model=${8:-qwen3.5:397b-cloud} developer_model=${9:-kimi-k2.7-code:cloud} reviewer_model=${10:-kimi-k2.6:cloud}
  v2_is_safe_name "$name" || v2_die 'project name contains an unsafe line break'
  if [ -e "$target" ]; then target=$(v2_real_dir "$target") || v2_die "target must be a real directory: $target"; else
    parent=$(v2_resolve_existing_dir "$(dirname "$target")") || v2_die "target parent must be an existing directory: $(dirname "$target")"
    target=$parent/$(basename "$target")
    if [ "$dry_run" -eq 1 ]; then
      printf '[PLAN] create target: %s\n' "$target"
    else
      mkdir "$target" || v2_die "cannot create target: $target"
      target=$(v2_real_dir "$target") || v2_die "cannot create target: $target"
    fi
  fi
  for path in "$target/.ccb" "$target/.ccb/agents" "$target/.ccb/ccb.config" \
    "$target/.ccb/agents/manager" "$target/.ccb/agents/graph" \
    "$target/.ccb/agents/developer" "$target/.ccb/agents/reviewer" \
    "$target/CLAUDE.md" "$target/.claude" "$target/.claude/skills"; do
    v2_require_safe_path "$path"
  done
  if [ "$token_optimization" -eq 1 ]; then
    v2_require_safe_path "$target/.mcp.json"
    v2_require_safe_path "$target/.claude"
    v2_require_safe_path "$target/.claude/rules"
    v2_require_safe_path "$target/.claude/rules/token-optimization.md"
    if [ -e "$target/.mcp.json" ]; then
      v2_validate_mcp_json "$target/.mcp.json" || v2_die "refusing invalid or incompatible MCP configuration: $target/.mcp.json"
    fi
  fi
  if [ -e "$target/.ccb/ccb.config" ]; then v2_die "refusing to overwrite existing CCB configuration: $target/.ccb/ccb.config"; fi
  config_dir=$target/.ccb
  if [ "$dry_run" -eq 1 ]; then
    rendered=$(mktemp "${TMPDIR:-/tmp}/ccb-config.XXXXXX") || v2_die 'cannot render configuration'
    trap 'rm -f "$rendered"' EXIT HUP INT TERM
    v2_render_config "$rendered" "$name" "$profile" "$manager_model" "$graph_model" "$developer_model" "$reviewer_model"
    printf '[PLAN] create: %s\n' "$config_dir/ccb.config"
    rm -f "$rendered"; trap - EXIT HUP INT TERM
  else
    mkdir -p "$config_dir" "$config_dir/agents"
    rendered=$(mktemp "$config_dir/.ccb.config.XXXXXX") || v2_die 'cannot render configuration'
    trap 'rm -f "$rendered"' EXIT HUP INT TERM
    v2_render_config "$rendered" "$name" "$profile" "$manager_model" "$graph_model" "$developer_model" "$reviewer_model"
    chmod 600 "$rendered"
    mv "$rendered" "$config_dir/ccb.config"
    trap - EXIT HUP INT TERM
    v2_info "installed: $config_dir/ccb.config"
  fi
  for asset in AGENT_POLICY.md ccb_memory.md \
    agents/manager/memory.md agents/graph/memory.md agents/developer/memory.md agents/reviewer/memory.md \
    agents/manager/CLAUDE.md agents/graph/CLAUDE.md agents/developer/CLAUDE.md agents/reviewer/CLAUDE.md; do
    v2_install_one "$root/assets/$asset" "$config_dir/$asset" "$dry_run"
  done
  v2_install_one "$root/assets/CLAUDE.md" "$target/CLAUDE.md" "$dry_run"
  for skill in ccb-manager-planning ccb-graph-analysis ccb-developer-delivery ccb-reviewer-audit; do
    v2_install_one "$root/assets/skills/$skill/SKILL.md" "$target/.claude/skills/$skill/SKILL.md" "$dry_run"
  done
  if [ "$token_optimization" -eq 1 ]; then
    v2_install_tilth_mcp "$target" "$dry_run"
    v2_install_one "$root/assets/token-optimization.md" "$target/.claude/rules/token-optimization.md" "$dry_run"
  fi
}
