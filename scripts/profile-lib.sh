#!/bin/sh

profile_id_is_safe() {
  case "$1" in
    ''|*[!a-z0-9-]*|-*|*-) return 1 ;;
    *) return 0 ;;
  esac
}

profile_path_is_safe() {
  case "$1" in
    ''|/*|*'..'*) return 1 ;;
    *) return 0 ;;
  esac
}

profile_reset() {
  PROFILE_ID=
  PROFILE_NAME=
  PROFILE_VERSION=
  PROFILE_DESCRIPTION=
  PROFILE_MEMORY_SEED=
  PROFILE_SKILLS=
  PROFILE_PARSE_ERROR=
}

profile_parse() {
  profile_reset
  profile_conf=$1
  [ -f "$profile_conf" ] || { PROFILE_PARSE_ERROR="missing profile.conf"; return 1; }

  while IFS= read -r profile_line || [ -n "$profile_line" ]; do
    case "$profile_line" in
      ''|'#'*) ;;
      PROFILE_ID=*) PROFILE_ID=${profile_line#PROFILE_ID=} ;;
      PROFILE_NAME=*) PROFILE_NAME=${profile_line#PROFILE_NAME=} ;;
      PROFILE_VERSION=*) PROFILE_VERSION=${profile_line#PROFILE_VERSION=} ;;
      PROFILE_DESCRIPTION=*) PROFILE_DESCRIPTION=${profile_line#PROFILE_DESCRIPTION=} ;;
      PROFILE_MEMORY_SEED=*) PROFILE_MEMORY_SEED=${profile_line#PROFILE_MEMORY_SEED=} ;;
      PROFILE_SKILLS=*) PROFILE_SKILLS=${profile_line#PROFILE_SKILLS=} ;;
      *=*) PROFILE_PARSE_ERROR="unknown key: ${profile_line%%=*}"; return 1 ;;
      *) PROFILE_PARSE_ERROR="invalid line"; return 1 ;;
    esac
  done <"$profile_conf"

  if ! profile_id_is_safe "$PROFILE_ID"; then
    PROFILE_PARSE_ERROR="invalid PROFILE_ID"
    return 1
  fi
  if [ -z "$PROFILE_NAME" ] || [ -z "$PROFILE_VERSION" ] || [ -z "$PROFILE_DESCRIPTION" ]; then
    PROFILE_PARSE_ERROR="missing required metadata"
    return 1
  fi
  if ! profile_path_is_safe "$PROFILE_MEMORY_SEED"; then
    PROFILE_PARSE_ERROR="unsafe PROFILE_MEMORY_SEED"
    return 1
  fi
  return 0
}

profile_skill_count() {
  profile_skills=$1
  profile_count=0
  [ -n "$profile_skills" ] || { printf '%s\n' 0; return; }
  old_ifs=$IFS
  IFS=,
  for profile_skill in $profile_skills; do
    profile_count=$((profile_count + 1))
  done
  IFS=$old_ifs
  printf '%s\n' "$profile_count"
}
