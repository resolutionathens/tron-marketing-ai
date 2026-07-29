#!/usr/bin/env bash
# Regression test for MD-2539: BlockIgnores in vale-ini.template must stay a
# single comma-free regex (Vale splits its value on commas), and must still
# ignore both the `::` and `:::` MDC fence variants without swallowing prose
# outside them.
#
# Hermetic: uses only the bundled Vale style + Vocab (no `Packages`/`vale sync`,
# so no network dependency); SKIPs cleanly if the `vale` binary is absent.
#
#   bash skills/prose-lint/scripts/test-vale-ini-template.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"

if ! command -v vale >/dev/null 2>&1; then
  echo "SKIP: vale not installed — skipping vale-ini.template regression test"
  exit 0
fi

BLOCK_IGNORES="$(grep '^BlockIgnores' "$SKILL_DIR/vale-ini.template" | sed 's/^BlockIgnores = //')"
TOKEN_IGNORES="$(grep '^TokenIgnores' "$SKILL_DIR/vale-ini.template" | sed 's/^TokenIgnores = //')"
[ -n "$BLOCK_IGNORES" ] || { echo "FAIL: no BlockIgnores line found in vale-ini.template" >&2; exit 1; }

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

PASS=0
pass() { echo "  ok: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; echo "$OUT" >&2; exit 1; }

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
