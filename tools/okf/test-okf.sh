#!/usr/bin/env bash
# Hermetic smoke test for okf.mjs (MD-1997). Stands up a tiny stub of the MD-1988
# control-plane OKF surface (GET /api/okf/select, POST /api/okf/load) on localhost,
# points TRON_API_URL at it, and asserts the client's select-then-load behavior plus
# its failure modes. No network, no tron-os, no cloudflared — pure loopback.
#
# Full-skill integration (manual): with a real dispatched worker whose env has
# TRON_API_URL, run  `node tools/okf/okf.mjs select --type Policy`  then
# `node tools/okf/okf.mjs query --tags git --limit 2` and confirm real playbooks come back.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
OKF="$DIR/okf.mjs"
TMP="$(mktemp -d)"
SRV_PID=""
cleanup() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

pass=0; fail=0
check() { # <label> <expected-substring> <actual>
  if [[ "$3" == *"$2"* ]]; then echo "ok: $1"; pass=$((pass+1)); else
    echo "FAIL: $1"; echo "  expected to contain: [$2]"; echo "  actual: [$3]"; fail=$((fail+1)); fi
}
check_missing() { # <label> <unexpected-substring> <actual>
  if [[ "$3" != *"$2"* ]]; then echo "ok: $1"; pass=$((pass+1)); else
    echo "FAIL: $1"; echo "  expected NOT to contain: [$2]"; echo "  actual: [$3]"; fail=$((fail+1)); fi
}

# ── stub server: mirrors routes/okf.ts shapes ────────────────────────────────
cat > "$TMP/server.mjs" <<'EOF'
import { createServer } from "node:http";
const CONCEPTS = [
  { id: "policy/git-flow", type: "Policy", tags: ["git", "lifecycle"], title: "Git flow policy", description: null, timestamp: null },
  { id: "policy/no-em-dash", type: "Policy", tags: ["writing"], title: "No em dashes", description: null, timestamp: null },
  { id: "role/worker", type: "Role", tags: ["git"], title: "Worker role overlay", description: null, timestamp: null },
];
const BODIES = {
  "policy/git-flow": "# Git flow\nCommit then PR. Never merge to prod.",
  "policy/no-em-dash": "# No em dashes\nUse commas.",
  "role/worker": "# Worker\nFile follow-ups.",
};
function applyQuery(list, { type, tags, idPrefix }) {
  return list.filter((e) => {
    if (type && e.type !== type) return false;
    if (idPrefix && !e.id.startsWith(idPrefix)) return false;
    if (tags && tags.length) { const s = new Set(e.tags); if (!tags.every((t) => s.has(t))) return false; }
    return true;
  });
}
const srv = createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  if (req.method === "GET" && u.pathname === "/api/okf/select") {
    const tagsRaw = u.searchParams.get("tags");
    const q = {
      type: u.searchParams.get("type") || undefined,
      idPrefix: u.searchParams.get("idPrefix") || undefined,
      tags: tagsRaw ? tagsRaw.split(",").map((t) => t.trim()).filter(Boolean) : undefined,
    };
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ concepts: applyQuery(CONCEPTS, q) }));
    return;
  }
  if (req.method === "POST" && u.pathname === "/api/okf/load") {
    let raw = ""; req.on("data", (c) => (raw += c)); req.on("end", () => {
      let ids = [];
      try { ids = JSON.parse(raw).ids || []; } catch { res.writeHead(400); res.end('{"error":"bad"}'); return; }
      const bodies = {};
      for (const id of ids) if (id in BODIES) bodies[id] = BODIES[id];
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ bodies }));
    });
    return;
  }
  res.writeHead(404); res.end("{}");
});
srv.listen(0, "127.0.0.1", () => { process.stdout.write(String(srv.address().port) + "\n"); });
EOF

node "$TMP/server.mjs" > "$TMP/port" &
SRV_PID=$!
for _ in $(seq 1 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
PORT="$(cat "$TMP/port")"
[ -n "$PORT" ] || { echo "FAIL: stub server did not start"; exit 1; }
export TRON_API_URL="http://127.0.0.1:$PORT"

# ── select: type filter, no bodies ──────────────────────────────────────────
out="$(node "$OKF" select --type Policy)"
check "select --type Policy lists git-flow" "policy/git-flow" "$out"
check "select --type Policy lists no-em-dash" "policy/no-em-dash" "$out"
check_missing "select excludes Role type" "role/worker" "$out"
check_missing "select returns no bodies" "Commit then PR" "$out"

# ── select: tags AND semantics ───────────────────────────────────────────────
out="$(node "$OKF" select --tags git)"
check "select --tags git includes policy/git-flow" "policy/git-flow" "$out"
check "select --tags git includes role/worker" "role/worker" "$out"
check_missing "select --tags git excludes writing-only" "no-em-dash" "$out"

# ── select: idPrefix ─────────────────────────────────────────────────────────
out="$(node "$OKF" select --id-prefix role/)"
check "select --id-prefix role/ matches role/worker" "role/worker" "$out"
check_missing "select --id-prefix role/ excludes policy" "policy/git-flow" "$out"

# ── select: no match ─────────────────────────────────────────────────────────
out="$(node "$OKF" select --type Nonexistent)"
check "select no-match message" "No OKF concepts matched" "$out"

# ── load: bodies for specific ids ────────────────────────────────────────────
out="$(node "$OKF" load policy/git-flow)"
check "load returns body" "Commit then PR" "$out"
check "load headers the id" "===== policy/git-flow" "$out"

# ── load: missing id reported ────────────────────────────────────────────────
out="$(node "$OKF" load policy/git-flow policy/ghost 2>&1)"
check "load reports missing id" "not found: policy/ghost" "$out"

# ── load: --json ─────────────────────────────────────────────────────────────
out="$(node "$OKF" load policy/no-em-dash --json)"
check "load --json returns keyed bodies" '"policy/no-em-dash"' "$out"

# ── query: select then load in one shot ──────────────────────────────────────
out="$(node "$OKF" query --type Policy)"
check "query loads git-flow body" "Commit then PR" "$out"
check "query loads no-em-dash body" "Use commas" "$out"

# ── query: --limit caps + warns ──────────────────────────────────────────────
out="$(node "$OKF" query --type Policy --limit 1)"
check "query --limit warns about truncation" "not loaded" "$out"

# ── query: refuses an unfiltered pull ────────────────────────────────────────
set +e
out="$(node "$OKF" query 2>&1)"; rc=$?
set -e
check "query with no filter errors" "needs at least one filter" "$out"
[ "$rc" -eq 2 ] && { echo "ok: query no-filter exit 2"; pass=$((pass+1)); } || { echo "FAIL: query no-filter exit ($rc)"; fail=$((fail+1)); }

# ── no base URL → clear error, exit 3 ────────────────────────────────────────
set +e
out="$(env -u TRON_API_URL node "$OKF" select --type Policy 2>&1)"; rc=$?
set -e
check "missing base URL message" "TRON_API_URL" "$out"
[ "$rc" -eq 3 ] && { echo "ok: no-url exit 3"; pass=$((pass+1)); } || { echo "FAIL: no-url exit ($rc)"; fail=$((fail+1)); }

# ── --api-url overrides env ──────────────────────────────────────────────────
out="$(env -u TRON_API_URL node "$OKF" select --type Role --api-url "http://127.0.0.1:$PORT")"
check "--api-url override works" "role/worker" "$out"

# ── network failure → exit 4 ─────────────────────────────────────────────────
set +e
out="$(node "$OKF" select --api-url "http://127.0.0.1:1" --timeout 1500 2>&1)"; rc=$?
set -e
[ "$rc" -eq 4 ] && { echo "ok: unreachable exit 4"; pass=$((pass+1)); } || { echo "FAIL: unreachable exit ($rc): $out"; fail=$((fail+1)); }

echo
echo "okf test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
