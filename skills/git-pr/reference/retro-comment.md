# Retrospective submission — mechanics

The `git-pr` Step 7 mechanics. The judgment and content stay with the worker; everything here is
the deterministic validation and transport around it.

This file used to document a post-PR GitHub Copilot review request and a bounded wait for it to
land. Both are gone (MD-2745): code review now runs **locally, before the PR exists**, and is
triggered from SKILL.md Step 1c with `bun run review:local`. Nothing reviews the PR after it opens,
so there is nothing here to request and nothing to poll.

## Contents

- [Resolving the script](#resolving-the-script)
- [Dispatched submission](#dispatched-submission)
- [Interactive fallback](#interactive-fallback)

## Resolving the script

The structured Scout submission and interactive marker-comment assembly live in the bundled
`git-pr-retro.sh`. Resolve it once:

```bash
name=git-pr
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/git-pr-retro.sh)"
```

## Dispatched submission

When both `TRON_DISPATCH_ID` and `TRON_API_URL` identify a Scout dispatch, write the retrospective
as a closed JSON object in a fresh temp file:

```bash
RETRO_PAYLOAD="$(mktemp "${TMPDIR:-/tmp}/tron-retro-payload.XXXXXX")"
trap 'rm -f "$RETRO_PAYLOAD"' EXIT
cat > "$RETRO_PAYLOAD" <<'EOF'
{
  "worked": ["What worked, as worker-authored prose."],
  "friction": ["Friction or surprises, as worker-authored prose."],
  "improvements": ["A concrete improvement, as worker-authored prose."],
  "followUps": ["MD-1234"]
}
EOF
bash "$SKILL_DIR/scripts/git-pr-retro.sh" submit-dispatched --payload-file "$RETRO_PAYLOAD"
```

That final line is the canonical dispatched invocation. Its argv shape is part of the Scout hook
contract: the subcommand is exactly `submit-dispatched`, followed by exactly `--payload-file` and
the payload path. Dispatch identity and API location come only from the inherited environment.

`worked`, `friction`, and `improvements` are required arrays of 1 to 20 non-empty strings, each no
longer than 1000 characters. `followUps` is optional and may contain 0 to 20 Jira ticket keys for
follow-up tickets that have already been filed. No other fields are accepted. Do not convert
unfiled or out-of-scope prose into `followUps`, and do not add bare `FOLLOW-UP:` lines for Scout to
classify later.

The helper sends the payload file unchanged with `POST` to
`$TRON_API_URL/api/dispatches/$TRON_DISPATCH_ID/retrospective` and prints exactly one JSON result.
Scout owns idempotency, durable storage, and canonical GitHub publication, so retry the same command
with the same payload when needed. Do not add local deduplication or post a second GitHub comment.

On a typed refusal, preserve Scout's remedy contract: `remedy: "worker"` means satisfy the named
precondition and retry; `remedy: "human"` means park for a human decision. A transport failure is
reported as a machine-readable failure, not recast as a human approval gate.

## Interactive fallback

Use this path only when there is no Scout dispatch identity. It posts a normal GitHub comment and
does not record durable retrospective state in Scout. Never use it to recover from a dispatched
submission failure.

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

The script adds the `<!-- tron-retro -->` marker, the `### Retro`
header, and the footer: the `*<model ID>*` line plus this session's real token line from
`tools/git/token-usage.sh` (empty token data never blocks the comment).

Replace `<your model ID>` with your own exact model ID (e.g. `claude-opus-4-8[1m]`) as **literal
text**. Do not paste a shell variable like `${CLAUDE_MODEL_ID}` — Claude Code does not export it to
the shell, so the literal `${...}` would end up in the comment. You know your own model ID from your
session context; write it in directly.

Legacy/manual `FOLLOW-UP:` lines remain available in this explicitly interactive comment. Use
`<!-- tron-note -->` on any other comment you post on this PR.

If the bundled script cannot be resolved, SKILL.md links the manual retro fallback.
