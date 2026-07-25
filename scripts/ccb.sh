#!/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
INSTALL="$SCRIPT_DIR/install-project.sh"
VALIDATE="$SCRIPT_DIR/validate-ccb.sh"
DOCTOR="$SCRIPT_DIR/doctor.sh"
PROFILE_ROOT="$TEMPLATE_ROOT/profiles"

. "$SCRIPT_DIR/profile-lib.sh"
. "$SCRIPT_DIR/mascot-lib.sh"

usage() {
  cat <<'EOF'
usage: ./scripts/ccb.sh [--ascii] <command> [arguments]

Commands:
  doctor [TARGET]                 Diagnose a project
  validate [TARGET]               Validate a project
  install [TARGET] [OPTIONS]      Delegate installation to install-project.sh
  profiles                        List local profiles
  profile show ID                 Show one profile
  status [TARGET]                 Show concise project status
  version                         Print the CCB template version
  help                            Show this help

With no command, open the interactive CCB Control Room.
EOF
}

list_profiles() {
  printf '%-14s %-18s %s\n' 'ID' 'Name' 'Skills'
  for profile_dir in "$PROFILE_ROOT"/*; do
    [ -d "$profile_dir" ] || continue
    if profile_parse "$profile_dir/profile.conf" && [ "$PROFILE_ID" = "$(basename "$profile_dir")" ]; then
      printf '%-14s %-18s %s\n' "$PROFILE_ID" "$PROFILE_NAME" "$(profile_skill_count "$PROFILE_SKILLS")"
    fi
  done
}

show_profile() {
  requested_id=$1
  profile_id_is_safe "$requested_id" || return 1
  profile_dir="$PROFILE_ROOT/$requested_id"
  if ! profile_parse "$profile_dir/profile.conf" || [ "$PROFILE_ID" != "$requested_id" ]; then
    return 1
  fi
  printf 'Name: %s\nID: %s\nVersion: %s\nDescription: %s\nSkills: %s\nPath: %s\n' \
    "$PROFILE_NAME" "$PROFILE_ID" "$PROFILE_VERSION" "$PROFILE_DESCRIPTION" \
    "${PROFILE_SKILLS:-none}" "$profile_dir"
}

status() {
  target=${1:-.}
  [ -d "$target" ] || { echo "error: target directory does not exist: $target" >&2; return 1; }
  target=$(CDPATH= cd "$target" && pwd)
  printf 'Target: %s\n' "$target"
  if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Branch: %s\n' "$(git -C "$target" branch --show-current 2>/dev/null || printf 'detached')"
    if [ -n "$(git -C "$target" status --porcelain 2>/dev/null)" ]; then echo 'Working tree: modified'; else echo 'Working tree: clean'; fi
  else
    echo 'Git: not a repository'
  fi
  if [ -f "$target/.ccb/active-profile" ]; then printf 'Active profile: %s\n' "$(cat "$target/.ccb/active-profile")"; else echo 'Active profile: none'; fi
  "$DOCTOR" "$target"
}

banner() {
  mascot_animate "$SESSION_MASCOT" "$SESSION_ASCII"
  if [ "${CCB_ASCII:-}" = 1 ] || [ "${CCB_ASCII:-}" = true ]; then
    cat <<'EOF'
+--------------------------------------------------+
|                    C C B                         |
|           CLAUDE CODEX BRIDGE                    |
|             CCB CONTROL ROOM                     |
+--------------------------------------------------+
EOF
  else
    cat <<'EOF'
╔══════════════════════════════════════════════════╗
║                  C C B                           ║
║         C L A U D E  C O D E X  B R I D G E      ║
║             CCB CONTROL ROOM                     ║
╚══════════════════════════════════════════════════╝
EOF
  fi
}

choose_profile() {
  choices=$(mktemp "${TMPDIR:-/tmp}/ccb-profile-choices.XXXXXX") || return 1
  trap 'rm -f "$choices"' EXIT HUP INT TERM
  number=0
  printf '%s\n' 'Choose a profile'
  for profile_dir in "$PROFILE_ROOT"/*; do
    [ -d "$profile_dir" ] || continue
    if profile_parse "$profile_dir/profile.conf" && [ "$PROFILE_ID" = "$(basename "$profile_dir")" ]; then
      number=$((number + 1))
      printf '%s\n' "$PROFILE_ID" >>"$choices"
      printf '[%s] %-14s %s\n' "$number" "$PROFILE_ID" "$PROFILE_DESCRIPTION"
    fi
  done
  printf 'Selection: '
  IFS= read -r selection || { rm -f "$choices"; trap - EXIT HUP INT TERM; return 1; }
  case "$selection" in ''|*[!0-9]*) rm -f "$choices"; trap - EXIT HUP INT TERM; return 1;; esac
  selected_id=$(sed -n "${selection}p" "$choices")
  rm -f "$choices"; trap - EXIT HUP INT TERM
  [ -n "$selected_id" ] || return 1
  printf '%s\n' "$selected_id"
}

interactive_install() {
  printf 'Target path: '
  IFS= read -r target || return 0
  [ -n "$target" ] || { echo 'Cancelled.'; return 0; }
  selected_id=$(choose_profile) || { echo 'Cancelled.'; return 0; }
  show_profile "$selected_id" || return 1
  printf 'Command: %s "%s" --profile %s\n' "$INSTALL" "$target" "$selected_id"
  printf 'Continue? [y/N] '
  IFS= read -r answer || return 0
  case "$answer" in y|Y|yes|YES) "$INSTALL" "$target" --profile "$selected_id";; *) echo 'Cancelled.';; esac
}

interactive() {
  SESSION_ASCII=0
  if [ "${CCB_ASCII:-}" = 1 ] || [ "${CCB_ASCII:-}" = true ]; then SESSION_ASCII=1; fi
  SESSION_MASCOT=$(mascot_select)
  banner
  printf 'Mascot: %s\n' "$(mascot_name "$SESSION_MASCOT")"
  while :; do
    cat <<'EOF'
╔══════════════ CCB CONTROL ROOM ══════════════╗
║ [1] Installer CCB dans un projet              ║
║ [2] Diagnostiquer un projet                   ║
║ [3] Valider un projet                         ║
║ [4] Voir les profils disponibles              ║
║ [5] Afficher le profil actif                  ║
║ [6] Aide                                      ║
║ [Q] Quitter                                   ║
╚══════════════════════════════════════════════╝
EOF
    printf 'Selection: '
    IFS= read -r choice || { echo; return 0; }
    case "$choice" in
      1) interactive_install ;;
      2) printf 'Target path [.]: '; IFS= read -r target || return 0; "$DOCTOR" "${target:-.}" ;;
      3) printf 'Target path [.]: '; IFS= read -r target || return 0; "$VALIDATE" "${target:-.}" ;;
      4) list_profiles ;;
      5) printf 'Target path [.]: '; IFS= read -r target || return 0; status "${target:-.}" ;;
      6) usage ;;
      q|Q) return 0 ;;
      *) echo 'Unknown selection. Choose 1-6 or Q.' ;;
    esac
  done
}

MASCOT_OPTION=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ascii) CCB_ASCII=1; shift ;;
    --no-animation) CCB_NO_ANIMATION=1; MASCOT_OPTION=1; shift ;;
    --mascot)
      shift; [ "$#" -gt 0 ] || { usage >&2; exit 2; }
      if ! mascot_id_is_safe "$1" || ! mascot_is_valid "$1"; then echo "error: invalid mascot: $1" >&2; exit 2; fi
      CCB_MASCOT=$1; MASCOT_OPTION=1; shift ;;
    *) break ;;
  esac
done
if [ "$MASCOT_OPTION" -eq 1 ] && [ "$#" -gt 0 ]; then echo 'error: mascot options require interactive mode' >&2; exit 2; fi
case "${1:-}" in
  '') interactive ;;
  help|--help|-h) usage ;;
  version) cat "$TEMPLATE_ROOT/VERSION" ;;
  profiles) [ "$#" -eq 1 ] || { usage >&2; exit 2; }; list_profiles ;;
  profile)
    [ "${2:-}" = show ] && [ "$#" -eq 3 ] || { usage >&2; exit 2; }
    show_profile "$3" || { echo "error: unknown profile: $3" >&2; exit 1; }
    ;;
  doctor) shift; exec "$DOCTOR" "$@" ;;
  validate) shift; exec "$VALIDATE" "$@" ;;
  install) shift; exec "$INSTALL" "$@" ;;
  status) shift; [ "$#" -le 1 ] || { usage >&2; exit 2; }; status "${1:-.}" ;;
  *) echo "error: unknown command: $1" >&2; usage >&2; exit 2 ;;
esac
