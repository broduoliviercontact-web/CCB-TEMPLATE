#!/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
INSTALL="$SCRIPT_DIR/install-project.sh"
VALIDATE="$SCRIPT_DIR/validate-ccb.sh"
DOCTOR="$SCRIPT_DIR/doctor.sh"
MODEL_SETUP="$SCRIPT_DIR/model-setup.sh"
MODEL_RESOLVE="$SCRIPT_DIR/model-resolve.sh"
MODEL_PRESETS="$TEMPLATE_ROOT/model-presets"
PROFILE_ROOT="$TEMPLATE_ROOT/profiles"

. "$SCRIPT_DIR/profile-lib.sh"
. "$SCRIPT_DIR/mascot-lib.sh"
. "$SCRIPT_DIR/model-lib.sh"

usage() {
  cat <<'EOF'
usage: ./scripts/ccb.sh [--ascii] <command> [arguments]

Commands:
  doctor [TARGET]                 Diagnose a project
  validate [TARGET]               Validate a project
  install [TARGET] [OPTIONS]      Delegate installation to install-project.sh
  setup [TARGET] [OPTIONS]        Guided setup; use --yes for non-interactive install
  profiles                        List local profiles
  profile show ID                 Show one profile
  status [TARGET]                 Show concise project status
  version                         Print the CCB template version
  mascots                         List original session mascots
  mascot show ID                  Render a mascot
  mascot moods ID|--all           List supported moods
  models [show|list|validate|recommendations|setup|reset]
  help                            Show this help

With no command, open the interactive CCB Control Room.
EOF
}

models_command() {
  subcommand=${1:-show}; shift || :
  target=${1:-.}
  case "$subcommand" in
    presets) for preset in "$MODEL_PRESETS"/*; do [ -d "$preset" ] && model_preset_parse "$preset/preset.conf" && printf '%s\t%s\n' "$PRESET_ID" "$PRESET_NAME"; done ;;
    preset)
      [ "${1:-}" = show ] && [ -n "${2:-}" ] || { echo 'error: usage: models preset show ID' >&2; return 2; }
      model_preset_is_safe "$2" && model_preset_parse "$MODEL_PRESETS/$2/preset.conf" && [ "$PRESET_ID" = "$2" ] || { echo "error: unknown preset: $2" >&2; return 1; }
      printf 'Name: %s\nDescription: %s\nManager: %s\nGraph: %s\nGraphiste: %s\nDeveloper: %s\nReviewer: %s\nFallback: %s\n' "$PRESET_NAME" "$PRESET_DESCRIPTION" "$MANAGER_MODEL" "$GRAPH_MODEL" "$GRAPHISTE_MODEL" "$DEVELOPER_MODEL" "$REVIEWER_MODEL" "$FALLBACK_MODEL" ;;
    resolve) exec "$MODEL_RESOLVE" "${1:-}" "${2:-.}" ;;
    list)
      if command -v ollama >/dev/null 2>&1; then ollama list | awk 'NR > 1 { print $1 }'; else echo '[WARN] Ollama was not detected. Recommendations remain available.'; fi ;;
    recommendations) model_recommendations ;;
    show|validate)
      file="$target/.ccb/models.conf"
      if models_conf_validate "$file"; then
        [ "$subcommand" = validate ] && echo '[OK] models.conf is valid' || sed '/API_KEY\|TOKEN\|SECRET/d' "$file"
      else echo "error: invalid or missing models.conf: $file" >&2; return 1; fi ;;
    setup) exec "$MODEL_SETUP" "$@" ;;
    reset) echo 'error: reset requires interactive model setup; existing configuration was preserved.' >&2; return 2 ;;
    *) echo "error: unknown models command: $subcommand" >&2; return 2 ;;
  esac
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
  SESSION_MOOD=${CCB_MASCOT_MOOD:-neutral}
  mascot_mood_is_valid "$SESSION_MOOD" || SESSION_MOOD=neutral
  banner
  printf 'Mascot: %s\n' "$(mascot_name "$SESSION_MASCOT")"
  mascot_render_mood "$SESSION_MASCOT" "$SESSION_MOOD" "$SESSION_ASCII"
  while :; do
    cat <<'EOF'
╔══════════════ CCB CONTROL ROOM ══════════════╗
║ [1] Installation guidée                       ║
║ [2] Installation rapide                       ║
║ [3] Diagnostiquer un projet                   ║
║ [4] Valider un projet                         ║
║ [5] Voir les profils                          ║
║ [6] Galerie des mascottes                     ║
║ [7] Aide                                      ║
║ [Q] Quitter                                   ║
╚══════════════════════════════════════════════╝
EOF
    printf 'Selection: '
    IFS= read -r choice || { echo; mascot_render_mood "$SESSION_MASCOT" goodbye "$SESSION_ASCII"; echo 'CCB session closed.'; return 0; }
    case "$choice" in
      1) setup_wizard ;;
      2) interactive_install ;;
      3) printf 'Target path [.]: '; IFS= read -r target || return 0; "$DOCTOR" "${target:-.}" ;;
      4) printf 'Target path [.]: '; IFS= read -r target || return 0; "$VALIDATE" "${target:-.}" ;;
      5) list_profiles ;;
      6) "$0" mascots ;;
      7) usage ;;
      q|Q) mascot_render_mood "$SESSION_MASCOT" goodbye "$SESSION_ASCII"; echo 'CCB session closed.'; return 0 ;;
      *) echo 'Unknown selection. Choose 1-6 or Q.' ;;
    esac
  done
}

setup_wizard() {
  printf '%s\n' 'Step 1/8 — Guided Setup: no file will change before confirmation.'
  printf '[C] Continue  [Q] Quit: '; IFS= read -r answer || return 0
  case "$answer" in q|Q) return 0;; c|C) :;; *) echo 'Setup cancelled.'; return 0;; esac
  printf '%s\n' 'Step 2/8 — Existing project only in this guided flow.'
  printf 'Target path: '; IFS= read -r target || return 0
  [ -d "$target" ] || { echo 'ERROR: target directory is not accessible.'; return 1; }
  target=$(CDPATH= cd "$target" && pwd)
  printf '%s\n' 'Step 4/8 — Pre-check'
  command -v git >/dev/null 2>&1 || { echo 'ERROR: Git is required.'; return 1; }
  git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo 'ERROR: target is not a Git repository.'; return 1; }
  printf '%s\n' 'Step 5/8 — Choose a profile'; list_profiles
  printf 'Profile [generic]: '; IFS= read -r profile || return 0; profile=${profile:-generic}
  show_profile "$profile" >/dev/null || { echo 'ERROR: unknown profile.'; return 1; }
  printf 'Step 6/8 — Would run: %s "%s" --profile %s\n' "$INSTALL" "$target" "$profile"
  "$INSTALL" "$target" --profile "$profile" --dry-run || return $?
  printf 'Step 7/8 — Proceed with installation? [y/N] '; IFS= read -r answer || return 0
  case "$answer" in y|Y|yes|YES) "$INSTALL" "$target" --profile "$profile" || return $?;; *) echo 'Installation cancelled.'; return 0;; esac
  printf '%s\n' 'Step 8/8 — Validation'; "$VALIDATE" "$target" && "$DOCTOR" "$target"
}

setup_command() {
  shift
  target= profile=generic yes=0 dry=0 update=0
  while [ "$#" -gt 0 ]; do
    case "$1" in --profile) shift; [ "$#" -gt 0 ] || return 2; profile=$1;; --yes) yes=1;; --dry-run) dry=1;; --update) update=1;; -*) return 2;; *) [ -z "$target" ] || return 2; target=$1;; esac
    shift
  done
  [ -n "$target" ] || { setup_wizard; return $?; }
  if [ "$dry" -eq 1 ]; then "$INSTALL" "$target" --profile "$profile" --dry-run; return $?; fi
  if [ "$yes" -ne 1 ]; then
    if [ ! -t 0 ]; then echo 'error: setup without --yes requires an interactive terminal' >&2; return 2; fi
    printf 'Proceed with setup? [y/N] '; IFS= read -r answer || return 0; case "$answer" in y|Y|yes|YES);; *) echo 'Installation cancelled.'; return 0;; esac
  fi
  if [ "$update" -eq 1 ]; then "$INSTALL" "$target" --profile "$profile" --update; else "$INSTALL" "$target" --profile "$profile"; fi
}

MASCOT_OPTION=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ascii) CCB_ASCII=1; shift ;;
    --no-animation) CCB_NO_ANIMATION=1; MASCOT_OPTION=1; shift ;;
    --mood) shift; [ "$#" -gt 0 ] || { usage >&2; exit 2; }; mascot_mood_is_valid "$1" || { echo "error: invalid mood: $1" >&2; exit 2; }; CCB_MASCOT_MOOD=$1; MASCOT_OPTION=1; shift ;;
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
  mascots) printf '%-14s %s\n' ID Name; for mascot in terminal-bot radio-bot synth-bot server-bot space-bot; do printf '%-14s %s\n' "$mascot" "$(mascot_name "$mascot")"; done ;;
  mascot)
    case "${2:-}" in
      show) [ "$#" -eq 3 ] && mascot_is_valid "$3" || { echo "error: unknown mascot: ${3:-}" >&2; exit 1; }; mascot_render_mood "$3" neutral "${CCB_ASCII:-0}" ;;
      moods) if [ "${3:-}" = --all ]; then mascot_moods; else [ "$#" -eq 3 ] && mascot_is_valid "$3" || { echo "error: unknown mascot: ${3:-}" >&2; exit 1; }; mascot_moods; fi ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  models) shift; models_command "$@"; exit $? ;;
  profiles) [ "$#" -eq 1 ] || { usage >&2; exit 2; }; list_profiles ;;
  profile)
    [ "${2:-}" = show ] && [ "$#" -eq 3 ] || { usage >&2; exit 2; }
    show_profile "$3" || { echo "error: unknown profile: $3" >&2; exit 1; }
    ;;
  doctor) shift; exec "$DOCTOR" "$@" ;;
  validate) shift; exec "$VALIDATE" "$@" ;;
  install) shift; exec "$INSTALL" "$@" ;;
  setup|wizard) setup_command "$@"; exit $? ;;
  status) shift; [ "$#" -le 1 ] || { usage >&2; exit 2; }; status "${1:-.}" ;;
  *) echo "error: unknown command: $1" >&2; usage >&2; exit 2 ;;
esac
