#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
PYTHON=${CCB_PYTHON:-python3}
PYTHON_BIN=$(command -v "$PYTHON" 2>/dev/null || true)
[ -n "$PYTHON_BIN" ] && PYTHON=$PYTHON_BIN
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccb-token-proxy.XXXXXX")
proxy_pid= upstream_pid=
cleanup() {
  [ -z "${proxy_pid:-}" ] || kill "$proxy_pid" 2>/dev/null || :
  [ -z "${upstream_pid:-}" ] || kill "$upstream_pid" 2>/dev/null || :
  rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }

"$PYTHON" -c 'import aiohttp' >/dev/null 2>&1 || fail "aiohttp is required; set CCB_PYTHON to the CCB Python environment"

upstream_port_file=$WORK/upstream-port
"$PYTHON" -c '
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        size = int(self.headers.get("Content-Length", 0))
        self.rfile.read(size)
        body = json.dumps({"usage": {"input_tokens": 17, "output_tokens": 5}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_): pass

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
open(sys.argv[1], "w", encoding="utf-8").write(str(server.server_port))
server.serve_forever()
' "$upstream_port_file" >/dev/null 2>&1 &
upstream_pid=$!
for attempt in $(seq 1 20); do [ -s "$upstream_port_file" ] && break; sleep 0.1; done
[ -s "$upstream_port_file" ] || fail 'fake Ollama upstream did not start'
upstream_port=$(cat "$upstream_port_file")
proxy_port=$("$PYTHON" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')

"$PYTHON" "$ROOT/assets/token-proxy.py" --upstream "http://127.0.0.1:$upstream_port" --port "$proxy_port" --metrics "$WORK/usage.jsonl" >"$WORK/proxy.log" 2>&1 &
proxy_pid=$!
for attempt in $(seq 1 20); do
  if "$PYTHON" -c 'import sys, urllib.request; urllib.request.urlopen(sys.argv[1], timeout=.2).read()' "http://127.0.0.1:$proxy_port/health" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
kill -0 "$proxy_pid" 2>/dev/null || fail "token proxy did not start: $(cat "$WORK/proxy.log")"

"$PYTHON" -c '
import json
import sys
import urllib.request

request = urllib.request.Request(sys.argv[1], data=json.dumps({"model": "test:cloud"}).encode(), headers={"Content-Type": "application/json"}, method="POST")
with urllib.request.urlopen(request, timeout=3) as response:
    assert response.status == 200
' "http://127.0.0.1:$proxy_port/manager/v1/messages"
for attempt in $(seq 1 20); do [ -s "$WORK/usage.jsonl" ] && break; sleep 0.1; done
[ -s "$WORK/usage.jsonl" ] || fail 'proxy request did not create usage.jsonl'
"$PYTHON" -c '
import json
import sys
event = json.loads(open(sys.argv[1], encoding="utf-8").readline())
assert event["agent"] == "manager"
assert event["model"] == "test:cloud"
assert event["input_tokens"] == 17
assert event["output_tokens"] == 5
' "$WORK/usage.jsonl" || fail 'usage.jsonl does not contain the expected CCB request metrics'

echo '[OK] Token proxy records a CCB-compatible request'

project=$WORK/project
start_port=$("$PYTHON" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
mkdir -p "$project/.ccb/token-monitor" "$project/.ccb-template/token-monitor" "$WORK/bin"
cp "$ROOT/assets/token-proxy.py" "$project/.ccb/token-proxy.py"
"$PYTHON" - "$project" "$start_port" <<'PY'
from pathlib import Path
import sys

project = Path(sys.argv[1])
port = sys.argv[2]
for path in (project / ".ccb/token-monitor/port", project / ".ccb-template/token-monitor/port"):
    path.write_text(port + "\n", encoding="utf-8")
for path in (project / ".ccb/token-monitor-python", project / ".ccb-template/token-monitor/python"):
    path.write_text(sys.executable + "\n", encoding="utf-8")
config = "\n".join(
    f'ANTHROPIC_BASE_URL = "http://127.0.0.1:{port}/{agent}"'
    for agent in ("manager", "graph", "developer", "reviewer")
)
(project / ".ccb/ccb.config").write_text(config + "\n", encoding="utf-8")
PY
printf '#!/bin/sh\ntouch "%s/ccb-was-started"\n' "$WORK" >"$WORK/bin/ccb"
chmod +x "$WORK/bin/ccb"
# Simulate the monitor files removed by a forceful CCB cleanup. The durable copy
# remains outside .ccb and must make the next start self-healing.
rm -f "$project/.ccb/token-proxy.py" "$project/.ccb/token-monitor-python" \
  "$project/.ccb/token-monitor/port" "$project/.ccb/token-monitor/pricing.json"
env PATH="$WORK/bin:$PATH" "$ROOT/ccb-template" start "$project"
[ -f "$WORK/ccb-was-started" ] || fail 'ccb-template start did not launch CCB after the monitor became ready'
[ -f "$project/.ccb/token-proxy.py" ] || fail 'ccb-template start did not restore the token proxy'
[ -f "$project/.ccb/token-monitor-python" ] || fail 'ccb-template start did not restore the token monitor Python setting'
[ -f "$project/.ccb/token-monitor/port" ] || fail 'ccb-template start did not restore the token monitor port'
[ -f "$project/.ccb/token-monitor/pricing.json" ] || fail 'ccb-template start did not restore token monitor pricing'
start_proxy_pid=$(cat "$project/.ccb/token-monitor/proxy.pid")
kill "$start_proxy_pid" 2>/dev/null || :

echo '[OK] ccb-template start waits for the project monitor before CCB'

dashboard_project=$WORK/dashboard-project
mkdir -p "$dashboard_project/.ccb/token-monitor" "$WORK/no-python3"
printf '%s\n' "$PYTHON" >"$dashboard_project/.ccb/token-monitor-python"
printf '%s\n' '{"timestamp":"2026-07-31T07:00:00+00:00","agent":"manager","model":"test:cloud","input_tokens":11,"output_tokens":3,"duration_ms":42}' >"$dashboard_project/.ccb/token-monitor/usage.jsonl"
cat >"$WORK/no-python3/python3" <<'EOF'
#!/bin/sh
exit 97
EOF
chmod +x "$WORK/no-python3/python3"
PATH="$WORK/no-python3:/usr/bin:/bin" "$ROOT/ccb-template" monitor "$dashboard_project" >/dev/null || fail 'ccb-template monitor did not use the stored project Python'

echo '[OK] ccb-template monitor uses the project Python setting'
