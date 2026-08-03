#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/figma-inspect.mjs"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/figma-inspect-test.XXXXXX")"
cleanup() {
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  trash "$ROOT"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
has() { printf '%s\n' "$1" | rg -q -F "$2" || fail "$3: $1"; }

OUT="$(node "$SCRIPT" parse-url 'https://www.figma.com/design/AbC123/Footer?node-id=10-20')"
has "$OUT" '"fileKey":"AbC123"' "design URL file key"
has "$OUT" '"nodeId":"10:20"' "hyphenated node id normalization"

OUT="$(node "$SCRIPT" parse-url 'https://figma.com/file/Key999/Name?node-id=12%3A34')"
has "$OUT" '"nodeId":"12:34"' "encoded node id normalization"

cat > "$ROOT/server.mjs" <<'EOF'
import http from 'node:http';
import fs from 'node:fs';
const mode = process.env.STUB_MODE;
const requests = [];
const send = (res, status, body) => { res.writeHead(status, {'content-type':'application/json'}); res.end(JSON.stringify(body)); };
const server = http.createServer((req, res) => {
  requests.push({url:req.url, token:req.headers['cf-access-token'] || null});
  fs.writeFileSync(process.env.HIT_LOG, JSON.stringify(requests));
  if (req.url === '/figma/oauth/status') return send(res, 200, mode === 'unauthorized' ? {connected:false} : {connected:true});
  if (req.url === '/figma/v1/files/AbC123?depth=1') return send(res, 200, {document:{id:'0:0',name:'Footer library',type:'DOCUMENT'},components:{'C:1':{name:'Button'}},componentSets:{'CS:1':{name:'Button states'}},styles:{'S:1':{name:'Heading/Large',styleType:'TEXT'}}});
  if (req.url === '/figma/v1/files/AbC123') return send(res, 200, {document:{id:'0:0',name:'Footer library',type:'DOCUMENT',children:[{id:'10:20',name:'Desktop',type:'FRAME',absoluteBoundingBox:{width:1440,height:420}}]},styles:{'S:1':{name:'Heading/Large',styleType:'TEXT'}}});
  if (req.url === '/figma/v1/files/AbC123/nodes?ids=10%3A20') return send(res, 200, {nodes:{'10:20':{document:{id:'10:20',name:'Footer',type:'FRAME',absoluteBoundingBox:{width:1440,height:420},layoutMode:'HORIZONTAL',itemSpacing:24,fills:[{type:'SOLID',color:{r:0.1,g:0.2,b:0.3}}],children:[{id:'11:1',name:'Heading',type:'TEXT',characters:'Plan your next event',style:{fontFamily:'Inter',fontSize:32,fontWeight:700,lineHeightPx:40}}]},components:{}}}});
  if (req.url === '/figma/v1/images/AbC123?ids=10%3A20&format=png&scale=2') return mode === 'render-forbidden' ? send(res, 403, {error:'forbidden'}) : send(res, 200, {images:{'10:20':'https://render.example/footer.png'}});
  send(res, 404, {error:'unexpected request',path:req.url});
});
server.listen(0, '127.0.0.1', () => { fs.writeFileSync(process.env.PORT_FILE, String(server.address().port)); });
EOF

start_server() {
  : > "$ROOT/port"
  STUB_MODE="$1" HIT_LOG="$ROOT/hits" PORT_FILE="$ROOT/port" node "$ROOT/server.mjs" &
  SERVER_PID=$!
  i=0; while [ ! -s "$ROOT/port" ] && [ "$i" -lt 50 ]; do sleep 0.05; i=$((i+1)); done
  [ -s "$ROOT/port" ] || fail "stub server did not start"
  PORT="$(cat "$ROOT/port")"
}

start_server success
OUT="$(FIGMA_ACCESS_TOKEN=must-not-be-used FIGMA_INSPECT_ACCESS_TOKEN=worker-token FIGMA_BROKER_APP="https://access.example" FIGMA_BROKER_BASE="http://127.0.0.1:$PORT" node "$SCRIPT" inspect 'https://figma.com/design/AbC123/Footer?node-id=10-20')"
has "$OUT" '"name":"Footer"' "selected node returned"
has "$OUT" '"width":1440' "frame dimensions returned"
has "$OUT" '"layoutMode":"HORIZONTAL"' "layout data returned"
has "$OUT" '"fontFamily":"Inter"' "typography returned"
has "$OUT" '"C:1":{"name":"Button"}' "node inspection includes file-level component metadata"
has "$OUT" '"CS:1":{"name":"Button states"}' "node inspection includes file-level component-set metadata"
has "$OUT" '"S:1":{"name":"Heading/Large","styleType":"TEXT"}' "node inspection includes file-level style metadata"
has "$OUT" '"renderedReference":"https://render.example/footer.png"' "rendered reference returned"
has "$(cat "$ROOT/hits")" '"token":"worker-token"' "broker Access token sent"
has "$(cat "$ROOT/hits")" '/figma/v1/files/AbC123/nodes?ids=10%3A20' "node endpoint selected"
has "$(cat "$ROOT/hits")" '/figma/v1/files/AbC123?depth=1' "node inspection requests shallow file metadata"

OUT="$(FIGMA_INSPECT_ACCESS_TOKEN=worker-token FIGMA_BROKER_APP="https://access.example" FIGMA_BROKER_BASE="http://127.0.0.1:$PORT" node "$SCRIPT" inspect 'https://figma.com/file/AbC123/Footer-library')"
has "$OUT" '"name":"Footer library"' "file URL returns the document tree"
has "$OUT" '"renderedReference":null' "file inspection does not request a rendered node"
has "$(cat "$ROOT/hits")" '"url":"/figma/v1/files/AbC123"' "file endpoint selected"
kill "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true; SERVER_PID=""

start_server render-forbidden
set +e
OUT="$(FIGMA_INSPECT_ACCESS_TOKEN=worker-token FIGMA_BROKER_APP="https://access.example" FIGMA_BROKER_BASE="http://127.0.0.1:$PORT" node "$SCRIPT" inspect 'https://figma.com/design/AbC123/Footer?node-id=10-20' 2>&1)"
RC=$?
set -e
[ "$RC" -eq 3 ] || fail "render-time authorization failure should exit 3, got $RC"
has "$OUT" 'Figma authorization was rejected (HTTP 403)' "render-time authorization failure is not suppressed"
kill "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true; SERVER_PID=""

start_server unauthorized
set +e
OUT="$(FIGMA_INSPECT_ACCESS_TOKEN=worker-token FIGMA_BROKER_APP="https://access.example" FIGMA_BROKER_BASE="http://127.0.0.1:$PORT" node "$SCRIPT" inspect 'https://figma.com/design/AbC123/Footer?node-id=10-20' 2>&1)"
RC=$?
set -e
[ "$RC" -eq 3 ] || fail "unconnected OAuth should exit 3, got $RC"
has "$OUT" '/figma/oauth/start' "authorization error includes connection URL"
has "$OUT" 'https://access.example/figma/oauth/start' "connection URL uses the Access app, not the request-base override"
has "$OUT" 'your Figma account' "authorization error names per-user connection"

echo "figma-inspect tests passed"
