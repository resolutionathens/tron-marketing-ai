#!/usr/bin/env bash
# Smoke for preview-url.sh. Detection is pure filesystem signal-matching, so it
# is fully testable offline: build temp repos carrying each signal and assert
# the detected target + the ok/url/reason semantics.
#
# Scoped to the Facilitron stack: only Cloudflare Workers (wrangler.*) and CircleCI
# (.circleci/config.yml) are detected; everything else is `unknown`.
#
#   bash skills/preview-url/scripts/test-preview-url.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/preview-url.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/preview-url-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT

# Make a repo dir carrying the given signal files, return its path.
mk() { local d="$ROOT/$1"; mkdir -p "$d"; printf '%s\n' "$d"; }

run() { bash "$SCRIPT" --repo "$1" --branch "${2:-some-branch}"; }
has() { grep -q "$2" <<<"$1" || fail "$3 — got: $1"; }

echo "preview-url smoke: root=$ROOT"

# wrangler.toml → cf-workers, the no-preview verdict
D="$(mk workers)"; printf 'name = "svc"\nmain = "src/index.ts"\n' > "$D/wrangler.toml"
O="$(run "$D")"; echo "  → $O"
has "$O" '"target":"cf-workers"' "wrangler.toml → cf-workers"
has "$O" '"url":null' "cf-workers has no preview URL"
has "$O" 'no per-PR preview' "cf-workers should state the gotcha up front"
has "$O" '"ok":true' "cf-workers is a real answer, not a failure"
pass "wrangler.toml → cf-workers (states the no-preview gotcha)"

# wrangler.jsonc also → cf-workers (Pages isn't part of the Facilitron stack)
D="$(mk workers-jsonc)"; printf '{ "name": "svc" }\n' > "$D/wrangler.jsonc"
O="$(run "$D")"; echo "  → $O"
has "$O" '"target":"cf-workers"' "wrangler.jsonc → cf-workers"
pass "wrangler.jsonc → cf-workers"

# .circleci/config.yml → circleci, routes onward (no hardcoded URL)
D="$(mk circle)"; mkdir -p "$D/.circleci"; echo 'version: 2.1' > "$D/.circleci/config.yml"
O="$(run "$D")"; echo "  → $O"
has "$O" '"target":"circleci"' ".circleci → circleci"
has "$O" '"url":null' "circleci should route onward (no hardcoded URL guess)"
has "$O" 'table in this skill' "circleci reason points at the in-skill branch→URL table"
pass ".circleci/config.yml → circleci (routes to in-skill table, no URL guess)"

# nothing → unknown, ok:false
D="$(mk bare)"; echo '# readme' > "$D/README.md"
O="$(run "$D" 2>/dev/null || true)"; echo "  → $O"
has "$O" '"target":"unknown"' "no signal → unknown"
has "$O" '"ok":false' "unknown is a failure (ask the user)"
pass "no deploy signal → unknown (ok:false)"

# precedence: wrangler.* wins over a co-present .circleci/config.yml
D="$(mk both)"; echo 'name="x"' > "$D/wrangler.toml"; mkdir -p "$D/.circleci"; echo 'version: 2.1' > "$D/.circleci/config.yml"
O="$(run "$D")"; has "$O" '"target":"cf-workers"' "wrangler.* should win over .circleci"
pass "precedence — wrangler.* wins over .circleci"

echo ""
echo "✅ preview-url smoke PASSED ($PASS checks)"
