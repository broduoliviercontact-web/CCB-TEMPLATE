#!/bin/sh

v2_die() { printf 'error: %s\n' "$*" >&2; exit 1; }
v2_info() { printf '[OK] %s\n' "$*"; }
v2_warn() { printf '[WARN] %s\n' "$*" >&2; }

v2_is_safe_name() {
  case "$1" in ''|*"\n"*|*"\r"*) return 1 ;; *) return 0 ;; esac
}

v2_is_cloud_model() {
  case "$1" in
    *"\n"*|*"\r"*|*[!A-Za-z0-9._:-]*|*:) return 1 ;;
    *:*cloud) return 0 ;;
    *) return 1 ;;
  esac
}

v2_is_valid_port() {
  case "$1" in
    *[!0-9]*|'') return 1 ;;
  esac
  [ "$1" -ge 1024 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

v2_select_token_monitor_port() {
  start=${CCB_TOKEN_MONITOR_PORT_START:-11435}
  v2_is_valid_port "$start" || v2_die "invalid token monitor port start: $start"
  "$CCB_TEMPLATE_PYTHON" - "$start" <<'PY'
import socket
import sys

start = int(sys.argv[1])
for port in range(start, 65536):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            continue
        print(port)
        break
else:
    raise SystemExit("no free local TCP port available for token monitoring")
PY
}

v2_real_dir() {
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  (CDPATH= cd "$1" && pwd)
}

v2_resolve_existing_dir() {
  [ -d "$1" ] || return 1
  (CDPATH= cd -P "$1" && pwd)
}

v2_path_is_within() {
  candidate=$1 root=$2
  case "$candidate" in "$root"|"$root"/*) return 0 ;; *) return 1 ;; esac
}

v2_require_safe_path() {
  [ ! -L "$1" ] || v2_die "refusing symbolic link: $1"
}
