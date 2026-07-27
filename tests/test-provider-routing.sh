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
printf 'prompt\n' >"$TMP/prompt"
printf 'literal $(touch "%s")\n' "$TMP/witness" >"$TMP/response"
CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$TMP/response" "$ROOT/scripts/provider-router.sh" generate-file ollama model:latest "$TMP/prompt" "$TMP/output"
cmp -s "$TMP/response" "$TMP/output"
[ ! -e "$TMP/witness" ]
CCB_TEST_MODE=1 CCB_OLLAMA_ENDPOINT=http://localhost:11434 CCB_TEST_PROVIDER_RESPONSE_FILE="$TMP/response" "$ROOT/scripts/provider-router.sh" generate-file ollama model:latest "$TMP/prompt" "$TMP/output-localhost"
CCB_TEST_MODE=1 CCB_OLLAMA_ENDPOINT=http://127.0.0.1:11434 CCB_TEST_PROVIDER_RESPONSE_FILE="$TMP/response" "$ROOT/scripts/provider-router.sh" generate-file ollama model:latest "$TMP/prompt" "$TMP/output-loopback"
if CCB_TEST_MODE=1 CCB_OLLAMA_ENDPOINT=http://example.com:11434 CCB_TEST_PROVIDER_RESPONSE_FILE="$TMP/response" "$ROOT/scripts/provider-router.sh" generate-file ollama model:latest "$TMP/prompt" "$TMP/output-remote" >/dev/null 2>&1; then exit 1; else [ "$?" -eq 68 ]; fi
if CCB_TEST_PROVIDER_RESPONSE_FILE="$TMP/response" "$ROOT/scripts/provider-router.sh" generate-file ollama model:latest "$TMP/prompt" "$TMP/output-production" >/dev/null 2>&1; then exit 1; else [ "$?" -eq 2 ]; fi
ln -s "$TMP/response" "$TMP/response-link"
if CCB_TEST_MODE=1 CCB_TEST_PROVIDER_RESPONSE_FILE="$TMP/response-link" "$ROOT/scripts/provider-router.sh" generate-file ollama model:latest "$TMP/prompt" "$TMP/output-link" >/dev/null 2>&1; then exit 1; else [ "$?" -eq 65 ]; fi
if PATH="$TMP/bin:$PATH" "$ROOT/scripts/provider-router.sh" available unknown . >/dev/null 2>&1; then exit 1; fi
echo '[OK] provider routing tests passed'
