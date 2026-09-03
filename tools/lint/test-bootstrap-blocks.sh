#!/usr/bin/env bash
# Execute every documented SKILL_DIR bootstrap block verbatim (MD-2450).
#
# check-fastpath-resolvers.sh greps the docs for the right shape. This runs
# them: it extracts each block exactly as an agent would copy it out of the
# markdown, points HOME at a hermetic fixture, and asserts the block resolves to
# the seeded skill dir. A block that greps clean but does not execute — a stray
# indent, an unbalanced quote, a zsh-only word-splitting difference — fails here
# and nowhere else.
#
# Hermetic: the fixture seeds its own resolver and installs under a fake HOME,
# so no real plugin install is consulted. Runs under bash and zsh, because the
# agent's shell is not guaranteed to be either one.
#
#   bash tools/lint/test-bootstrap-blocks.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(cd "$HERE/../.." && pwd)}"
cd "$ROOT"

PASS=0
fail=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
bad()  { echo "  ✗ $*" >&2; fail=1; }

FIX="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-blocks.XXXXXX")"
trap 'rm -rf "$FIX"' EXIT

# The fixture's own copy of the shared resolver, found by each block's fallback.
# resolve-skill-dir.sh scores candidates via its sibling rank-candidate.sh
# (MD-3047), so both must be present for it to resolve anything.
INSTALL="$FIX/.claude/plugins/cache/tron/tron-test/0.1.0"
mkdir -p "$INSTALL/tools/skill"
cp "$ROOT/tools/skill/resolve-skill-dir.sh" "$INSTALL/tools/skill/resolve-skill-dir.sh"
cp "$ROOT/tools/skill/rank-candidate.sh" "$INSTALL/tools/skill/rank-candidate.sh"

docs="$(
  { ls -1 skills/*/SKILL.md agents/*.md 2>/dev/null
    ls -1 skills/*/reference/*.md 2>/dev/null; } | sort
)"

checked=0
while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  # This suite owns SKILL_DIR bootstraps. Shared plugin-root bootstraps also use
  # RESOLVER=, but have their own exact-block integration test and a different
  # fixture contract under tools/skill/test-resolve-plugin-root.sh.
  grep -q 'SKILL_DIR="$(bash "$RESOLVER" "$name"' "$doc" || continue
  checked=$((checked + 1))

  block="$FIX/block.sh"
  # Pull `name=<skill>` through the SKILL_DIR assignment, stripping the leading
  # indentation the markdown list added.
  awk '
    /^[ \t]*name=[a-z0-9-]+[ \t]*$/ { grab=1; match($0, /^[ \t]*/); ind=RLENGTH }
    grab { print substr($0, ind + 1) }
    grab && /SKILL_DIR="\$\(bash "\$RESOLVER" "\$name"/ { exit }
  ' "$doc" > "$block"

  skill="$(sed -n '1s/^name=//p' "$block")"
  probes="$(sed -n 's/.*bash "\$RESOLVER" "\$name" \(.*\))"$/\1/p' "$block" | tr -d '"')"
  if [ -z "$skill" ] || [ -z "$probes" ]; then
    bad "$doc: could not extract skill/probes from the block"
    continue
  fi

  # Seed every path the block requires, so a complete install exists.
  dir="$INSTALL/skills/$skill"
  rm -rf "$dir"; mkdir -p "$dir"
  for p in $probes; do
    case "$p" in
      */*) mkdir -p "$dir/$(dirname "$p")" ;;
    esac
    # `styles` and friends are directories; anything with a suffix is a file.
    case "$p" in
      *.*) printf '#\n' > "$dir/$p" ;;
      *)   mkdir -p "$dir/$p" ;;
    esac
  done

  for sh in /bin/bash /bin/zsh; do
    [ -x "$sh" ] || continue
    got="$(env -u CLAUDE_SKILL_DIR -u CLAUDE_PLUGIN_ROOT HOME="$FIX" "$sh" "$block" 2>/dev/null; \
           env -u CLAUDE_SKILL_DIR -u CLAUDE_PLUGIN_ROOT HOME="$FIX" "$sh" -c \
             "source '$block' >/dev/null 2>&1; printf '%s' \"\$SKILL_DIR\"" 2>/dev/null)"
    if [ "$got" = "$dir" ]; then
      pass "$(basename "$sh"): $doc ($skill)"
    else
      bad "$(basename "$sh"): $doc ($skill) resolved to '${got:-<empty>}', expected '$dir'"
    fi
  done
done <<EOF
$docs
EOF

echo
if [ "$checked" -eq 0 ]; then
  echo "test-bootstrap-blocks: FAILED (no bootstrap blocks found — extraction is broken)"
  exit 1
fi
if [ "$fail" = 1 ]; then
  echo "test-bootstrap-blocks: FAILED ($checked blocks)"
  exit 1
fi
echo "test-bootstrap-blocks: OK ($checked blocks, $PASS shell/block combinations)"
