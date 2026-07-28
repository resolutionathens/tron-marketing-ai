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
# Nested under $ROOT so the EXIT trap always cleans it up, even on fail().
ROOT4="$ROOT/nuxt4"
mkdir -p "$ROOT4/app/pages/product/works"
: > "$ROOT4/app/pages/product/works/index.vue"
[[ -n "$(ct_resolve_page /product/works "$ROOT4")" ]] || fail "should resolve app/pages/ route (Nuxt 4 srcDir)"
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

# --- repo content profile ----------------------------------------------------
# A fixture standing in for the consuming repo's .tron/content-profile.json —
# one pipeline per valueFormat, since that field is the whole point: the same
# webp is referenced three different ways depending on how the renderer eats it.
PROF="$ROOT/.tron"
mkdir -p "$PROF"
cat > "$PROF/content-profile.json" <<'JSON'
{
  "version": 1,
  "cdn": { "baseUrl": "https://ik.imagekit.io/facilitron/" },
  "collections": {
    "toolkit": {
      "dir": "content/resources/toolkit",
      "required": ["title", "description", "date", "category"],
      "optional": ["image", "download"],
      "enums": { "category": ["sop", "checklist", "template"] }
    }
  },
  "pipelines": {
    "news": {
      "destination": "content/resources/news/{slug}.md",
      "route": "/resources/news/{slug}",
      "components": { "allowed": ["fImg"], "forbidden": ["checklist-group"] },
      "images": [
        { "role": "featured", "cdnFolder": "blog-featured", "fileName": "{slug}.webp", "valueFormat": "filename" },
        { "role": "body", "cdnFolder": "blog-posts/{slug}", "fileName": "{name}.webp", "valueFormat": "cdn-relative-path" }
      ]
    },
    "guides": {
      "destination": "app/pages/resources/guides/{slug}.vue",
      "registration": { "mode": "manual", "file": "app/pages/resources/guides/index.vue" },
      "images": [
        { "role": "og", "cdnFolder": "og", "fileName": "og-{slug}.webp", "valueFormat": "absolute-url" },
        { "role": "card", "cdnFolder": "guides", "fileName": "guide-{NN}.webp", "valueFormat": "cdn-relative-path" }
      ]
    },
    "toolkit": {
      "destination": "content/resources/toolkit/{slug}.md",
      "images": [{ "role": "card", "cdnFolder": "toolkit", "fileName": "{slug}.webp", "valueFormat": "filename" }],
      "downloads": [{ "role": "pdf", "cdnFolder": "toolkit/downloads", "fileName": "{slug}.pdf", "valueFormat": "filename" }]
    }
  }
}
JSON

O="$(bash "$SCRIPT" pipeline news --slug my-post --repo "$ROOT")"; echo "  → $O"
has "$O" '"destination":"content/resources/news/my-post.md"' "pipeline expands {slug} in destination"
has "$O" '"route":"/resources/news/my-post"' "pipeline expands {slug} in route"
pass "pipeline <name> --slug → destination/route resolved from the repo profile"

O="$(bash "$SCRIPT" pipeline guides --slug g1 --repo "$ROOT")"; echo "  → $O"
has "$O" '"destination":"app/pages/resources/guides/g1.vue"' "guides destination comes from the profile (Nuxt 4 app/ srcDir)"
has "$O" '"mode":"manual"' "guides registration mode is declared, not assumed"
pass "pipeline guides → repo-declared Vue destination + manual registration"

# The three valueFormats must produce three genuinely different strings.
O="$(bash "$SCRIPT" image news featured --slug my-post --repo "$ROOT")"; echo "  → $O"
has "$O" '"uploadFolder":"blog-featured"' "featured upload folder"
has "$O" '"reference":"my-post.webp"' "valueFormat filename → bare filename, no folder"
O="$(bash "$SCRIPT" image news body --slug my-post --name hero --repo "$ROOT")"; echo "  → $O"
has "$O" '"reference":"blog-posts/my-post/hero.webp"' "valueFormat cdn-relative-path → folder/name"
O="$(bash "$SCRIPT" image guides og --slug g1 --repo "$ROOT")"; echo "  → $O"
has "$O" '"reference":"https://ik.imagekit.io/facilitron/og/og-g1.webp"' "valueFormat absolute-url → full CDN URL"
pass "image → filename / cdn-relative-path / absolute-url each resolve differently"

O="$(bash "$SCRIPT" image guides card --index 07 --repo "$ROOT")"; echo "  → $O"
has "$O" '"uploadName":"guide-07.webp"' "{NN} expands from --index"
O="$(bash "$SCRIPT" image toolkit pdf --slug my-sop --repo "$ROOT")"; echo "  → $O"
has "$O" '"uploadFolder":"toolkit/downloads"' "downloads[] roles resolve like images[]"
pass "image → {NN} index expansion and downloads[] roles"

O="$(bash "$SCRIPT" collection toolkit --repo "$ROOT")"; echo "  → $O"
has "$O" '"required":["title","description","date","category"]' "collection required fields"
has "$O" '"category":["sop","checklist","template"]' "collection enum values"
pass "collection <name> → front-matter schema from the profile, not the skill"

# --- profile failure contract: name what was needed, never guess a path -------
NOPROF="$ROOT/noprofile"
mkdir -p "$NOPROF"; git -C "$NOPROF" init -q
rc=0; O="$(bash "$SCRIPT" pipeline news --slug x --repo "$NOPROF" 2>&1)" || rc=$?
echo "  → $O"
[[ "$rc" == 1 ]] || fail "missing profile should exit 1 (got $rc)"
has "$O" '"ok":false' "missing profile is a logical failure"
has "$O" 'content-profile.json' "failure names the file it looked for"
has "$O" 'pipeline' "failure names what it needed"
pass "no profile → exit 1 naming the missing file and the need (no guessed path)"

rc=0; O="$(bash "$SCRIPT" pipeline webinars --repo "$ROOT" 2>&1)" || rc=$?
echo "  → $O"
[[ "$rc" == 1 ]] || fail "undeclared pipeline should exit 1 (got $rc)"
has "$O" '"declared":["guides","news","toolkit"]' "failure lists what the repo DOES declare"
pass "undeclared pipeline → exit 1 listing the declared ones"

rc=0; O="$(bash "$SCRIPT" image news sidebar --slug x --repo "$ROOT" 2>&1)" || rc=$?
[[ "$rc" == 1 ]] || fail "undeclared asset role should exit 1 (got $rc)"
has "$O" '"declared":["featured","body"]' "failure lists the declared roles"
pass "undeclared asset role → exit 1 listing the declared roles"

# An unfilled {slug} must never reach front matter as a literal.
rc=0; O="$(bash "$SCRIPT" image news featured --repo "$ROOT" 2>&1)" || rc=$?
echo "  → $O"
[[ "$rc" == 2 ]] || fail "unfilled {slug} should exit 2 (got $rc)"
has "$O" 'pass --slug' "refusal says which flag is missing"
pass "unfilled {slug} → exit 2 rather than a literal placeholder in the output"

BADV="$ROOT/badversion"
mkdir -p "$BADV/.tron"; git -C "$BADV" init -q
jq '.version = 99' "$PROF/content-profile.json" > "$BADV/.tron/content-profile.json"
rc=0; O="$(bash "$SCRIPT" collection toolkit --repo "$BADV" 2>&1)" || rc=$?
[[ "$rc" == 1 ]] || fail "unknown profile version should exit 1 (got $rc)"
has "$O" 'version-1' "failure names the version it speaks"
pass "unknown profile version → exit 1 rather than reading moved fields"

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
