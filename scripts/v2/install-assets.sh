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

v2_install_assets() {
  root=$1 target=$2 name=$3 profile=$4 dry_run=$5
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
    "$target/.ccb/agents/manager" "$target/.ccb/agents/graph" "$target/.ccb/agents/graphiste" \
    "$target/.ccb/agents/developer" "$target/.ccb/agents/reviewer"; do
    v2_require_safe_path "$path"
  done
  if [ -e "$target/.ccb/ccb.config" ]; then v2_die "refusing to overwrite existing CCB configuration: $target/.ccb/ccb.config"; fi
  config_dir=$target/.ccb
  if [ "$dry_run" -eq 1 ]; then
    rendered=$(mktemp "${TMPDIR:-/tmp}/ccb-config.XXXXXX") || v2_die 'cannot render configuration'
    trap 'rm -f "$rendered"' EXIT HUP INT TERM
    v2_render_config "$rendered" "$name" "$profile"
    printf '[PLAN] create: %s\n' "$config_dir/ccb.config"
    rm -f "$rendered"; trap - EXIT HUP INT TERM
  else
    mkdir -p "$config_dir" "$config_dir/agents"
    rendered=$(mktemp "$config_dir/.ccb.config.XXXXXX") || v2_die 'cannot render configuration'
    trap 'rm -f "$rendered"' EXIT HUP INT TERM
    v2_render_config "$rendered" "$name" "$profile"
    chmod 600 "$rendered"
    mv "$rendered" "$config_dir/ccb.config"
    trap - EXIT HUP INT TERM
    v2_info "installed: $config_dir/ccb.config"
  fi
  for asset in AGENT_POLICY.md ccb_memory.md agents/manager/memory.md agents/graph/memory.md agents/graphiste/memory.md agents/developer/memory.md agents/reviewer/memory.md; do
    v2_install_one "$root/assets/$asset" "$config_dir/$asset" "$dry_run"
  done
}
