#!/bin/sh

project_models_parse() {
  PROJECT_MODEL_PROVIDER= PROJECT_MODEL_DEFAULT= PROJECT_MODEL_PLANNER= PROJECT_MODEL_CODER= PROJECT_MODEL_REVIEWER=
  models_file=$1
  [ -f "$models_file" ] && [ ! -L "$models_file" ] || return 1
  seen=' '
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in CCB_MODEL_PROVIDER=*|CCB_MODEL_DEFAULT=*|CCB_MODEL_PLANNER=*|CCB_MODEL_CODER=*|CCB_MODEL_REVIEWER=*) key=${line%%=*}; value=${line#*=};; *) return 1;; esac
    case "$seen" in *" $key "*) return 1;; *) seen="$seen$key ";; esac
    case "$key" in
      CCB_MODEL_PROVIDER) PROJECT_MODEL_PROVIDER=$value;; CCB_MODEL_DEFAULT) PROJECT_MODEL_DEFAULT=$value;; CCB_MODEL_PLANNER) PROJECT_MODEL_PLANNER=$value;; CCB_MODEL_CODER) PROJECT_MODEL_CODER=$value;; CCB_MODEL_REVIEWER) PROJECT_MODEL_REVIEWER=$value;;
    esac
  done <"$models_file"
  [ "$PROJECT_MODEL_PROVIDER" = ollama ] || return 1
  for project_config_model in "$PROJECT_MODEL_DEFAULT" "$PROJECT_MODEL_PLANNER" "$PROJECT_MODEL_CODER" "$PROJECT_MODEL_REVIEWER"; do model_name_is_safe "$project_config_model" || return 1; done
}

project_conf_parse() {
  PROJECT_NAME= PROJECT_PROFILE=
  project_file=$1
  [ -f "$project_file" ] && [ ! -L "$project_file" ] || return 1
  seen=' '
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in CCB_PROJECT_NAME=*|CCB_PROJECT_PROFILE=*|CCB_PROJECT_VERSION=*|CCB_TEMPLATE_VERSION=*) key=${line%%=*}; value=${line#*=};; *) return 1;; esac
    case "$seen" in *" $key "*) return 1;; *) seen="$seen$key ";; esac
    case "$key" in CCB_PROJECT_NAME) PROJECT_NAME=$value;; CCB_PROJECT_PROFILE) PROJECT_PROFILE=$value;; esac
  done <"$project_file"
  [ -n "$PROJECT_NAME" ] && project_profile_id_is_safe "$PROJECT_PROFILE"
}
