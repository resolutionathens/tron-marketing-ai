#!/usr/bin/env bash
# Smoke for content.sh + content-lib.sh — the deterministic backbone shared by
# tron:toolkit-item, news-item, and guide-item. Everything here is offline:
# slug derivation, the facilitron.com→relative rewrite, internal-path resolution
# against a temp pages/ tree, next-index, the repo guard, and the usage contract.
#
#   bash tools/content/test-content.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/content.sh"
LIB="$HERE/content-lib.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/content-smoke.XXXXXX")"
ROOT="$(cd "$ROOT" && pwd -P)"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT
has() { grep -qF "$2" <<<"$1" || fail "$3 — got: $1"; }

echo "content smoke: root=$ROOT"

# --- content-lib pure functions ----------------------------------------------
# shellcheck source=/dev/null
source "$LIB"

[[ "$(ct_slug 'How to Prepare a Preventive Maintenance Plan')" == how-to-prepare-a-preventive-maintenance-plan ]] \
  || fail "ct_slug basic title"
[[ "$(ct_slug '  Cluster: HVAC & Air-Quality!! ')" == cluster-hvac-air-quality ]] \
  || fail "ct_slug punctuation/edges (got: $(ct_slug '  Cluster: HVAC & Air-Quality!! '))"
pass "ct_slug → lowercase, hyphenated, trimmed"

OUT="$(printf 'See [Works](https://www.facilitron.com/product/works) and [T](https://facilitron.com/resources/toolkit/x).\nExternal https://example.com/facilitron.com/y stays.\n' | ct_rewrite_links)"
has "$OUT" '[Works](/product/works)' "rewrites www. URL to relative"
has "$OUT" '[T](/resources/toolkit/x)' "rewrites bare-domain URL to relative"
has "$OUT" 'https://example.com/facilitron.com/y stays' "leaves external URLs alone"
pass "ct_rewrite_links → only facilitron.com absolute URLs become relative"

printf 'guide-01.webp\nguide-02.webp\nguide-04.webp\nother.png\n' > "$ROOT/names.txt"
[[ "$(ct_next_index guide .webp < "$ROOT/names.txt")" == 05 ]] || fail "ct_next_index should be 05"
[[ "$(printf '' | ct_next_index guide .webp)" == 01 ]] || fail "ct_next_index empty → 01"
pass "ct_next_index → next zero-padded index (05; 01 when none)"

# --- check-link against a temp pages/ tree -----------------------------------
mkdir -p "$ROOT/pages/product/works" "$ROOT/pages/resources/news"
: > "$ROOT/pages/product/works/index.vue"
: > "$ROOT/pages/product/facilitron-fit.vue"
: > "$ROOT/pages/resources/news/[...slug].vue"
[[ -n "$(ct_resolve_page /product/works "$ROOT")" ]] || fail "should resolve dir/index.vue"
[[ -n "$(ct_resolve_page /product/facilitron-fit "$ROOT")" ]] || fail "should resolve foo.vue"
[[ -n "$(ct_resolve_page /resources/news/some-article "$ROOT")" ]] || fail "should resolve via [...slug].vue catch-all"
ct_resolve_page /product/scheduling-and-reservations "$ROOT" >/dev/null 2>&1 && fail "missing route should not resolve"
pass "ct_resolve_page → foo.vue, foo/index.vue, and [...slug].vue catch-all"

# --- Nuxt 4 srcDir layout: app/pages/ takes precedence over pages/ ----------
ROOT4="$(mktemp -d "${TMPDIR:-/tmp}/content-smoke4.XXXXXX")"
ROOT4="$(cd "$ROOT4" && pwd -P)"
mkdir -p "$ROOT4/app/pages/product/works"
: > "$ROOT4/app/pages/product/works/index.vue"
[[ -n "$(ct_resolve_page /product/works "$ROOT4")" ]] || fail "should resolve app/pages/ route (Nuxt 4 srcDir)"
rm -rf "$ROOT4"
pass "ct_resolve_page → checks app/pages/ first for Nuxt 4 repos"

O="$(bash "$SCRIPT" check-link /product/works --repo "$ROOT")"; echo "  → $O"
has "$O" '"exists":true' "check-link known route exists"
has "$O" 'product/works/index.vue' "check-link reports the resolved file"
pass "check-link <known> → exists:true + resolved file"

O="$(bash "$SCRIPT" check-link /product/scheduling-and-reservations --repo "$ROOT" 2>/dev/null || true)"; echo "  → $O"
has "$O" '"exists":false' "check-link unknown route → exists:false"
pass "check-link <missing> → exists:false (would 404 the prerender)"

# --- check-repo --------------------------------------------------------------
git -C "$ROOT" init -q
git -C "$ROOT" remote add origin 'git@github.com:Facilitron/marketing-pages.git'
O="$(bash "$SCRIPT" check-repo --repo "$ROOT")"; echo "  → $O"
has "$O" '"isMarketingPages":true' "marketing-pages remote passes the guard"
pass "check-repo (marketing-pages remote) → isMarketingPages:true"

git -C "$ROOT" remote set-url origin 'git@github.com:Facilitron/some-other-repo.git'
O="$(bash "$SCRIPT" check-repo --repo "$ROOT" 2>/dev/null || true)"; echo "  → $O"
has "$O" '"isMarketingPages":false' "other repo fails the guard"
pass "check-repo (other remote) → isMarketingPages:false (ok:false)"

# --- slug subcommand + rewrite-links in place --------------------------------
O="$(bash "$SCRIPT" slug 'Standard Operating Procedure: Lockdown')"
has "$O" '"slug":"standard-operating-procedure-lockdown"' "slug subcommand"
pass "slug \"<title>\" → {ok,slug}"

cat > "$ROOT/doc.md" <<'MD'
Read [the guide](https://www.facilitron.com/resources/guides/x) today.
MD
O="$(bash "$SCRIPT" rewrite-links "$ROOT/doc.md")"; echo "  → $O"
has "$O" '"rewritten":1' "reports one rewrite"
grep -qF '[the guide](/resources/guides/x)' "$ROOT/doc.md" || fail "file should be rewritten in place"
pass "rewrite-links <file> → in-place facilitron.com→relative"

# --- usage / error contract --------------------------------------------------
rc=0; bash "$SCRIPT" slug >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "slug without title should exit 2 (got $rc)"
rc=0; bash "$SCRIPT" next-index --prefix guide >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "next-index without --suffix should exit 2 (got $rc)"
rc=0; bash "$SCRIPT" bogus >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "unknown subcommand should exit 2 (got $rc)"
pass "usage contract → exit 2 on missing args / unknown subcommand"

echo ""
echo "✅ content smoke PASSED ($PASS checks)"
