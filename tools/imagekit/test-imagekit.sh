#!/usr/bin/env bash
# Hermetic test for imagekit.mjs's broker→direct fallback (MD-2037).
#
# It points the broker bases at an unreachable port (127.0.0.1:1) and the direct
# bases at a local mock ImageKit server, supplies a fake Access token + private
# key, and asserts that both a GET (list) and a POST-multipart (upload) request:
#   • try the broker, fail on the refused connection,
#   • log the fallback notice on stderr,
#   • complete successfully against the direct API with HTTP Basic auth.
# No network, no cloudflared, no real ImageKit — fully offline.
#
#   bash tools/imagekit/test-imagekit.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CLI="$HERE/imagekit.mjs"

command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/imagekit-fallback.XXXXXX")"
trap 'kill "${SRV_PID:-}" 2>/dev/null; rm -rf "$TMP"' EXIT

fail=0
ok()   { echo "  ok  : $1"; }
bad()  { echo "  FAIL: $1"; fail=1; }

# --- mock ImageKit direct API -------------------------------------------------
# Routes: GET /v1/files → a list; POST /api/v1/files/upload → an upload result.
# Requires an `Authorization: Basic` header on every request (proves the direct
# path swapped in Basic auth). Prints its chosen ephemeral port as PORT=<n>.
cat > "$TMP/mock.mjs" <<'JS'
import http from 'http';
const srv = http.createServer((req, res) => {
  const auth = req.headers['authorization'] || '';
  if (!auth.startsWith('Basic ')) { res.writeHead(401); res.end('{"message":"no basic auth"}'); return; }
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', () => {
    if (req.method === 'GET' && req.url.startsWith('/v1/files')) {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify([{ fileId: 'mock-list-1', name: 'listed.png' }]));
    } else if (req.method === 'POST' && req.url.startsWith('/api/v1/files/upload')) {
      const sawMultipart = (req.headers['content-type'] || '').includes('multipart/form-data');
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ fileId: 'mock-upload-1', name: 'uploaded.png', multipart: sawMultipart }));
    } else {
      res.writeHead(404); res.end('{"message":"no route"}');
    }
  });
});
srv.listen(0, '127.0.0.1', () => { console.log('PORT=' + srv.address().port); });
JS

node "$TMP/mock.mjs" > "$TMP/port.txt" 2>"$TMP/mock.err" &
SRV_PID=$!
disown "$SRV_PID" 2>/dev/null || true   # silence the shell's "Terminated" notice on cleanup

# wait for the port line (up to ~5s)
PORT=""
for _ in $(seq 1 50); do
  PORT="$(sed -n 's/^PORT=//p' "$TMP/port.txt" 2>/dev/null)"
  [ -n "$PORT" ] && break
  sleep 0.1
done
[ -n "$PORT" ] || { echo "FAIL: mock server never reported a port"; cat "$TMP/mock.err"; exit 1; }

# Broker bases point at a refused port so the fetch throws; direct bases point at
# the mock. Fake token + private key so no cloudflared / ~/.env is consulted.
export IMAGEKIT_BROKER_BASE="http://127.0.0.1:1/imagekit/api/v1"
export IMAGEKIT_BROKER_UPLOAD="http://127.0.0.1:1/imagekit/upload/api/v1"
export IMAGEKIT_DIRECT_BASE="http://127.0.0.1:$PORT/v1"
export IMAGEKIT_DIRECT_UPLOAD="http://127.0.0.1:$PORT/api/v1"
export IMAGEKIT_ACCESS_TOKEN="fake-broker-token"
export IMAGEKIT_PRIVATE_KEY="private_TESTKEY"

echo "imagekit fallback smoke: mock port=$PORT"

# --- 1) list: GET falls back to the direct API --------------------------------
out="$(node "$CLI" list 2>"$TMP/list.err")"; rc=$?
[ "$rc" -eq 0 ] && ok "list: exits 0 via fallback" || bad "list: exit $rc"
grep -qi 'falling back to the direct ImageKit API' "$TMP/list.err" && ok "list: logs the fallback notice on stderr" || bad "list: no fallback notice (stderr: $(cat "$TMP/list.err"))"
printf '%s' "$out" | grep -q 'mock-list-1' && ok "list: returns the direct API's payload" || bad "list: missing direct payload (got: $out)"

# --- 2) upload: POST multipart falls back to the direct API -------------------
printf 'not really a png' > "$TMP/pic.png"
out="$(node "$CLI" upload "$TMP/pic.png" --name pic.png 2>"$TMP/up.err")"; rc=$?
[ "$rc" -eq 0 ] && ok "upload: exits 0 via fallback" || bad "upload: exit $rc (stderr: $(cat "$TMP/up.err"))"
printf '%s' "$out" | grep -q 'mock-upload-1' && ok "upload: returns the direct API's result" || bad "upload: missing upload result (got: $out)"
printf '%s' "$out" | grep -q '"multipart": true' && ok "upload: direct request kept multipart form body" || bad "upload: multipart not preserved (got: $out)"

# --- 3) missing private key: clear error, not a silent no-op ------------------
( unset IMAGEKIT_PRIVATE_KEY; HOME="$TMP/nohome" node "$CLI" list ) >"$TMP/nokey.out" 2>"$TMP/nokey.err"; rc=$?
[ "$rc" -ne 0 ] && ok "no key: fails (non-zero) instead of silently succeeding" || bad "no key: unexpectedly exited 0"
grep -qi 'IMAGEKIT_PRIVATE_KEY' "$TMP/nokey.err" && ok "no key: error names IMAGEKIT_PRIVATE_KEY" || bad "no key: error doesn't name the missing secret (stderr: $(cat "$TMP/nokey.err"))"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES above"; exit 1; }
