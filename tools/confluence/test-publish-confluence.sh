#!/usr/bin/env bash
set -euo pipefail

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/confluence-publish-test.XXXXXX")"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/publish-confluence.mjs"
PASS=0
cleanup() { trash "$ROOT" >/dev/null 2>&1 || true; }
trap cleanup EXIT
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
has() { printf '%s' "$1" | rg -q -F -- "$2" || fail "$3: $1"; }

mkdir -p "$ROOT/bin"
printf '<p>Finished deliverable</p>\n' > "$ROOT/deliverable.html"

cat > "$ROOT/bin/cloudflared" <<'SH'
#!/usr/bin/env bash
[[ "${STUB_AUTH_FAIL:-0}" == 1 ]] && exit 1
printf '%s\n' 'broker-access-token'
SH
chmod +x "$ROOT/bin/cloudflared"

cat > "$ROOT/mock-server.mjs" <<'JS'
import http from 'node:http';
import fs from 'node:fs';

const log = process.env.REQUEST_LOG;
const server = http.createServer((req, res) => {
  let body = '';
  req.setEncoding('utf8');
  req.on('data', chunk => { body += chunk; });
  req.on('end', () => {
    fs.appendFileSync(log, `${JSON.stringify({ method: req.method, url: req.url, authorization: req.headers['cf-access-token'], body })}\n`);
    if (req.url === '/jira/wiki/api/v2/pages/9001' && req.method === 'GET') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ id: '9001', title: 'Existing title', version: { number: 6 } }));
      return;
    }
    if (req.method === 'POST') {
      res.writeHead(201, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ id: '4242', title: 'Quarterly plan', version: { number: 1 }, _links: { webui: '/spaces/MKT/pages/4242/Quarterly+plan' } }));
      return;
    }
    if (req.method === 'PUT') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ id: '9001', title: 'Revised plan', version: { number: 7 }, _links: { webui: '/spaces/MKT/pages/9001/Revised+plan' } }));
      return;
    }
    res.writeHead(404, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ message: 'not found' }));
  });
});
server.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(process.env.PORT_FILE, String(server.address().port));
});
JS

: > "$ROOT/requests.jsonl"
PORT_FILE="$ROOT/port" REQUEST_LOG="$ROOT/requests.jsonl" node "$ROOT/mock-server.mjs" &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true; cleanup' EXIT
while [[ ! -s "$ROOT/port" ]]; do sleep 0.05; done
BASE="http://127.0.0.1:$(cat "$ROOT/port")/jira"

run_publish() {
  PATH="$ROOT/bin:$PATH" CONFLUENCE_BROKER_BASE="$BASE" CONFLUENCE_SITE_BASE="https://facilitron.atlassian.net/wiki" node "$SCRIPT" "$@"
}

rg -q -F "'CF-Access-Token': token" "$SCRIPT" || fail "publisher must use the broker contract's canonical auth header"
! rg -q -F "'Cf-Access-Jwt-Assertion':" "$SCRIPT" || fail "publisher must not use the browser-session assertion header"
pass "authentication uses the broker contract's CF-Access-Token header"

OUT="$(run_publish create --space-id 111 --parent-id 222 --title 'Quarterly plan' --body-file "$ROOT/deliverable.html")"
[[ "$OUT" == '{"ok":true,"action":"create","pageId":"4242","version":1,"title":"Quarterly plan","url":"https://facilitron.atlassian.net/wiki/spaces/MKT/pages/4242/Quarterly+plan"}' ]] || fail "create should return exact destination metadata: $OUT"
CREATE_REQ="$(sed -n '1p' "$ROOT/requests.jsonl")"
node -e 'const r=JSON.parse(process.argv[1]), b=JSON.parse(r.body); if(r.method!=="POST"||r.url!=="/jira/wiki/api/v2/pages"||r.authorization!=="broker-access-token"||b.spaceId!=="111"||b.parentId!=="222"||b.title!=="Quarterly plan"||b.body?.representation!=="storage"||b.body?.value!=="<p>Finished deliverable</p>\n") process.exit(1)' "$CREATE_REQ" || fail "create request should use the explicit destination and exact body"
pass "create posts to the explicit space and parent and returns exact metadata"

OUT="$(run_publish update --page-id 9001 --title 'Revised plan' --body-file "$ROOT/deliverable.html")"
[[ "$OUT" == '{"ok":true,"action":"update","pageId":"9001","version":7,"title":"Revised plan","url":"https://facilitron.atlassian.net/wiki/spaces/MKT/pages/9001/Revised+plan"}' ]] || fail "update should return exact destination metadata: $OUT"
GET_REQ="$(sed -n '2p' "$ROOT/requests.jsonl")"
PUT_REQ="$(sed -n '3p' "$ROOT/requests.jsonl")"
node -e 'const r=JSON.parse(process.argv[1]); if(r.method!=="GET"||r.url!=="/jira/wiki/api/v2/pages/9001") process.exit(1)' "$GET_REQ" || fail "update should fetch only the explicit page id"
node -e 'const r=JSON.parse(process.argv[1]), b=JSON.parse(r.body); if(r.method!=="PUT"||r.url!=="/jira/wiki/api/v2/pages/9001"||b.id!=="9001"||b.version?.number!==7||b.title!=="Revised plan") process.exit(1)' "$PUT_REQ" || fail "update should target the same id and increment its version"
[[ "$(wc -l < "$ROOT/requests.jsonl" | tr -d ' ')" == 3 ]] || fail "update must not issue a title search or create request"
pass "update targets one explicit page id without title lookup or duplicate creation"

rc=0
ERR="$(run_publish create --space-id 111 --title MissingParent --body-file "$ROOT/deliverable.html" 2>&1)" || rc=$?
[[ "$rc" == 2 ]] || fail "missing parent should exit 2, got $rc"
has "$ERR" '--parent-id is required for create' "invalid destination should name the missing field"
[[ "$(wc -l < "$ROOT/requests.jsonl" | tr -d ' ')" == 3 ]] || fail "invalid destination must fail before any request"
pass "invalid destination fails before network access"

rc=0
ERR="$(run_publish update --page-id 'not-an-id' --title BadId --body-file "$ROOT/deliverable.html" 2>&1)" || rc=$?
[[ "$rc" == 2 ]] || fail "non-numeric page id should exit 2, got $rc"
has "$ERR" '--page-id must be a numeric Confluence ID' "invalid page id should be rejected exactly"
[[ "$(wc -l < "$ROOT/requests.jsonl" | tr -d ' ')" == 3 ]] || fail "invalid page id must fail before any request"
pass "non-numeric destination is rejected before network access"

rc=0
ERR="$(PATH="$ROOT/bin:$PATH" STUB_AUTH_FAIL=1 CONFLUENCE_BROKER_BASE="$BASE" node "$SCRIPT" create --space-id 111 --parent-id 222 --title T --body-file "$ROOT/deliverable.html" 2>&1)" || rc=$?
[[ "$rc" == 1 ]] || fail "auth failure should exit 1, got $rc"
has "$ERR" 'could not authenticate with the Atlassian broker' "auth failure should be actionable"
has_secret="$(printf '%s' "$ERR" | rg 'broker-access-token|JIRA_API_TOKEN|ATLASSIAN_EMAIL' || true)"
[[ -z "$has_secret" ]] || fail "auth failure exposed credential material: $has_secret"
pass "authentication failure is explicit and exposes no credentials"

[[ -f "$ROOT/deliverable.html" ]] || fail "caller-owned deliverable should remain in place"
[[ -z "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type f -name '*confluence-publish*' -print -quit)" ]] || fail "publisher left a completed deliverable in temporary storage"
pass "publishing creates no temporary deliverable copy"

echo "Confluence publish tests passed ($PASS checks)."
