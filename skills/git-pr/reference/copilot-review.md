# Copilot review + retro comment — mechanics

The `git-pr` Steps 7 and 8 mechanics. The judgment (which review comments to act on, what to write
in the retro) stays in SKILL.md; everything here is the deterministic shape around it.

## Contents

- [Resolving the script](#resolving-the-script)
- [Step 7 — request the Copilot review](#step-7--request-the-copilot-review)
- [Step 7b — wait for the review, then report status](#step-7b--wait-for-the-review-then-report-status)
- [Step 8 — retro comment](#step-8--retro-comment)

## Resolving the script

The doc-only skip arithmetic, the token-usage lookup, and the marker-comment assembly all live in
the bundled `git-pr-retro.sh`. Resolve it once:

```bash
name=git-pr
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/git-pr-retro.sh)"
```

## Step 7 — request the Copilot review

Best-effort, and skipped for small doc-only PRs:

```bash
bash "$SKILL_DIR/scripts/git-pr-retro.sh" skip-check --pr "<N>"
```

Prints `{"skip":bool,"reason":"..."}` (doc = `*.md`/`*.mdx` only; small = ≤3 files and ≤40 changed
lines). A SKILL.md counts as documentation, but its blast radius (it's instructions an agent
executes) still makes it easy to blow past the thresholds — don't special-case it lower. If `skip`
is true, skip the request and note it in Step 9. Otherwise:

```bash
bash "$SKILL_DIR/scripts/git-pr-retro.sh" request-review --pr "<N>"
```

Never fails the lifecycle (an org without Copilot review returns `requested:false`, exit 0). One
request at PR open only.

## Step 7b — wait for the review, then report status

A PR is **not** approval-ready the instant it opens (MD-2112). If a review was requested
(`requested:true` above), wait for it to land before handing off to the human approval gate. Skip
this step only when Step 7 skipped the request or returned `requested:false`.

```bash
bash "$SKILL_DIR/scripts/git-pr-retro.sh" await-review --pr "<N>"
```

Polls until Copilot posts its review (default: up to 10 min, every 20s — tighter, 120s, for a
dispatched worker with `TRON_DISPATCH_ID` set, unless you pass `--timeout` yourself; tune with
`--timeout`/`--interval` seconds). It prints one JSON line — branch on `status`:

- **`commented`** — Copilot left inline comments (in `comments[]`, each with `path`/`line`/`body`).
  Read them, **address the valid ones in the worktree**, then `tron:git-commit` the fixes so they
  push to the PR branch. Skip any that are wrong or out of scope, and say which in your status.
  Then post a status comment: `Copilot review: N comment(s), addressed in <short-sha>` (or note the
  ones you deliberately left), ending with the `<!-- tron-note -->` marker.
- **`no-comments`** — Copilot reviewed and had nothing to flag. Post a one-line
  `Copilot review: no comments` status comment with the `<!-- tron-note -->` marker. No code changes.
- **`skipped`** — the operator set `TRON_COPILOT_UNAVAILABLE` (e.g. during a known Copilot outage)
  so the poll was skipped entirely; no gh calls were made (MD-2194). Treat exactly like `timeout`.
- **`timeout`** / **`error`** / **`skipped`** — no automated review ran. Do **not** hang, retry, or
  proceed silently — post a prominent status comment so the human gate is unmistakably the only
  review that happened: `**No automated review ran** — <reason>. Proceeding to the human approval
  gate.` (fill `<reason>` from the JSON's `reason` field; use `<!-- tron-note -->`).

Post the status comment with `gh pr comment "<N>" --body-file <tmp>`, writing the body to a unique
file from `mktemp "${TMPDIR:-/tmp}/tron-status-body.XXXXXX"` first — never inline `--body`. Only
after this status is reported is the PR genuinely ready for the human approval gate. When dispatched
(`TRON_DISPATCH_ID` set), this status comment is also how the tron-os dashboard learns the PR is
review-resolved.

## Step 8 — retro comment

Write the filled-in retro sections (this is your judgment) to a fresh temp file, then post and clean
up:

```bash
RETRO_BODY="$(mktemp "${TMPDIR:-/tmp}/tron-retro-body.XXXXXX")"
cat > "$RETRO_BODY" <<'EOF'
**What went well:**
**Friction / surprises:**
**Follow-up (filed):**
**Out of scope / not filed:**
FOLLOW-UP:
EOF
bash "$SKILL_DIR/scripts/git-pr-retro.sh" retro-comment --pr "<N>" \
  --model "<your model ID>" --body-file "$RETRO_BODY" && rm -f "$RETRO_BODY"
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

If the bundled script cannot be resolved, SKILL.md links the manual review fallback.
