#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ccb-provider.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir "$TMP/bin"
cat >"$TMP/bin/ollama" <<'EOF'
#!/bin/sh
case "$1" in --version) echo ollama-test;; list) printf 'NAME ID\nmodel:latest x\n';; run) exit 0;; *) exit 9;; esac
EOF
chmod +x "$TMP/bin/ollama"
PATH="$TMP/bin:$PATH" "$ROOT/scripts/provider-router.sh" available ollama .
PATH="$TMP/bin:$PATH" "$ROOT/scripts/provider-router.sh" check ollama model:latest . local
if PATH="$TMP/bin:$PATH" "$ROOT/scripts/provider-router.sh" available unknown . >/dev/null 2>&1; then exit 1; fi
echo '[OK] provider routing tests passed'
