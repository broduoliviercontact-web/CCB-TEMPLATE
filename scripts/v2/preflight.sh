#!/bin/sh

v2_version_at_least() {
  actual=$1 minimum=$2
  awk -v actual="$actual" -v minimum="$minimum" 'BEGIN {
    split(actual, a, "."); split(minimum, b, ".");
    for (i = 1; i <= 3; i++) { x = a[i] + 0; y = b[i] + 0; if (x > y) exit 0; if (x < y) exit 1 }
    exit 0
  }'
}

v2_python_version_supported() {
  awk -v version="$1" 'BEGIN {
    if (version !~ /^[0-9]+\.[0-9]+$/) exit 1
    split(version, parts, ".")
    exit !((parts[1] + 0 > 3) || (parts[1] + 0 == 3 && parts[2] + 0 >= 10))
  }'
}

v2_try_python() {
  candidate=$1
  [ -x "$candidate" ] || { v2_warn "Python candidate rejected: $candidate (not executable)"; return 1; }
  version=$($candidate -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null) || {
    v2_warn "Python candidate rejected: $candidate (cannot run version check)"
    return 1
  }
  v2_python_version_supported "$version" || {
    v2_warn "Python candidate rejected: $candidate (requires Python 3.10+, found $version)"
    return 1
  }
  "$candidate" -c 'import importlib.util; assert importlib.util.find_spec("tomllib") or importlib.util.find_spec("tomli"); assert importlib.util.find_spec("aiohttp"); assert importlib.util.find_spec("cryptography")' >/dev/null 2>&1 || {
    v2_warn "Python candidate rejected: $candidate (missing tomllib/tomli, aiohttp, or cryptography)"
    return 1
  }
  CCB_TEMPLATE_PYTHON=$candidate
  export CCB_TEMPLATE_PYTHON
  v2_info "Python: $candidate ($version)"
  return 0
}

v2_select_python() {
  if [ -n "${CCB_PYTHON:-}" ]; then
    v2_try_python "$CCB_PYTHON" && return 0
  fi
  for candidate_name in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
    candidate=$(command -v "$candidate_name" 2>/dev/null || true)
    [ -n "$candidate" ] || continue
    v2_try_python "$candidate" && return 0
  done
  v2_die 'no compatible Python found; install Python 3.10+ with tomllib/tomli, aiohttp, and cryptography, or set CCB_PYTHON'
}

v2_doctor_state=0
v2_doctor_cloud_models=

v2_doctor_emit() {
  state=$1 message=$2
  printf '[%s] %s\n' "$state" "$message"
  [ "$state" = MISSING ] && v2_doctor_state=1
  return 0
}

v2_doctor_command_path() {
  command -v "$1" 2>/dev/null || true
}

v2_doctor_parse_ccb_version() {
  sed -n 's/.*v\{0,1\}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | sed -n '1p'
}

v2_doctor_try_python() {
  candidate=$1
  [ -x "$candidate" ] || return 1
  version=$($candidate -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null) || return 1
  v2_python_version_supported "$version" || return 1
  "$candidate" -c 'import importlib.util; assert importlib.util.find_spec("tomllib") or importlib.util.find_spec("tomli"); assert importlib.util.find_spec("aiohttp"); assert importlib.util.find_spec("cryptography")' >/dev/null 2>&1 || return 1
  CCB_TEMPLATE_PYTHON=$candidate
  export CCB_TEMPLATE_PYTHON
  printf '%s (%s)\n' "$candidate" "$version"
  return 0
}

v2_doctor_check_python() {
  if [ -n "${CCB_PYTHON:-}" ]; then
    if detail=$(v2_doctor_try_python "$CCB_PYTHON"); then
      v2_doctor_emit OK "Python 3.10+ with tomllib/tomli, aiohttp and cryptography: $detail"
      return 0
    fi
  fi
  for candidate_name in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
    candidate=$(v2_doctor_command_path "$candidate_name")
    [ -n "$candidate" ] || continue
    if detail=$(v2_doctor_try_python "$candidate"); then
      v2_doctor_emit OK "Python 3.10+ with tomllib/tomli, aiohttp and cryptography: $detail"
      return 0
    fi
  done
  v2_doctor_emit MISSING 'Python 3.10+ with tomllib/tomli, aiohttp and cryptography is required; install dependencies or set CCB_PYTHON'
  return 1
}

v2_doctor_check_standard() {
  root=$1
  v2_doctor_state=0
  v2_doctor_cloud_models=

  system=$(uname -s 2>/dev/null || true)
  case "$system" in
    Darwin|Linux|FreeBSD) v2_doctor_emit OK "platform: $system" ;;
    *) v2_doctor_emit MISSING "unsupported platform: ${system:-unknown}; use macOS or a Unix-compatible environment" ;;
  esac

  tmux_bin=$(v2_doctor_command_path tmux)
  [ -n "$tmux_bin" ] && v2_doctor_emit OK "tmux: $tmux_bin" || v2_doctor_emit MISSING 'tmux is required; install it with your system package manager'

  git_bin=$(v2_doctor_command_path git)
  [ -n "$git_bin" ] && v2_doctor_emit OK "git: $git_bin" || v2_doctor_emit MISSING 'git is required to initialise generated projects'

  v2_doctor_check_python || :

  ccb_bin=$(v2_doctor_command_path ccb)
  if [ -z "$ccb_bin" ]; then
    v2_doctor_emit MISSING 'official ccb is required; install @seemseam/ccb@latest globally'
  else
    ccb_bin=$(CDPATH= cd "$(dirname "$ccb_bin")" && pwd)/$(basename "$ccb_bin")
    if v2_path_is_within "$ccb_bin" "$root"; then
      v2_doctor_emit MISSING "official ccb must not resolve to this repository: $ccb_bin"
    else
      ccb_version=$($ccb_bin --version 2>&1 | v2_doctor_parse_ccb_version)
      if [ -z "$ccb_version" ]; then
        v2_doctor_emit MISSING "cannot determine official ccb version: $ccb_bin"
      elif v2_version_at_least "$ccb_version" 8.4.3; then
        v2_doctor_emit OK "official ccb: $ccb_bin (v$ccb_version)"
      else
        v2_doctor_emit MISSING "official ccb 8.4.3+ is required; found $ccb_version at $ccb_bin"
      fi
    fi
  fi

  claude_bin=$(v2_doctor_command_path claude)
  [ -n "$claude_bin" ] && v2_doctor_emit OK "Claude Code CLI: $claude_bin" || v2_doctor_emit MISSING 'Claude Code CLI is required; install the official Claude Code CLI'

  ollama_bin=$(v2_doctor_command_path ollama)
  if [ -z "$ollama_bin" ]; then
    v2_doctor_emit MISSING 'Ollama is required; install Ollama and start its local server'
  else
    if models=$(ollama list 2>/dev/null); then
      v2_doctor_cloud_models=$(printf '%s\n' "$models" | awk 'NR > 1 && $1 ~ /:.*cloud$/ { print $1 }')
      if [ -n "$v2_doctor_cloud_models" ]; then
        count=$(printf '%s\n' "$v2_doctor_cloud_models" | sed '/^$/d' | wc -l | awk '{ print $1 }')
        v2_doctor_emit OK "Ollama reachable with $count Cloud model(s)"
      else
        v2_doctor_emit MISSING 'at least one installed Ollama Cloud model ending in :cloud is required'
      fi
    else
      v2_doctor_emit MISSING 'Ollama server is not reachable; start Ollama and retry'
    fi
  fi

  return "$v2_doctor_state"
}

v2_doctor_check_full() {
  root=$1
  v2_doctor_check_standard "$root" || :

  rtk_bin=$(v2_doctor_command_path rtk)
  [ -n "$rtk_bin" ] && v2_doctor_emit OK "optional RTK: $rtk_bin" || v2_doctor_emit WARNING 'optional RTK is unavailable; --token-optimization will be skipped unless RTK is installed and initialized by the user'

  npx_bin=$(v2_doctor_command_path npx)
  [ -n "$npx_bin" ] && v2_doctor_emit OK "optional npx: $npx_bin" || v2_doctor_emit WARNING 'optional npx is unavailable; Tilth MCP cannot be configured without Node.js/npm'

  if [ -n "$npx_bin" ]; then
    if command -v npm >/dev/null 2>&1 && npm view --offline tilth@0.9.0 version >/dev/null 2>&1; then
      v2_doctor_emit OK 'optional Tilth package tilth@0.9.0 is available in the local npm cache for the configured npx MCP command'
    else
      v2_doctor_emit WARNING 'optional Tilth package was not verified locally; doctor does not run npx -y, use the network or install packages'
    fi
  fi

  [ -f "$root/assets/token-proxy.py" ] && [ ! -L "$root/assets/token-proxy.py" ] && \
    v2_doctor_emit OK 'optional local monitoring proxy asset is present' || \
    v2_doctor_emit WARNING 'optional local monitoring proxy asset is unavailable'
  [ -f "$root/assets/token-pricing.json" ] && [ ! -L "$root/assets/token-pricing.json" ] && \
    v2_doctor_emit OK 'optional local monitoring pricing template is present' || \
    v2_doctor_emit WARNING 'optional local monitoring pricing template is unavailable'

  return "$v2_doctor_state"
}

v2_preflight() {
  root=$1 token_optimization=${2:-0} manager_model=${3:-glm-5.2:cloud} graph_model=${4:-qwen3.5:397b-cloud} developer_model=${5:-kimi-k2.7-code:cloud} reviewer_model=${6:-kimi-k2.6:cloud}
  system=$(uname -s 2>/dev/null || true)
  case "$system" in Darwin|Linux|FreeBSD) v2_info "platform: $system" ;; *) v2_die "unsupported platform: ${system:-unknown}; use macOS or a Unix-compatible environment" ;; esac
  command -v tmux >/dev/null 2>&1 || v2_die 'tmux is required; install it with your system package manager'
  v2_info "tmux: $(command -v tmux)"
  v2_select_python

  ccb_bin=$(command -v ccb 2>/dev/null || true)
  [ -n "$ccb_bin" ] || v2_die 'official ccb is required; install @seemseam/ccb@latest globally'
  ccb_bin=$(CDPATH= cd "$(dirname "$ccb_bin")" && pwd)/$(basename "$ccb_bin")
  v2_path_is_within "$ccb_bin" "$root" && v2_die "refusing repository-local ccb binary: $ccb_bin"
  ccb_version=$($ccb_bin --version 2>&1 | sed -n 's/.*v\([0-9][0-9.]*\).*/\1/p' | sed -n '1p')
  [ -n "$ccb_version" ] || v2_die "cannot determine official ccb version: $ccb_bin"
  v2_version_at_least "$ccb_version" 8.4.3 || v2_die "official ccb 8.4.3+ is required; found $ccb_version at $ccb_bin"
  v2_info "official ccb: $ccb_bin (v$ccb_version)"

  command -v claude >/dev/null 2>&1 || v2_die 'Claude Code is required; install the official Claude Code CLI'
  v2_info "Claude Code: $(command -v claude)"
  command -v ollama >/dev/null 2>&1 || v2_die 'Ollama is required; install Ollama and start its local server'
  models=$(ollama list 2>/dev/null) || v2_die 'Ollama server is not reachable; start Ollama and retry'
  for model in "$manager_model" "$graph_model" "$developer_model" "$reviewer_model"; do
    v2_is_cloud_model "$model" || v2_die "invalid Ollama Cloud model: $model"
    printf '%s\n' "$models" | awk 'NR > 1 { print $1 }' | grep -Fqx "$model" || v2_die "Ollama Cloud model is unavailable: $model"
  done
  v2_info 'Ollama server and selected Cloud models: available'

  if [ "$token_optimization" -eq 1 ]; then
    command -v rtk >/dev/null 2>&1 || v2_die "$(printf '%s\n%s\n%s\n%s' \
      'RTK is required with --token-optimization. On macOS run:' \
      'brew install rtk-ai/tap/rtk' \
      'rtk init -g' \
      'The bootstrap never installs or initializes RTK for you.')"
    v2_info "RTK: $(command -v rtk)"
    command -v npx >/dev/null 2>&1 || v2_die 'npx is required with --token-optimization to launch the project Tilth MCP server; install Node.js/npm so npx is available'
    v2_info "npx: $(command -v npx)"
  fi
}
