#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
RESOLVER="$HERE/resolve-plugin-root.sh"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/tron-plugin-root.XXXXXX")"
cleanup() { trash "$FIXTURE"; }
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf '  ok  : %s\n' "$*"; }

command -v trash >/dev/null 2>&1 || fail "trash is required"
[ -x "$RESOLVER" ] || fail "resolve-plugin-root.sh is missing or not executable"

node - "$ROOT/.claude-plugin/plugin.json" "$ROOT/.codex-plugin/plugin.json" <<'NODE'
const fs = require("fs");
const expected = {
  schemaVersion: 1,
  root: ".",
  skills: {
    "create-ticket": ["tools/jira", "tools/md-to-adf", "tools/skill", "tools/ticket", "tools/voice"],
    jira: ["tools/jira", "tools/md-to-adf", "tools/skill", "tools/ticket"],
  },
};
for (const file of process.argv.slice(2)) {
  const actual = JSON.parse(fs.readFileSync(file, "utf8")).resourceContract;
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${file} resourceContract differs from the exact v1 contract`);
  }
}
NODE
pass "Claude and Codex manifests publish the same exact v1 per-skill resource contract"

for portable_file in "$RESOLVER" "$ROOT/skills/create-ticket/SKILL.md" "$ROOT/skills/jira/SKILL.md"; do
  if rg -q 'sort -V' "$portable_file"; then
    fail "$portable_file relies on GNU-only sort -V"
  fi
done
pass "resolver and both skill bootstraps avoid GNU-only version sorting"

if rg -q 'claude_cache|claude_marketplaces|codex_cache|codex_marketplaces|release_store|candidate=' "$RESOLVER"; then
  fail "resolver searches ambient installations instead of staying package-local"
fi
pass "resolver contains no ambient cross-install selection path"

for skill_doc in "$ROOT/skills/create-ticket/SKILL.md" "$ROOT/skills/jira/SKILL.md"; do
  rg -qF '[ -z "$PLUGIN_ROOT" ] && [ -f "$HOME/.config/opencode/skills/$name/SKILL.md" ]' "$skill_doc" \
    || fail "$skill_doc does not bind an OpenCode invocation to its own package root"
  rg -q 'find .*resolve-plugin-root\.sh' "$skill_doc" \
    && fail "$skill_doc can select a resolver from another installed package"
done
pass "both skill bootstraps bind OpenCode locally and never search for a foreign resolver"

INSTALL="$FIXTURE/home/.config/opencode"
mkdir -p "$INSTALL/skills/create-ticket" "$INSTALL/skills/jira" "$INSTALL/tools/skill"
INSTALL="$(cd "$INSTALL" && pwd)"
cp "$ROOT/skills/create-ticket/SKILL.md" "$INSTALL/skills/create-ticket/SKILL.md"
cp "$ROOT/skills/jira/SKILL.md" "$INSTALL/skills/jira/SKILL.md"
cp "$RESOLVER" "$INSTALL/tools/skill/resolve-plugin-root.sh"

for resource in tools/md-to-adf tools/ticket; do
  cp -R "$ROOT/$resource" "$INSTALL/${resource%/*}"
done

resolved="$(env -u TRON_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_SKILL_DIR \
  HOME="$FIXTURE/home" bash "$INSTALL/tools/skill/resolve-plugin-root.sh" \
  create-ticket tools/md-to-adf/md-to-adf.mjs tools/ticket/rubric-lint.sh tools/ticket/ticket-rubric.md)"
[ "$resolved" = "$INSTALL" ] || fail "clean OpenCode install resolved '$resolved', expected '$INSTALL'"
pass "clean installed-skill environment resolves its plugin root with no ambient root variables"

MD="$FIXTURE/ticket.md"
cat >"$MD" <<'EOF'
```
Done: Ship portable resource resolution
Type: engineering
Deliverable type: pr
Context: https://facilitron.atlassian.net/browse/MD-2607
Decision: Preserve rich Jira descriptions
Repo: tron-marketing-ai
Affected paths: skills/create-ticket/SKILL.md
Acceptance criteria:
- installed skills resolve shared tools
```

## Portable Jira description

Keep **formatted descriptions** and ticket validation available in every harness.
EOF

ADF="$(env -u TRON_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_SKILL_DIR \
  HOME="$FIXTURE/home" node "$resolved/tools/md-to-adf/md-to-adf.mjs" "$MD")"
printf '%s' "$ADF" | node -e '
let text = "";
process.stdin.on("data", (chunk) => text += chunk);
process.stdin.on("end", () => {
  const doc = JSON.parse(text);
  const flat = JSON.stringify(doc);
  if (doc.type !== "doc" || doc.version !== 1) throw new Error("not an ADF document");
  if (!flat.includes("Portable Jira description") || !flat.includes("formatted descriptions")) {
    throw new Error("formatted description content was lost");
  }
  if (!flat.includes("strong")) throw new Error("formatted description fell back to raw markdown");
});'
pass "clean install converts formatted Markdown to structured ADF without a raw-Markdown fallback"

VERDICT="$(env -u TRON_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_SKILL_DIR \
  HOME="$FIXTURE/home" bash "$resolved/tools/ticket/rubric-lint.sh" --file "$MD" \
  --summary 'TRON-PLUGIN: make resources portable' | jq -r '.verdict')"
[ "$VERDICT" = "high: actionable" ] || fail "clean install lint verdict was '$VERDICT'"
pass "clean install lints a complete ticket draft"

AMBIENT="$FIXTURE/home/.claude/plugins/cache/tron/99.99.99"
mkdir -p "$AMBIENT/skills/create-ticket" "$AMBIENT/tools/skill"
cp "$ROOT/skills/create-ticket/SKILL.md" "$AMBIENT/skills/create-ticket/SKILL.md"
cp "$RESOLVER" "$AMBIENT/tools/skill/resolve-plugin-root.sh"
cp -R "$ROOT/tools/md-to-adf" "$AMBIENT/tools"
cp -R "$ROOT/tools/ticket" "$AMBIENT/tools"

trash "$INSTALL/tools/ticket/ticket-rubric.md"
mkdir -p "$FIXTURE/bin"
cat >"$FIXTURE/bin/sort" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  [ "$arg" = "-V" ] && { echo "GNU-only sort -V rejected by portability fixture" >&2; exit 64; }
done
exec /usr/bin/sort "$@"
EOF
chmod +x "$FIXTURE/bin/sort"
set +e
ERROR="$(env -u TRON_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_SKILL_DIR \
  HOME="$FIXTURE/home" PATH="$FIXTURE/bin:$PATH" bash "$INSTALL/tools/skill/resolve-plugin-root.sh" \
  create-ticket tools/md-to-adf/md-to-adf.mjs tools/ticket/rubric-lint.sh tools/ticket/ticket-rubric.md 2>&1)"
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "partial install unexpectedly resolved"
case "$ERROR" in
  *"incomplete Tron installation"*"tools/ticket/ticket-rubric.md"*"Install or update the complete Tron package"*) ;;
  *) fail "partial-install diagnostic was not actionable: $ERROR" ;;
esac
pass "partial installs fail with the missing exact path and an actionable update instruction"
case "$ERROR" in
  *"$AMBIENT"*) fail "partial OpenCode skill crossed into an ambient complete package: $ERROR" ;;
esac
pass "partial invoking package never binds to a newer complete ambient installation"

set +e
ERROR="$(TRON_PLUGIN_ROOT="$FIXTURE/not-an-install" HOME="$FIXTURE/home" \
  bash "$INSTALL/tools/skill/resolve-plugin-root.sh" create-ticket \
  tools/md-to-adf/md-to-adf.mjs tools/ticket/rubric-lint.sh 2>&1)"
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || fail "invalid explicit plugin root unexpectedly fell through to another install"
case "$ERROR" in
  *"TRON_PLUGIN_ROOT is set to an incomplete installation"*"$FIXTURE/not-an-install"*) ;;
  *) fail "invalid explicit-root diagnostic was not actionable: $ERROR" ;;
esac
pass "an invalid explicit portable root fails closed instead of selecting an ambient install"

for compatibility_var in CLAUDE_PLUGIN_ROOT CLAUDE_SKILL_DIR; do
  set +e
  ERROR="$(env -u TRON_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_SKILL_DIR \
    "$compatibility_var=$FIXTURE/not-an-install" HOME="$FIXTURE/home" \
    bash "$INSTALL/tools/skill/resolve-plugin-root.sh" create-ticket \
    tools/md-to-adf/md-to-adf.mjs tools/ticket/rubric-lint.sh 2>&1)"
  STATUS=$?
  set -e
  [ "$STATUS" -ne 0 ] || fail "$compatibility_var unexpectedly fell through to another install"
  case "$ERROR" in
    *"$compatibility_var"*"incomplete installation"*|*"$compatibility_var"*"does not belong to a complete installation"*) ;;
    *) fail "$compatibility_var diagnostic was not actionable: $ERROR" ;;
  esac
done
pass "invalid Claude compatibility roots also fail closed at their invoking package"

printf 'PASS: portable plugin-root resolution and clean installed Jira tooling.\n'
