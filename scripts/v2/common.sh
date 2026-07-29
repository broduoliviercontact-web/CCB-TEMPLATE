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
