#!/usr/bin/env bash
# Regression coverage for MD-3047: resolve-skill-dir.sh and git-pr's Step 1c
# ambient fallback each pick the newest complete installed package with the
# same version-then-rank scoring (version key, then cache/marketplace rank,
# newest wins on a tie). git-pr's Step 1c fallback cannot call
# resolve-skill-dir.sh directly — it is the one bootstrap that must resolve a
# package root before any resolver script is known to exist, and it must stay
# free of the GNU-only sort -V / find -maxdepth resolve-skill-dir.sh otherwise
# relies on (see tools/skill/test-resolve-plugin-root.sh). So the two keep an
# identical inline copy of the scoring logic instead of a shared script; this
# test is what makes "share the logic" real — it fails loudly the moment the
# two copies drift apart, which is the only way a future change (a new
# install root, a different tie-break) can be guaranteed to land in both.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
RESOLVER="$ROOT/tools/skill/resolve-skill-dir.sh"
DOC="$ROOT/skills/git-pr/SKILL.md"

PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }

# --- extract the scoring snippet from each file --------------------------
# Both compute: version -> zero-padded key, then rank from which root the
# candidate lives under. Pull just those lines (version=... through the
# final printf) and normalize the candidate-path variable name so the two
# are comparable text.
normalize() {
  # Fold line continuations, collapse all whitespace to single spaces, and
  # drop then/fi statement separators so single-line and multi-line `if`
  # forms compare equal — formatting is free to differ; the logic must not.
  tr '\n' ' ' | sed -E 's/\\ //g; s/[[:space:]]+/ /g; s/; */ /g; s/ +$//; s/^ +//'
}

extract_resolver_scoring() {
  awk '
    /version="\$\(printf/ { grab=1 }
    grab { print }
    grab && /printf .%s\\t%s\\t%s\\n. /  { exit }
  ' "$RESOLVER" | sed -E 's/\$skill_dir/$CANDIDATE/g' | normalize
}

extract_git_pr_scoring() {
  awk '
    /version="\$\(printf/ { grab=1 }
    grab { print }
    grab && /printf .%s\\t%s\\t%s\\n. /  { exit }
  ' "$DOC" | sed -E 's/\$root/$CANDIDATE/g' | normalize
}

RESOLVER_SNIPPET="$(extract_resolver_scoring)"
GITPR_SNIPPET="$(extract_git_pr_scoring)"

[ -n "$RESOLVER_SNIPPET" ] || fail "could not extract the scoring snippet from resolve-skill-dir.sh"
[ -n "$GITPR_SNIPPET" ] || fail "could not extract the scoring snippet from git-pr/SKILL.md Step 1c"

if [ "$RESOLVER_SNIPPET" != "$GITPR_SNIPPET" ]; then
  fail "resolve-skill-dir.sh and git-pr Step 1c's version-then-rank scoring have drifted apart:
--- resolve-skill-dir.sh ---
$RESOLVER_SNIPPET
--- git-pr Step 1c ---
$GITPR_SNIPPET"
fi
pass "resolve-skill-dir.sh and git-pr Step 1c score candidates with identical logic"

# Neither copy may use the GNU-only sort -V key modifier for the scoring —
# both now key on a zero-padded version string sorted with plain -k.
case "$RESOLVER_SNIPPET$GITPR_SNIPPET" in
  *'V'*key*|*'-k1,1V'*) fail "scoring snippet still relies on the GNU-only sort -V key modifier" ;;
esac
pass "scoring snippet uses a portable zero-padded version key, not sort -V"

# --- behavior: both pick the newest of two versions under the same root ---
FIX="$(mktemp -d "${TMPDIR:-/tmp}/rank-selection-sync.XXXXXX")"
trap 'find "$FIX" -depth -delete 2>/dev/null || true' EXIT

CACHE="$FIX/.claude/plugins/cache/tron/tron-engineer"
mkdir -p "$CACHE/0.35.2/skills/start-ticket" "$CACHE/0.35.10/skills/start-ticket"
printf '#!/usr/bin/env bash\n' > "$CACHE/0.35.2/skills/start-ticket/scripts.sh"
printf '#!/usr/bin/env bash\n' > "$CACHE/0.35.10/skills/start-ticket/scripts.sh"

for shell in /bin/bash /bin/zsh; do
  [[ -x "$shell" ]] || continue
  got="$(HOME="$FIX" "$shell" "$RESOLVER" start-ticket scripts.sh)"
  want="$CACHE/0.35.10/skills/start-ticket"
  [[ "$got" == "$want" ]] || fail "$shell: resolve-skill-dir.sh picked $got, expected the newer $want"
  pass "$shell: resolve-skill-dir.sh still picks the newest version after the algorithm swap"
done

echo "rank-selection-sync regression: $PASS passed"
