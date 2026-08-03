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
  if rg -q 'find .* -maxdepth' "$portable_file"; then
    fail "$portable_file relies on GNU-only find -maxdepth"
  fi
done
pass "resolver and both skill bootstraps avoid GNU-only sort and find flags"

if rg -q 'claude_cache|claude_marketplaces|codex_cache|codex_marketplaces|release_store|candidate=' "$RESOLVER"; then
  fail "resolver searches ambient installations instead of staying package-local"
fi
pass "resolver contains no ambient cross-install selection path"

for skill_doc in "$ROOT/skills/create-ticket/SKILL.md" "$ROOT/skills/jira/SKILL.md"; do
  rg -qF '[ -z "$PLUGIN_ROOT" ] && [ -f "$HOME/.config/opencode/skills/$name/SKILL.md" ]' "$skill_doc" \
    || fail "$skill_doc does not bind an OpenCode invocation to its own package root"
  rg -qF '[ -z "$PLUGIN_ROOT" ] && [ -f "$HOME/.pi/agent/skills/$name/SKILL.md" ]' "$skill_doc" \
    || fail "$skill_doc does not bind a Pi invocation to its own package root"
  rg -q 'find .*resolve-plugin-root\.sh' "$skill_doc" \
    && fail "$skill_doc can select a resolver from another installed package"
done
pass "both skill bootstraps bind OpenCode and Pi locally and never search for a foreign resolver"

run_doc_bootstrap() {
  local doc="$1"
  local skill="$2"
  local script="$FIXTURE/bootstrap-$skill.sh"
  awk -v skill="$skill" '
    $0 == "name=" skill { copying = 1 }
    copying { print }
    copying && $0 ~ /^PLUGIN_ROOT="\$\(bash "\$RESOLVER"/ { exit }
  ' "$doc" >"$script"
  printf '\nprintf "%%s\\n" "$PLUGIN_ROOT"\n' >>"$script"
  env -u TRON_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_SKILL_DIR \
    HOME="${BOOTSTRAP_HOME:-$FIXTURE/home}" PATH="${BOOTSTRAP_PATH:-$PATH}" bash "$script"
}

mkdir -p "$FIXTURE/bsd-bin"
cat >"$FIXTURE/bsd-bin/find" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  [ "$arg" = "-maxdepth" ] && { echo "GNU-only find -maxdepth rejected by BSD fixture" >&2; exit 64; }
done
exec /usr/bin/find "$@"
EOF
chmod +x "$FIXTURE/bsd-bin/find"
BOOTSTRAP_PATH="$FIXTURE/bsd-bin:$PATH"
export BOOTSTRAP_PATH

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

for skill in create-ticket jira; do
  resolved_bootstrap="$(BOOTSTRAP_HOME="$FIXTURE/home" \
    run_doc_bootstrap "$ROOT/skills/$skill/SKILL.md" "$skill")"
  [ "$resolved_bootstrap" = "$INSTALL" ] \
    || fail "$skill bootstrap resolved '$resolved_bootstrap', expected OpenCode root '$INSTALL'"
done
pass "both documented bootstraps bind a clean OpenCode package to its own root"

PI_USER="$FIXTURE/pi-user"
PI="$PI_USER/.pi/agent"
mkdir -p "$PI/skills/create-ticket" "$PI/skills/jira" "$PI/tools/skill"
PI="$(cd "$PI" && pwd)"
cp "$ROOT/skills/create-ticket/SKILL.md" "$PI/skills/create-ticket/SKILL.md"
cp "$ROOT/skills/jira/SKILL.md" "$PI/skills/jira/SKILL.md"
cp "$RESOLVER" "$PI/tools/skill/resolve-plugin-root.sh"
cp -R "$ROOT/tools/md-to-adf" "$PI/tools"
cp -R "$ROOT/tools/ticket" "$PI/tools"

for skill in create-ticket jira; do
  resolved_bootstrap="$(BOOTSTRAP_HOME="$PI_USER" \
    run_doc_bootstrap "$ROOT/skills/$skill/SKILL.md" "$skill")"
  [ "$resolved_bootstrap" = "$PI" ] \
    || fail "$skill bootstrap resolved '$resolved_bootstrap', expected clean Pi root '$PI'"
done
pass "both documented bootstraps bind a clean Pi package with no root variables"

CODEX_USER="$FIXTURE/codex-user"
CODEX="$CODEX_USER/.codex/plugins/cache/tron/0.44.0"
mkdir -p "$CODEX/skills/create-ticket" "$CODEX/skills/jira" "$CODEX/tools/skill"
CODEX="$(cd "$CODEX" && pwd)"
cp "$ROOT/skills/create-ticket/SKILL.md" "$CODEX/skills/create-ticket/SKILL.md"
cp "$ROOT/skills/jira/SKILL.md" "$CODEX/skills/jira/SKILL.md"
cp "$RESOLVER" "$CODEX/tools/skill/resolve-plugin-root.sh"
cp -R "$ROOT/tools/md-to-adf" "$CODEX/tools"
cp -R "$ROOT/tools/ticket" "$CODEX/tools"

for skill in create-ticket jira; do
  resolved_bootstrap="$(BOOTSTRAP_HOME="$CODEX_USER" \
    run_doc_bootstrap "$ROOT/skills/$skill/SKILL.md" "$skill")"
  [ "$resolved_bootstrap" = "$CODEX" ] \
    || fail "$skill bootstrap resolved '$resolved_bootstrap', expected clean Codex root '$CODEX'"
done
pass "both documented bootstraps locate a clean complete Codex package with no root variables"

RELEASE_USER="$FIXTURE/release-user"
RELEASE="$RELEASE_USER/Library/Application Support/tron-os/tron-releases/versions/0.44.0"
mkdir -p "$RELEASE/skills/create-ticket" "$RELEASE/skills/jira" "$RELEASE/tools/skill"
RELEASE="$(cd "$RELEASE" && pwd)"
cp "$ROOT/skills/create-ticket/SKILL.md" "$RELEASE/skills/create-ticket/SKILL.md"
cp "$ROOT/skills/jira/SKILL.md" "$RELEASE/skills/jira/SKILL.md"
cp "$RESOLVER" "$RELEASE/tools/skill/resolve-plugin-root.sh"
cp -R "$ROOT/tools/md-to-adf" "$RELEASE/tools"
cp -R "$ROOT/tools/ticket" "$RELEASE/tools"

for skill in create-ticket jira; do
  resolved_bootstrap="$(BOOTSTRAP_HOME="$RELEASE_USER" \
    run_doc_bootstrap "$ROOT/skills/$skill/SKILL.md" "$skill")"
  [ "$resolved_bootstrap" = "$RELEASE" ] \
    || fail "$skill bootstrap resolved '$resolved_bootstrap', expected release-store root '$RELEASE'"
done
pass "both documented bootstraps locate a clean release-store package with no root variables"

SECOND_CODEX="$CODEX_USER/.codex/plugins/cache/tron/0.43.0"
mkdir -p "$SECOND_CODEX/skills/create-ticket" "$SECOND_CODEX/tools/skill"
cp "$ROOT/skills/create-ticket/SKILL.md" "$SECOND_CODEX/skills/create-ticket/SKILL.md"
cp "$RESOLVER" "$SECOND_CODEX/tools/skill/resolve-plugin-root.sh"
set +e
AMBIGUOUS="$(BOOTSTRAP_HOME="$CODEX_USER" \
  run_doc_bootstrap "$ROOT/skills/create-ticket/SKILL.md" create-ticket 2>&1)"
AMBIGUOUS_STATUS=$?
set -e
[ "$AMBIGUOUS_STATUS" -ne 0 ] || fail "ambiguous Codex installs selected one package silently"
case "$AMBIGUOUS" in
  *"found 2 installed package roots"*"set TRON_PLUGIN_ROOT"*"multiple installed Tron packages are ambiguous"*) ;;
  *) fail "ambiguous-install diagnostic was not actionable: $AMBIGUOUS" ;;
esac
pass "multiple installed copies fail closed instead of crossing package versions"
trash "$SECOND_CODEX"

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
