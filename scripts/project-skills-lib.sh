#!/bin/sh
ponytail_mode_is_valid() { case "$1" in off|lite|full|ultra) return 0;; *) return 1;; esac; }
ponytail_ref_is_safe() { case "$1" in ''|*[!A-Za-z0-9._/-]*|*..*) return 1;; *) return 0;; esac; }
project_skills_parse() {
  PROJECT_SKILLS_VERSION= PROJECT_SKILL_PONYTAIL= PROJECT_SKILL_PONYTAIL_MODE= PROJECT_SKILL_PONYTAIL_SOURCE= PROJECT_SKILL_PONYTAIL_REF=
  file=$1; [ -f "$file" ] && [ ! -L "$file" ] || return 1; seen=' '
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in CCB_SKILLS_VERSION=*|CCB_SKILL_PONYTAIL=*|CCB_SKILL_PONYTAIL_MODE=*|CCB_SKILL_PONYTAIL_SOURCE=*|CCB_SKILL_PONYTAIL_REF=*) key=${line%%=*}; value=${line#*=};; *) return 1;; esac
    case "$seen" in *" $key "*) return 1;; *) seen="$seen$key ";; esac
    case "$key" in CCB_SKILLS_VERSION) PROJECT_SKILLS_VERSION=$value;; CCB_SKILL_PONYTAIL) PROJECT_SKILL_PONYTAIL=$value;; CCB_SKILL_PONYTAIL_MODE) PROJECT_SKILL_PONYTAIL_MODE=$value;; CCB_SKILL_PONYTAIL_SOURCE) PROJECT_SKILL_PONYTAIL_SOURCE=$value;; CCB_SKILL_PONYTAIL_REF) PROJECT_SKILL_PONYTAIL_REF=$value;; esac
  done <"$file"
  [ "$PROJECT_SKILLS_VERSION" = 1 ] && [ "$PROJECT_SKILL_PONYTAIL_SOURCE" = DietrichGebert/ponytail ] && ponytail_ref_is_safe "$PROJECT_SKILL_PONYTAIL_REF" && ponytail_mode_is_valid "$PROJECT_SKILL_PONYTAIL_MODE" || return 1
  case "$PROJECT_SKILL_PONYTAIL_MODE:$PROJECT_SKILL_PONYTAIL" in off:disabled|lite:enabled|full:enabled|ultra:enabled) return 0;; *) return 1;; esac
}
