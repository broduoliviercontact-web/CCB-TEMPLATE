#!/bin/sh

project_profile_id_is_safe() { case "$1" in ''|*[!a-z0-9-]*) return 1;; *) return 0;; esac; }

project_profile_parse() {
  PROJECT_PROFILE_ID= PROJECT_PROFILE_NAME= PROJECT_PROFILE_DESCRIPTION= PROJECT_PROFILE_GUIDANCE= PROJECT_PROFILE_SECURITY=
  PROJECT_MODEL_DEFAULT= PROJECT_MODEL_PLANNER= PROJECT_MODEL_CODER= PROJECT_MODEL_REVIEWER=
  profile_file=$1
  [ -f "$profile_file" ] && [ ! -L "$profile_file" ] || return 1
  seen=' '
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      PROFILE_ID=*|PROFILE_NAME=*|PROFILE_DESCRIPTION=*|PROFILE_GUIDANCE=*|PROFILE_SECURITY=*|MODEL_DEFAULT=*|MODEL_PLANNER=*|MODEL_CODER=*|MODEL_REVIEWER=*) key=${line%%=*}; value=${line#*=} ;;
      *) return 1 ;;
    esac
    case "$seen" in *" $key "*) return 1;; *) seen="$seen$key ";; esac
    case "$key" in
      PROFILE_ID) PROJECT_PROFILE_ID=$value;; PROFILE_NAME) PROJECT_PROFILE_NAME=$value;; PROFILE_DESCRIPTION) PROJECT_PROFILE_DESCRIPTION=$value;;
      PROFILE_GUIDANCE) PROJECT_PROFILE_GUIDANCE=$value;; PROFILE_SECURITY) PROJECT_PROFILE_SECURITY=$value;;
      MODEL_DEFAULT) PROJECT_MODEL_DEFAULT=$value;; MODEL_PLANNER) PROJECT_MODEL_PLANNER=$value;; MODEL_CODER) PROJECT_MODEL_CODER=$value;; MODEL_REVIEWER) PROJECT_MODEL_REVIEWER=$value;;
    esac
  done <"$profile_file"
  project_profile_id_is_safe "$PROJECT_PROFILE_ID" && [ -n "$PROJECT_PROFILE_NAME" ] && [ -n "$PROJECT_PROFILE_DESCRIPTION" ] && [ -n "$PROJECT_PROFILE_GUIDANCE" ] && [ -n "$PROJECT_PROFILE_SECURITY" ] || return 1
  for project_profile_model in "$PROJECT_MODEL_DEFAULT" "$PROJECT_MODEL_PLANNER" "$PROJECT_MODEL_CODER" "$PROJECT_MODEL_REVIEWER"; do model_name_is_safe "$project_profile_model" || return 1; done
}

project_profiles_list() { printf '%s\n' 'generic, web, node, python, audio'; }
