#!/usr/bin/env bash
# Regression test for MD-2539: BlockIgnores in vale-ini.template must stay a
# single comma-free regex (Vale splits its value on commas), and must still
# ignore both the `::` and `:::` MDC fence variants without swallowing prose
# outside them.
#
# The comma check below is vale-independent and runs unconditionally — it's
# the assertion CI actually exercises, since CI never installs vale. It fails
# on any future edit that reintroduces a comma (e.g. a `{n,m}` quantifier),
# not just on a snapshot of today's string. It's scoped to BlockIgnores only:
# TokenIgnores on the next line legitimately contains a comma (a genuine
# two-pattern list), so the test also asserts the check doesn't false-positive
# there.
#
# Below that, if `vale` is installed locally, a richer check exercises the
# real regex end-to-end against Vale's bundled styles (no `Packages`/`vale
# sync`, so still no network dependency) and confirms both fence variants are
# ignored while outside prose still lints. That part SKIPs cleanly in CI.
#
#   bash skills/prose-lint/scripts/test-vale-ini-template.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
TEMPLATE="$SKILL_DIR/vale-ini.template"

PASS=0
pass() { echo "  ok: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; exit 1; }

[ -f "$TEMPLATE" ] || fail "vale-ini.template not found at $TEMPLATE"

BLOCK_IGNORES="$(grep '^BlockIgnores' "$TEMPLATE" | sed 's/^BlockIgnores = //')"
TOKEN_IGNORES="$(grep '^TokenIgnores' "$TEMPLATE" | sed 's/^TokenIgnores = //')"

[ -n "$BLOCK_IGNORES" ] || fail "no BlockIgnores line found in vale-ini.template"
[ -n "$TOKEN_IGNORES" ] || fail "no TokenIgnores line found in vale-ini.template"

# --- Vale-independent: this is the assertion CI actually runs. ---

case "$BLOCK_IGNORES" in
  *,*) fail "BlockIgnores contains a comma — Vale splits *Ignores values on commas, so this will break with an E201 parse error (the {n,m}-quantifier bug this test guards against): $BLOCK_IGNORES" ;;
esac
pass "BlockIgnores contains no comma"

# Scoping check: the rule above must apply to BlockIgnores only. TokenIgnores
# is a genuine two-pattern list and is expected to contain a comma; if a
# broader "no *Ignores key may contain a comma" check were written instead,
# this would catch it failing on legitimate input.
case "$TOKEN_IGNORES" in
  *,*) pass "TokenIgnores legitimately contains a comma (two-pattern list) — confirms the check above is scoped to BlockIgnores only" ;;
  *) fail "TokenIgnores has no comma — expected it to still be a two-pattern list; if this changed, the scoping assumption behind this test needs a re-check" ;;
esac

if printf '%s' "$BLOCK_IGNORES" | grep -qE '\{[0-9]+,'; then
  fail "BlockIgnores contains a {n,...} quantifier, which reintroduces a comma: $BLOCK_IGNORES"
fi
pass "BlockIgnores contains no {n,...} quantifier"

# --- Vale-dependent: richer end-to-end check, SKIPs cleanly where vale isn't installed (e.g. CI). ---

if ! command -v vale >/dev/null 2>&1; then
  echo "SKIP: vale not installed — skipping the end-to-end vale-ini.template check"
  echo "vale-ini.template BlockIgnores regression: $PASS checks passed (+ 1 skipped)"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/prose-lint-blockignores.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/.vale/styles/config/vocabularies"
ln -s "$SKILL_DIR/styles/Facilitron" "$WORK/.vale/styles/Facilitron"
ln -s "$SKILL_DIR/styles/config/vocabularies/Facilitron" "$WORK/.vale/styles/config/vocabularies/Facilitron"

# Minimal config: exercises the real BlockIgnores/TokenIgnores values against
# the bundled Vale + Facilitron styles only, so no `vale sync` / network call
# is needed to reproduce the E201 parse failure or verify fence behavior.
cat > "$WORK/.vale.ini" <<EOF
StylesPath = .vale/styles
MinAlertLevel = suggestion
Vocab = Facilitron

[*.md]
BasedOnStyles = Vale, Facilitron
Vale.Spelling = NO

BlockIgnores = $BLOCK_IGNORES
TokenIgnores = $TOKEN_IGNORES
EOF

cat > "$WORK/fixture.md" <<'EOF'
This sentence is very very very extremely utilized in order to test wordiness outside a fence.

::card{prop=1}
This markup fence body should be totally skipped no matter how sloppy the writing inside happens to be, obviously.
::

Some more content between the fences that ought to also get linted properly right here.

:::alert{type=warning}
This is the triple-colon fence variant and it too should be skipped entirely, clearly.
:::

Final closing remark outside every fence, meant to trigger a finding down here too.
EOF

OUT="$(cd "$WORK" && vale --output=line fixture.md 2>&1)" || true

if printf '%s\n' "$OUT" | grep -q 'E201'; then
  fail "BlockIgnores/TokenIgnores regex failed to parse (E201)"
fi
pass "vale-ini.template parses under Vale ($(vale --version)) — no E201"

if printf '%s\n' "$OUT" | grep -qE '^fixture\.md:(3|4|5):'; then
  fail "prose inside the ::card fence body (lines 3-5) was linted; expected it to be ignored"
fi
pass "::card{...} ... :: fence body stays ignored"

if printf '%s\n' "$OUT" | grep -qE '^fixture\.md:(9|10|11):'; then
  fail "prose inside the :::alert fence body (lines 9-11) was linted; expected it to be ignored"
fi
pass ":::alert{...} ... ::: fence body stays ignored"

if ! printf '%s\n' "$OUT" | grep -qE '^fixture\.md:1:'; then
  fail "prose outside the fences (line 1) produced no findings; expected the wordiness/hedging hits to survive"
fi
pass "prose outside the fences still produces findings"

echo "vale-ini.template BlockIgnores regression: $PASS checks passed"
