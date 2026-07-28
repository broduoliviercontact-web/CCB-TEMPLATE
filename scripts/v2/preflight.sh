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

v2_preflight() {
  root=$1
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
  for model in glm-5.2:cloud qwen3.5:397b-cloud gemma4:31b-cloud kimi-k2.7-code:cloud deepseek-v4-pro:cloud; do
    printf '%s\n' "$models" | awk 'NR > 1 { print $1 }' | grep -Fqx "$model" || v2_die "Ollama Cloud model is unavailable: $model"
  done
  v2_info 'Ollama server and five required Cloud models: available'
}
