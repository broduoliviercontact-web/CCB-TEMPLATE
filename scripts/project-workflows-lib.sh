#!/bin/sh
project_workflow_name_is_safe() { case "$1" in feature|bugfix|design|review) return 0;; *) return 1;; esac; }
project_workflow_description_is_valid() { value=$1; [ -n "$value" ] && [ "${#value}" -le 200 ] || return 1; case "$value" in *'$('*|*'`'*|*';'*|*'|'*|*'&'*|*'<'*|*'>'*|*'\\'*|*"	"*) return 1;; esac; }
project_workflows_default_content() { cat <<'EOF'
CCB_WORKFLOWS_VERSION=1
CCB_WORKFLOW_NAMES=feature,bugfix,design,review
CCB_WORKFLOW_DEFAULT=feature
CCB_WORKFLOW_FEATURE_STEPS=manager,developer,reviewer
CCB_WORKFLOW_FEATURE_DESCRIPTION=Plan implement and review a project feature
CCB_WORKFLOW_BUGFIX_STEPS=graph,developer,reviewer
CCB_WORKFLOW_BUGFIX_DESCRIPTION=Investigate fix and review a defect
CCB_WORKFLOW_DESIGN_STEPS=manager,graphiste,reviewer
CCB_WORKFLOW_DESIGN_DESCRIPTION=Prepare implement and review a visual change
CCB_WORKFLOW_REVIEW_STEPS=reviewer
CCB_WORKFLOW_REVIEW_DESCRIPTION=Review an existing project change
EOF
}
project_workflows_parse() {
  PROJECT_WORKFLOWS_VERSION= PROJECT_WORKFLOW_NAMES= PROJECT_WORKFLOW_DEFAULT=
  PROJECT_WORKFLOW_FEATURE_STEPS= PROJECT_WORKFLOW_FEATURE_DESCRIPTION= PROJECT_WORKFLOW_BUGFIX_STEPS= PROJECT_WORKFLOW_BUGFIX_DESCRIPTION= PROJECT_WORKFLOW_DESIGN_STEPS= PROJECT_WORKFLOW_DESIGN_DESCRIPTION= PROJECT_WORKFLOW_REVIEW_STEPS= PROJECT_WORKFLOW_REVIEW_DESCRIPTION=
  workflow_file=$1; [ -f "$workflow_file" ] && [ ! -L "$workflow_file" ] || return 1; seen=' '
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in CCB_WORKFLOWS_VERSION=*|CCB_WORKFLOW_NAMES=*|CCB_WORKFLOW_DEFAULT=*|CCB_WORKFLOW_FEATURE_STEPS=*|CCB_WORKFLOW_FEATURE_DESCRIPTION=*|CCB_WORKFLOW_BUGFIX_STEPS=*|CCB_WORKFLOW_BUGFIX_DESCRIPTION=*|CCB_WORKFLOW_DESIGN_STEPS=*|CCB_WORKFLOW_DESIGN_DESCRIPTION=*|CCB_WORKFLOW_REVIEW_STEPS=*|CCB_WORKFLOW_REVIEW_DESCRIPTION=*) key=${line%%=*}; value=${line#*=};; *) return 1;; esac
    case "$seen" in *" $key "*) return 1;; *) seen="$seen$key ";; esac
    case "$key" in
      CCB_WORKFLOWS_VERSION) PROJECT_WORKFLOWS_VERSION=$value;; CCB_WORKFLOW_NAMES) PROJECT_WORKFLOW_NAMES=$value;; CCB_WORKFLOW_DEFAULT) PROJECT_WORKFLOW_DEFAULT=$value;;
      CCB_WORKFLOW_FEATURE_STEPS) PROJECT_WORKFLOW_FEATURE_STEPS=$value;; CCB_WORKFLOW_FEATURE_DESCRIPTION) PROJECT_WORKFLOW_FEATURE_DESCRIPTION=$value;; CCB_WORKFLOW_BUGFIX_STEPS) PROJECT_WORKFLOW_BUGFIX_STEPS=$value;; CCB_WORKFLOW_BUGFIX_DESCRIPTION) PROJECT_WORKFLOW_BUGFIX_DESCRIPTION=$value;; CCB_WORKFLOW_DESIGN_STEPS) PROJECT_WORKFLOW_DESIGN_STEPS=$value;; CCB_WORKFLOW_DESIGN_DESCRIPTION) PROJECT_WORKFLOW_DESIGN_DESCRIPTION=$value;; CCB_WORKFLOW_REVIEW_STEPS) PROJECT_WORKFLOW_REVIEW_STEPS=$value;; CCB_WORKFLOW_REVIEW_DESCRIPTION) PROJECT_WORKFLOW_REVIEW_DESCRIPTION=$value;;
    esac
  done <"$workflow_file"
  [ "$PROJECT_WORKFLOWS_VERSION" = 1 ] && [ "$PROJECT_WORKFLOW_NAMES" = feature,bugfix,design,review ] && project_workflow_name_is_safe "$PROJECT_WORKFLOW_DEFAULT" || return 1
  for workflow_name in feature bugfix design review; do project_workflow_details "$workflow_name"; project_workflow_description_is_valid "$PROJECT_WORKFLOW_DESCRIPTION" || return 1; [ -n "$PROJECT_WORKFLOW_STEPS" ] || return 1; oldifs=$IFS; IFS=,; for workflow_role in $PROJECT_WORKFLOW_STEPS; do project_agent_role_is_safe "$workflow_role" || { IFS=$oldifs; return 1; }; case ",$PROJECT_WORKFLOW_STEPS," in *,"$workflow_role",*,"$workflow_role",*) IFS=$oldifs; return 1;; esac; done; IFS=$oldifs; done
}
project_workflow_details() { case "$1" in feature) PROJECT_WORKFLOW_STEPS=$PROJECT_WORKFLOW_FEATURE_STEPS; PROJECT_WORKFLOW_DESCRIPTION=$PROJECT_WORKFLOW_FEATURE_DESCRIPTION;; bugfix) PROJECT_WORKFLOW_STEPS=$PROJECT_WORKFLOW_BUGFIX_STEPS; PROJECT_WORKFLOW_DESCRIPTION=$PROJECT_WORKFLOW_BUGFIX_DESCRIPTION;; design) PROJECT_WORKFLOW_STEPS=$PROJECT_WORKFLOW_DESIGN_STEPS; PROJECT_WORKFLOW_DESCRIPTION=$PROJECT_WORKFLOW_DESIGN_DESCRIPTION;; review) PROJECT_WORKFLOW_STEPS=$PROJECT_WORKFLOW_REVIEW_STEPS; PROJECT_WORKFLOW_DESCRIPTION=$PROJECT_WORKFLOW_REVIEW_DESCRIPTION;; *) return 1;; esac; }
