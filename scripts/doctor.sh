#!/bin/sh
# Diagnostic read-only for projects using the CCB template.
set -u

usage() {
  cat <<'EOF'
usage: ./scripts/doctor.sh [project-directory] [--verbose]

Diagnose whether a Git project is ready to use the CCB template.

Examples:
  ./scripts/doctor.sh
  ./scripts/doctor.sh .
  ./scripts/doctor.sh /path/to/project --verbose
EOF
}

TARGET=
VERBOSE=0

for argument in "$@"; do
  case "$argument" in
    --help|-h)
      usage
      exit 0
      ;;
    --verbose|-v)
      VERBOSE=1
      ;;
    -*)
      echo "error: unknown option: $argument" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -n "$TARGET" ]; then
        echo "error: only one project directory may be specified" >&2
        usage >&2
        exit 2
      fi
      TARGET=$argument
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET=.
fi

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMPLATE_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
VALIDATE="$TEMPLATE_ROOT/scripts/validate-ccb.sh"
. "$SCRIPT_DIR/profile-lib.sh"
PROFILE_ROOT="$TEMPLATE_ROOT/profiles"
ERRORS=0
WARNINGS=0

ok() { printf '%s\n' "[OK] $1"; }
warn() { printf '%s\n' "[WARN] $1"; WARNINGS=$((WARNINGS + 1)); }
error() { printf '%s\n' "[ERROR] $1" >&2; ERRORS=$((ERRORS + 1)); }

check_command() {
  command_name=$1
  label=$2
  recommendation=$3

  if command -v "$command_name" >/dev/null 2>&1; then
    ok "$label available"
    return 0
  fi

  warn "$label not found; $recommendation"
  return 1
}

printf '%s\n' 'CCB doctor v1.2'

GIT_AVAILABLE=0
if command -v git >/dev/null 2>&1; then
  ok 'Git available'
  GIT_AVAILABLE=1
else
  error 'Git not found; install Git, then run this command again.'
fi

check_command tmux tmux 'install tmux before starting a CCB session.' || :

GH_AVAILABLE=0
if check_command gh 'GitHub CLI' 'install GitHub CLI if your workflow needs GitHub authentication.'; then
  GH_AVAILABLE=1
fi

check_command ccb CCB 'install or make the CCB command available before starting CCB.' || :

if [ "$GH_AVAILABLE" -eq 1 ]; then
  if gh auth status >/dev/null 2>&1; then
    ok 'GitHub CLI authentication is available'
  else
    warn 'GitHub CLI is not authenticated; run: gh auth login'
  fi
fi

if [ ! -d "$TARGET" ]; then
  error "target directory does not exist: $TARGET"
  TARGET_VALID=0
else
  TARGET=$(CDPATH= cd "$TARGET" && pwd)
  TARGET_VALID=1
  ok "target directory: $TARGET"
fi

PROJECT_IS_GIT=0
if [ "$TARGET_VALID" -eq 1 ] && [ "$GIT_AVAILABLE" -eq 1 ]; then
  if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    PROJECT_IS_GIT=1
    ok 'target is a Git repository'
  else
    error 'target is not a Git repository; initialize Git before installing CCB.'
  fi
fi

if [ "$PROJECT_IS_GIT" -eq 1 ]; then
  if git -C "$TARGET" rev-parse --verify HEAD >/dev/null 2>&1; then
    ok 'initial Git commit exists'
  else
    error 'initial Git commit is missing; create one before CCB creates developer worktrees.'
  fi

  if git -C "$TARGET" remote get-url origin >/dev/null 2>&1; then
    ok 'Git remote "origin" is configured'
  else
    warn 'Git remote "origin" is not configured; add one before publishing work.'
  fi

  if [ -n "$(git -C "$TARGET" status --porcelain 2>/dev/null)" ]; then
    warn 'working tree has local changes; commit or stash them before starting collaborative work.'
  else
    ok 'working tree is clean'
  fi

  if git -C "$TARGET" config --get user.name >/dev/null 2>&1 \
    || git config --global --get user.name >/dev/null 2>&1; then
    ok 'Git author name is configured'
  else
    warn 'Git author name is not configured; run: git config --global user.name "Your Name"'
  fi

  if git -C "$TARGET" config --get user.email >/dev/null 2>&1 \
    || git config --global --get user.email >/dev/null 2>&1; then
    ok 'Git author email is configured'
  else
    warn 'Git author email is not configured; run: git config --global user.email "you@example.com"'
  fi
fi

if [ "$TARGET_VALID" -eq 1 ]; then
  if [ -f "$VALIDATE" ]; then
    VALIDATE_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/ccb-doctor.XXXXXX") || VALIDATE_OUTPUT=
    if [ -n "$VALIDATE_OUTPUT" ]; then
      if sh "$VALIDATE" "$TARGET" >"$VALIDATE_OUTPUT" 2>&1; then
        ok 'CCB template files and ignore rules are valid'
      else
        error 'CCB template files or ignore rules are incomplete; run the installer or inspect the validator output.'
      fi

      if [ "$VERBOSE" -eq 1 ]; then
        printf '%s\n' '--- validate-ccb.sh output ---'
        sed 's/^/  /' "$VALIDATE_OUTPUT"
      fi
      rm -f "$VALIDATE_OUTPUT"
    else
      warn 'could not create a temporary file; CCB template validation was skipped.'
    fi
  else
    error 'validate-ccb.sh is missing from this CCB template checkout.'
  fi
fi

if [ "$TARGET_VALID" -eq 1 ]; then
  printf '%s\n' 'Project profile:'
  if [ ! -f "$TARGET/.ccb/active-profile" ]; then
    warn 'no active profile; run install-project.sh --profile generic to add one.'
  else
    active_profile=$(cat "$TARGET/.ccb/active-profile")
    if ! profile_id_is_safe "$active_profile" || ! profile_parse "$PROFILE_ROOT/$active_profile/profile.conf"; then
      error "invalid active profile: $active_profile"
    elif [ ! -f "$TARGET/.ccb/profiles/$active_profile/PROFILE.md" ]; then
      error "profile installation is incomplete: $active_profile"
    else
      profile_valid=1
      old_ifs=$IFS; IFS=,
      for profile_skill in $PROFILE_SKILLS; do
        [ -n "$profile_skill" ] && [ ! -f "$TARGET/.ccb/profiles/$active_profile/skills/$profile_skill/SKILL.md" ] && profile_valid=0
      done
      IFS=$old_ifs
      if [ "$profile_valid" -eq 1 ]; then
        ok "Active profile: $active_profile (version $PROFILE_VERSION)"
        printf '%s\n' "[INFO] Profile skills: $(profile_skill_count "$PROFILE_SKILLS")"
        ok 'Profile installation is valid'
      else
        error "profile installation is incomplete: $active_profile"
      fi
    fi
  fi
fi

printf '%s\n' "Summary: $ERRORS error(s), $WARNINGS warning(s)."
if [ "$ERRORS" -ne 0 ]; then
  printf '%s\n' 'Result: project is not ready for CCB. Apply the recommendations above, then rerun doctor.' >&2
  exit 1
fi

if [ "$WARNINGS" -ne 0 ]; then
  printf '%s\n' 'Result: project is usable, with recommendations to review before starting CCB.'
else
  printf '%s\n' 'Result: project is ready for CCB.'
fi
