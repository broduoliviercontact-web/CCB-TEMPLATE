#!/bin/sh

mascot_id_is_safe() { case "$1" in ''|*[!a-z0-9-]*) return 1;; *) return 0;; esac; }
mascot_is_valid() { case "$1" in terminal-bot|radio-bot|synth-bot|server-bot|space-bot) return 0;; *) return 1;; esac; }
mascot_name() { case "$1" in terminal-bot) echo 'Terminal Bot';; radio-bot) echo 'Radio Bot';; synth-bot) echo 'Synth Bot';; server-bot) echo 'Server Bot';; space-bot) echo 'Space Bot';; esac; }
mascot_select() {
  request=${CCB_MASCOT:-}
  if [ -n "$request" ]; then
    if mascot_id_is_safe "$request" && mascot_is_valid "$request"; then printf '%s\n' "$request"; return; fi
    printf '%s\n' "[WARN] Unknown mascot '$request'; selecting a local mascot." >&2
  fi
  seed=${CCB_MASCOT_SEED:-}
  case "$seed" in ''|*[!0-9]*) seed="$(date +%s 2>/dev/null || printf 0)$$";; esac
  case "$(awk -v value="$seed" 'BEGIN { print (value % 5) + 1 }')" in 1) echo terminal-bot;; 2) echo radio-bot;; 3) echo synth-bot;; 4) echo server-bot;; *) echo space-bot;; esac
}
mascot_render_frame() {
  id=$1; frame=$2; ascii=$3
  case "$id:$frame:$ascii" in
    terminal-bot:1:1) printf '%s\n' '  +-------+' '  | o o   |' '  |   -   |' '  +-+---+-+' '    |CCB|' '    +---+';;
    terminal-bot:*:1) printf '%s\n' '  +-------+' '  | o -   |' '  |   -   |' '  +-+---+-+' '    |CCB|' '    +---+';;
    radio-bot:1:1) printf '%s\n' '    .-.-.' '  +-------+' '  | o ~ o |' '  +--RAD--+';; radio-bot:*:1) printf '%s\n' '    .-^-.' '  +-------+' '  | o = o |' '  +--RAD--+';;
    synth-bot:1:1) printf '%s\n' '  +--SYNTH--+' '  | o  _  o |' '  | [=|=|=] |' '  +---------+';; synth-bot:*:1) printf '%s\n' '  +--SYNTH--+' '  | o  ~  o |' '  | [=|=|=] |' '  +---------+';;
    server-bot:1:1) printf '%s\n' '  +-------+' '  | [*]   |' '  | [.]   |' '  | [*]   |' '  +-------+';; server-bot:*:1) printf '%s\n' '  +-------+' '  | [.]   |' '  | [*]   |' '  | [.]   |' '  +-------+';;
    space-bot:1:1) printf '%s\n' '     .' '   .-^-.' '  / CCB \' '  | o o |' '  +-----+';; space-bot:*:1) printf '%s\n' '     *' '   .-^-.' '  / CCB \' '  | o - |' '  +-----+';;
    terminal-bot:1:0) printf '%s\n' '  ┌───────┐' '  │  ■ ■  │' '  │   ▰   │' '  └─┬───┬─┘' '    │CCB│' '    └───┘';;
    radio-bot:1:0) printf '%s\n' '    ╭─⌁─╮' '  ┌───────┐' '  │ ■ ~ ■ │' '  └─ RADIO┘';;
    synth-bot:1:0) printf '%s\n' '  ┌─ SYNTH ─┐' '  │ ■ 〰  ■ │' '  │ ▰ ▰ ▰ ▰ │' '  └─────────┘';;
    server-bot:1:0) printf '%s\n' '  ┌───────┐' '  │  ●    │' '  │  ○    │' '  │  ●    │' '  └───────┘';;
    space-bot:1:0) printf '%s\n' '     ✦' '   ╭─▲─╮' '  ╱ CCB ╲' '  │ ■ ■ │' '  └─────┘';;
    *) mascot_render_frame "$id" 1 "$ascii";;
  esac
}
mascot_animate() {
  id=$1; ascii=$2
  if [ "${CCB_NO_ANIMATION:-}" = 1 ] || [ ! -t 0 ] || [ ! -t 1 ]; then mascot_render_frame "$id" 1 "$ascii"; return; fi
  mascot_render_frame "$id" 1 "$ascii"; sleep 0.2 2>/dev/null || :; printf '\033[6A'; mascot_render_frame "$id" 2 "$ascii"
}
