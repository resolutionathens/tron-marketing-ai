#!/usr/bin/env bash
# Smoke for preview-url.sh. Detection is pure filesystem signal-matching, so it
# is fully testable offline: build temp repos carrying each signal and assert
# the detected target + the ok/url/reason semantics. URL resolution (gh/flyctl)
# is best-effort and not asserted here — without a registered deployment it
# correctly degrades to url:null with a routing reason.
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

# vercel.json → vercel
D="$(mk vercel)"; echo '{}' > "$D/vercel.json"
O="$(run "$D")"; echo "  → $O"
has "$O" '"target":"vercel"' "vercel.json should detect vercel"
has "$O" '"ok":true' "vercel ok"
pass "vercel.json → vercel"

# netlify.toml → netlify
D="$(mk netlify)"; echo '' > "$D/netlify.toml"
O="$(run "$D")"; has "$O" '"target":"netlify"' "netlify.toml should detect netlify"
pass "netlify.toml → netlify"

# fly.toml → fly (no flyctl in test → default .fly.dev host from app name)
D="$(mk fly)"; printf 'app = "my-app"\n' > "$D/fly.toml"
O="$(run "$D")"; echo "  → $O"
has "$O" '"target":"fly"' "fly.toml should detect fly"
has "$O" 'my-app.fly.dev' "fly should derive the default host from app name"
pass "fly.toml → fly (default host from app name)"

# wrangler.toml with no Pages markers → cf-workers, the no-preview verdict
D="$(mk workers)"; printf 'name = "svc"\nmain = "src/index.ts"\n' > "$D/wrangler.toml"
O="$(run "$D")"; echo "  → $O"
has "$O" '"target":"cf-workers"' "bare wrangler.toml → cf-workers"
has "$O" '"url":null' "cf-workers has no preview URL"
has "$O" 'no per-PR preview' "cf-workers should state the gotcha up front"
has "$O" '"ok":true' "cf-workers is a real answer, not a failure"
pass "bare wrangler.toml → cf-workers (states the no-preview gotcha)"

# wrangler.jsonc WITH a Pages marker → cf-pages
D="$(mk pages)"; printf '{ "pages_build_output_dir": "dist" }\n' > "$D/wrangler.jsonc"
O="$(run "$D")"; echo "  → $O"
has "$O" '"target":"cf-pages"' "wrangler + pages_build_output_dir → cf-pages"
pass "wrangler.jsonc + Pages marker → cf-pages"

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

# precedence: vercel.json wins over a co-present wrangler.toml
D="$(mk both)"; echo '{}' > "$D/vercel.json"; echo 'name="x"' > "$D/wrangler.toml"
O="$(run "$D")"; has "$O" '"target":"vercel"' "vercel.json should win over wrangler.toml"
pass "precedence — vercel.json wins over wrangler.toml"

echo ""
echo "✅ preview-url smoke PASSED ($PASS checks)"
