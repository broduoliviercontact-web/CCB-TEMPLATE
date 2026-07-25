#!/usr/bin/env sh
set -eu

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: run this script from a Git repository" >&2
  exit 1
fi

mkdir -p .ccb graphify-out
touch .gitignore

append_ignore() {
  entry=$1
  if ! grep -Fqx "$entry" .gitignore; then
    printf '\n%s\n' "$entry" >> .gitignore
    echo "added .gitignore entry: $entry"
  fi
}

append_ignore "graphify-out/"
append_ignore ".ccb/backups/"

echo "CCB project directories are ready."
