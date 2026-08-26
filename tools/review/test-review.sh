#!/usr/bin/env bash
# Hermetic smoke for tools/review/review.mjs (MD-2749). No network: a stub control
# plane on 127.0.0.1:0 stands in for the real API, so every branch of the exit-code
# contract is exercised without a dispatch, a worker, or tron-os.
#
# The exit codes ARE the contract — tron:git-pr Step 1c branches on them, and a client
# that reported "settled" for a review that never ran would send a worker to the PR on
# the strength of nothing. That is what these assertions defend.
#
#   bash tools/review/test-review.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CLI="$HERE/review.mjs"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tron-review-smoke.XXXXXX")"
# `wait` inside the same subshell as the kill keeps bash's job-control notice
# ("Terminated: 15") off CI's stderr, which would otherwise read as a failure.
cleanup() { if [ -n "${SRV_PID:-}" ]; then { kill "$SRV_PID"; wait "$SRV_PID"; } 2>/dev/null; fi; rm -rf "$TMP"; }
trap cleanup EXIT

PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
# check <label> <needle> <haystack>
check() { case "$3" in *"$2"*) pass "$1" ;; *) fail "$1 — expected \"$2\" in: $3" ;; esac; }
# rc_of <expected> <label> -- <cmd...>
rc_of() { local want="$1" label="$2"; shift 3; local rc=0; "$@" >/dev/null 2>&1 || rc=$?; [ "$rc" = "$want" ] || fail "$label — expected exit $want, got $rc"; pass "$label"; }

command -v node >/dev/null 2>&1 || { echo "review smoke: SKIPPED — node not on PATH"; exit 0; }

echo "review CLI smoke: tmp=$TMP"

# ---- stub control plane -------------------------------------------------------
# Behaviour is switched by the dispatch id in the URL, so one server covers every
# case and each assertion just picks the id that provokes the branch it wants.
cat > "$TMP/server.mjs" <<'EOF'
import { createServer } from "node:http";
import { appendFileSync } from "node:fs";

const RESPONSES = {
  // settled, no findings → exit 0
  "d-settled": [200, { text: "Round 3: nothing further.", round: { status: "completed", findings: [] },
                       localReview: { settled: true, roundsRemaining: 0, roundsSpent: 3 } }],
  // findings present → exit 1, and the text carries the OS-side bun command
  "d-findings": [200, { text: "Round 1: 1 finding.\n  bun run review:disposition --finding f1 --fixed|--skipped|--disagreed --note \"<why>\"\nNext: run the `review:disposition` line, then `review:local`.",
                        round: { status: "completed", findings: [{ id: "f1", category: "correctness", severity: "high", file: "a.ts", line: 2, issue: "boom" }] },
                        localReview: { settled: false, roundsRemaining: 2, roundsSpent: 1 } }],
  // the review did not run → recorded FAILED, exit 1, never "clean"
  "d-failed":  [200, { text: "Round 1 FAILED.", round: { status: "failed", failureReason: "reviewer session died", findings: [] } }],
  // all three rounds spent → terminal but NOT an error, exit 0
  "d-409":     [409, { error: "All local review rounds are spent. Run `bun run review:local` no more." }],
  // server-side error → exit 2, not a clean review
  "d-500":     [500, { error: "internal" }],
  // an older control plane that returns no rendered `text`
  "d-notext":  [200, { round: { status: "completed", findings: [] } }],
};

const srv = createServer((req, res) => {
  const u = new URL(req.url, "http://x");
  const m = u.pathname.match(/^\/api\/dispatches\/([^/]+)\/local-review(\/findings\/([^/]+)\/disposition|\/final-remediation|\/failed-final-recovery)?$/);
  if (req.method !== "POST" || !m) { res.writeHead(404); res.end("{}"); return; }
  const [, id, suffix, findingId] = m;
  let raw = "";
  req.on("data", (c) => (raw += c));
  req.on("end", () => {
    appendFileSync(process.env.BODY_LOG, `${u.pathname} ${raw}\n`);
    if (suffix === "/final-remediation") {
      if (id === "d-500") { res.writeHead(400, {"content-type":"application/json"}); res.end('{"error":"unresolved target"}'); return; }
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ localReview: { allowsPr: true } }));
      return;
    }
    if (suffix === "/failed-final-recovery") {
      if (id === "d-500") { res.writeHead(400, {"content-type":"application/json"}); res.end('{"error":"recovery not allowed"}'); return; }
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ localReview: { allowsPr: true } }));
      return;
    }
    if (findingId) {
      if (id === "d-500") { res.writeHead(400, {"content-type":"application/json"}); res.end('{"error":"unknown finding"}'); return; }
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ localReview: { roundsRemaining: id === "d-final" ? 1 : 2 } }));
      return;
    }
    const [code, body] = RESPONSES[id] || [200, { round: { status: "completed", findings: [] } }];
    res.writeHead(code, { "content-type": "application/json" });
    res.end(JSON.stringify(body));
  });
});
srv.listen(0, "127.0.0.1", () => process.stdout.write(String(srv.address().port) + "\n"));
EOF

export BODY_LOG="$TMP/bodies.log"; : > "$BODY_LOG"
node "$TMP/server.mjs" > "$TMP/port" &
SRV_PID=$!
for _ in $(seq 1 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
PORT="$(cat "$TMP/port")"
[ -n "$PORT" ] || fail "stub control plane did not start"
API="http://127.0.0.1:$PORT"

run() { # run <dispatch-id> <args...>
  local id="$1"; shift
  env TRON_DISPATCH_ID="$id" TRON_API_URL="$API" node "$CLI" "$@"
}

# ---- exit-code contract: the three states a worker branches on ----------------
out="$(run d-settled local)"; rc=$?
[ "$rc" = 0 ] || fail "settled review must exit 0, got $rc"
check "settled round prints the OS text" "nothing further" "$out"
pass "local: settled → exit 0"

rc_of 1 "local: findings to address → exit 1" -- run d-findings local
rc_of 1 "local: review that could not run is FAILED, never clean → exit 1" -- run d-failed local
rc_of 2 "local: server error → exit 2 (not a clean review)" -- run d-500 local

# 409 is a normal terminal outcome, not an error — the round budget is simply spent.
out="$(run d-409 local)"; rc=$?
[ "$rc" = 0 ] || fail "409 all-rounds-spent must exit 0, got $rc"
check "409 prints the reason" "rounds are spent" "$out"
pass "local: 409 all rounds spent → exit 0, reported not thrown"

# ---- MD-2749: printed commands must resolve HERE, not in tron-os --------------
# The OS renders `bun run review:disposition …` because it is written for a worker
# sitting in tron-os. A worker in marketing-pages copying that line runs nothing.
out="$(run d-findings local || true)"
case "$out" in *"bun run review:"*) fail "server-side 'bun run review:*' must be rewritten to a resolvable command — got: $out" ;; esac
check "disposition command is localized" "$CLI disposition" "$out"
check "re-review command is localized"  "$CLI local"       "$out"
pass "local: OS-side bun commands are rewritten to this CLI's own invocation"

out="$(run d-409 local)"
case "$out" in *"bun run review:"*) fail "409 text must be localized too — got: $out" ;; esac
pass "local: the 409 message is localized as well"

# TRON_REVIEW_CMD lets a harness present its own wrapper instead of a raw node path.
out="$(env TRON_DISPATCH_ID=d-findings TRON_API_URL="$API" TRON_REVIEW_CMD="tron-review" node "$CLI" local || true)"
check "TRON_REVIEW_CMD overrides the printed invocation" "tron-review disposition" "$out"
pass "local: TRON_REVIEW_CMD overrides the rendered command"

# ---- a response with no `text` falls back to the raw round ---------------------
# tron-os `review-local.ts` does `body.text ?? JSON.stringify(body.round)`; matching it
# means an older control plane that omits `text` still tells the worker something.
out="$(run d-notext local)"; rc=$?
[ "$rc" = 0 ] || fail "no-findings round without text must exit 0, got $rc"
check "falls back to the raw round when text is absent" '"status": "completed"' "$out"
pass "local: response without \`text\` falls back to the serialized round"

# ---- --verified is repeatable and reaches the server as a claim ---------------
: > "$BODY_LOG"
run d-settled local --verified "bun run test: 10 pass" --verified "typecheck clean" >/dev/null
body="$(cat "$BODY_LOG")"
check "--verified #1 forwarded" "10 pass" "$body"
check "--verified #2 forwarded" "typecheck clean" "$body"
pass "local: --verified is repeatable and forwarded verbatim"

# ---- disposition ---------------------------------------------------------------
: > "$BODY_LOG"
out="$(run d-findings disposition --finding f1 --fixed --note "narrowed the guard")"; rc=$?
[ "$rc" = 0 ] || fail "a valid disposition must exit 0, got $rc"
check "disposition confirms what was recorded" "Recorded fixed for finding f1" "$out"
check "disposition posts to the per-finding route" "/findings/f1/disposition" "$(cat "$BODY_LOG")"
check "disposition forwards the note" "narrowed the guard" "$(cat "$BODY_LOG")"
check "round one disposition names the next review" "for your next review" "$out"
pass "disposition: valid call posts to the per-finding route and exits 0"

out="$(run d-final disposition --finding f2 --fixed --note "narrowed the guard")"; rc=$?
[ "$rc" = 0 ] || fail "a round-two disposition must exit 0, got $rc"
check "round two disposition names the final review" "for your final review" "$out"
pass "disposition: transition wording reflects the remaining review round"

rc_of 2 "disposition: missing --finding → exit 2"      -- run d-findings disposition --fixed --note n
rc_of 2 "disposition: missing --note → exit 2"         -- run d-findings disposition --finding f1 --fixed
rc_of 2 "disposition: blank --note → exit 2"           -- run d-findings disposition --finding f1 --fixed --note "   "
rc_of 2 "disposition: no disposition flag → exit 2"    -- run d-findings disposition --finding f1 --note n
rc_of 2 "disposition: two disposition flags → exit 2"  -- run d-findings disposition --finding f1 --fixed --skipped --note n
rc_of 1 "disposition: server rejection → exit 1"       -- run d-500 disposition --finding f1 --fixed --note n

# --disagreed must be as recordable as --fixed: a reasoned push-back is a signal
# about the RULE, and a client that only accepted agreement would erase it.
out="$(run d-findings disposition --finding f2 --disagreed --note "rule does not apply to generated code")"
check "disagreed is recordable" "Recorded disagreed for finding f2" "$out"
pass "disposition: --disagreed records like any other verdict"

# ---- final remediation --------------------------------------------------------
: > "$BODY_LOG"
out="$(run d-findings remediation --target finding:f3 --repair "narrowed the guard" --verification "bash tools/review/test-review.sh: passed")"; rc=$?
[ "$rc" = 0 ] || fail "valid final remediation must exit 0, got $rc"
check "final remediation confirms the recorded target" "Recorded final remediation for finding:f3" "$out"
check "final remediation posts to its route" "/local-review/final-remediation" "$(cat "$BODY_LOG")"
check "final remediation forwards repair evidence" "narrowed the guard" "$(cat "$BODY_LOG")"
check "final remediation forwards verification evidence" "test-review.sh: passed" "$(cat "$BODY_LOG")"
pass "remediation: records repair and verification evidence"

rc_of 2 "remediation: missing target → exit 2" -- run d-findings remediation --repair x --verification y
rc_of 2 "remediation: missing repair → exit 2" -- run d-findings remediation --target finding:f3 --verification y
rc_of 2 "remediation: missing verification → exit 2" -- run d-findings remediation --target finding:f3 --repair x
rc_of 1 "remediation: server rejection → exit 1" -- run d-500 remediation --target finding:f3 --repair x --verification y

# ---- terminal failed-review recovery -----------------------------------------
: > "$BODY_LOG"
out="$(run d-findings recovery --failed-review-reason "review artifact was invalid with no repair target" --verification "bash tools/review/test-review.sh: passed")"; rc=$?
[ "$rc" = 0 ] || fail "valid failed-review recovery must exit 0, got $rc"
check "recovery confirms the recorded evidence" "Recorded failed final-review recovery" "$out"
check "recovery posts to its route" "/local-review/failed-final-recovery" "$(cat "$BODY_LOG")"
check "recovery forwards the failure reason" "invalid with no repair target" "$(cat "$BODY_LOG")"
check "recovery forwards verification evidence" "test-review.sh: passed" "$(cat "$BODY_LOG")"
pass "recovery: records terminal failed-review evidence"

rc_of 2 "recovery: missing failure reason → exit 2" -- run d-findings recovery --verification y
rc_of 2 "recovery: missing verification → exit 2" -- run d-findings recovery --failed-review-reason x
rc_of 1 "recovery: server rejection → exit 1" -- run d-500 recovery --failed-review-reason x --verification y

# ---- no dispatch env: cannot run, and says so --------------------------------
rc_of 2 "local without TRON_DISPATCH_ID → exit 2"       -- env -u TRON_DISPATCH_ID TRON_API_URL="$API" node "$CLI" local
rc_of 2 "disposition without TRON_DISPATCH_ID → exit 2" -- env -u TRON_DISPATCH_ID TRON_API_URL="$API" node "$CLI" disposition --finding f1 --fixed --note n

# ---- unreachable control plane: exit 2, never a silent pass ------------------
rc_of 2 "unreachable API → exit 2" -- env TRON_DISPATCH_ID=d1 TRON_API_URL="http://127.0.0.1:1" node "$CLI" local
out="$(env TRON_DISPATCH_ID=d1 TRON_API_URL="http://127.0.0.1:1" node "$CLI" local 2>&1 || true)"
check "unreachable API warns against opening a PR" "NOT a clean review" "$out"
pass "local: an unreachable control plane is never mistaken for a clean review"

# ---- usage surface -------------------------------------------------------------
rc_of 2 "unknown subcommand → exit 2" -- run d1 bogus
out="$(run d1 --help)"
check "help documents local" " local" "$out"
check "help documents disposition" " disposition" "$out"
check "help documents remediation" " remediation" "$out"
check "help documents recovery" " recovery" "$out"
check "help states the three-round policy" "There is no fourth round" "$out"
pass "help → prints usage (exit 0)"

echo ""
echo "✅ review CLI smoke PASSED ($PASS checks)"
