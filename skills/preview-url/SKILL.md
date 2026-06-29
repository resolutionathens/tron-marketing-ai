---
name: preview-url
model: haiku
effort: low
description: "Given a branch (default: current) and a repo (default: cwd), find the staging/preview URL where the latest commit is deployed. Detects the deploy target from repo signals (`.circleci/config.yml`, `wrangler.{toml,jsonc}`) and routes to the right lookup. Use this skill whenever the user asks 'where's my staging link', 'what's the preview URL for this PR', 'where did this deploy', 'has staging updated yet', 'can you grab the deploy URL'. This skill just resolves the URL — for CircleCI pipeline internals use tron:circleci; for GitHub Actions runs use tron:gh."
allowed-tools:
  - Bash
  - Read
---

# Preview URL Finder

Find the staging/preview URL for a deployed branch. Detects the deploy target and delegates to the right lookup. The Facilitron stack deploys two ways: **CircleCI** (marketing-pages and friends → fixed dev/staging/prod URLs) and **Cloudflare Workers** (Scout, the broker → no per-PR preview).

## Fast path (deterministic)

```bash
name=preview-url
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/preview-url.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/preview-url.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/preview-url.sh" ] || { echo "tron:$name: scripts/preview-url.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/preview-url.sh" [--repo <path>] [--branch <branch>]
```

Detects the deploy target from filesystem signals. One JSON line:

```json
{"ok":true,"target":"cf-workers","branch":"x","url":null,"confidence":"n/a","reason":"workers has no per-PR preview …"}
{"ok":true,"target":"circleci","branch":"x","url":null,"confidence":"low","reason":"consult the branch→URL table"}
{"ok":false,"target":"unknown","branch":"x","url":null,"reason":"no deploy signal — ask the user"}
```

| `target` | Action |
|----------|--------|
| `circleci` | Look the branch up in the branch→URL table below (Facilitron repos have fixed mappings). |
| `cf-workers` | No per-PR preview exists. Use the dev server or merge to prod. |
| `unknown` | Ask the user where it deploys. |

Smoke the detection with `bash "$SKILL_DIR/scripts/test-preview-url.sh"`.

## Detection logic

| Signal in repo | Target |
|----------------|--------|
| `wrangler.{toml,jsonc}` | Cloudflare Workers — no preview URL |
| `.circleci/config.yml` | CircleCI (branch→fixed URL) |

## Workers gotcha

**Cloudflare Workers does not create per-PR preview URLs.** Each deploy overwrites production. No preview exists — use the dev server or merge to main.

## Facilitron branch→URL table (CircleCI repos)

### marketing-pages

| Branch | URL |
|--------|-----|
| `dev` | https://morning-coast.facilitron.com |
| `staging` | https://staging.facilitron.com |
| `production` | https://www.facilitron.com |

Only `dev`, `staging`, and `production` deploy — feature/PR branches have no per-PR preview. Merge into dev and check the dev URL after CircleCI finishes. Check sibling repos' READMEs for their own URL tables.

## When the script misses

For a CircleCI repo, the branch→URL table above is the answer. To confirm the deploy job actually finished (or find which job deploys), use **tron:circleci**. For a Cloudflare Workers repo there is no preview — check the dev server, or production after merge.

When returning the URL, lead with the URL itself. One line. Then confidence + how to verify.
