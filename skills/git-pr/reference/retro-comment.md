# Retro comment — mechanics

The `git-pr` Step 7 mechanics. The judgment (what to write in the retro) stays in SKILL.md;
everything here is the deterministic shape around it.

This file used to document a post-PR GitHub Copilot review request and a bounded wait for it to
land. Both are gone (MD-2745): code review now runs **locally, before the PR exists**, and is
triggered from SKILL.md Step 1c with `bun run review:local`. Nothing reviews the PR after it opens,
so there is nothing here to request and nothing to poll.

## Contents

- [Resolving the script](#resolving-the-script)
- [The retro comment](#the-retro-comment)

## Resolving the script

The token-usage lookup and the marker-comment assembly live in the bundled `git-pr-retro.sh`.
Resolve it once:

```bash
name=git-pr
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/git-pr-retro.sh)"
```

## The retro comment

Write the filled-in retro sections (this is your judgment) to a fresh temp file, then post and clean
up:

```bash
RETRO_BODY="$(mktemp "${TMPDIR:-/tmp}/tron-retro-body.XXXXXX")"
trap 'rm -f "$RETRO_BODY"' EXIT
cat > "$RETRO_BODY" <<'EOF'
**What went well:**
**Friction / surprises:**
**Follow-up (filed):**
**Out of scope / not filed:**
FOLLOW-UP:
EOF
bash "$SKILL_DIR/scripts/git-pr-retro.sh" retro-comment --pr "<N>" \
  --model "<your model ID>" --body-file "$RETRO_BODY"
```

The script adds the `<!-- tron-retro -->` marker (required for the OS reviewer), the `### Retro`
header, and the footer: the `*<model ID>*` line plus this session's real token line from
`tools/git/token-usage.sh` (empty token data never blocks the comment).

Replace `<your model ID>` with your own exact model ID (e.g. `claude-opus-4-8[1m]`) as **literal
text**. Do not paste a shell variable like `${CLAUDE_MODEL_ID}` — Claude Code does not export it to
the shell, so the literal `${...}` would end up in the comment. You know your own model ID from your
session context; write it in directly.

Use `FOLLOW-UP:` for work this PR did not do — one per line. Use `<!-- tron-note -->` on any other
comment you post on this PR.

If the bundled script cannot be resolved, SKILL.md links the manual retro fallback.
