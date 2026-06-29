---
name: preview-page
model: haiku
effort: low
description: Open a marketing-pages route in the user's default browser so they can visually inspect it. Spins up the Nuxt dev server on port 4001 if it isn't running, then opens the requested URL in the default browser. Use this whenever the user asks to "preview", "open in the browser", "show me the page", "load it up", "open that route", or anything similar after creating or editing a `pages/**/*.vue` file.
allowed-tools:
  - Bash
  - Read
---

# Preview Page in the Default Browser

Open a new or edited Nuxt page in the user's browser, starting the dev server first if needed. For self-verification (errors, DOM checks), use the headless `agent-browser` CLI — separate from the user's default browser.

## Preflight — confirm marketing-pages repo

```bash
git remote get-url origin 2>/dev/null | grep -qi 'marketing-pages' \
  || echo "✋ NOT in the marketing-pages repo — preview-page drives the marketing-pages dev server."
```

## Fast path (scripted)

```bash
name=preview-page
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/preview.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/preview.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/preview.sh" ] || { echo "tron:$name: scripts/preview.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/preview.sh" <route-or-file>
```

The script resolves the route, starts the dev server on 4001 if needed, opens in the browser, and saves the URL to `/tmp/preview-page-url`. Use it directly when you already know the route.

### Route resolution

| Input | Result |
|-------|--------|
| `http://localhost:4001/...` | Use as-is |
| `/resources/guides/foo` | Prefix `http://localhost:4001` |
| `pages/resources/guides/foo.vue` | Strip `pages/`, strip `.vue`, collapse `index` to parent |
| `pages/resources/news/[...slug].vue` | Ask the user for the actual slug |

## Manual path (if script unavailable)

```bash
# 1. Start dev server if not running
lsof -ti:4001 >/dev/null 2>&1 || (
  source ~/.nvm/nvm.sh && nvm use >/dev/null 2>&1
  bun dev > /tmp/preview-page-dev.log 2>&1 &
)
until grep -q "Local:" /tmp/preview-page-dev.log 2>/dev/null; do sleep 1; done

# 2. Open in browser
open "<full-url>"
```

## Figma design parity workflow

When building from a Figma design, follow the parity gate in `reference/figma-parity.md`. It covers: section-by-section comparison, side-by-side/stack/diff compare view, responsive checks, `agent-browser` self-checks, and the visual diff checklist.

### Quick self-check before handing off

```bash
U=$(cat /tmp/preview-page-url); agent-browser open "$U" && agent-browser wait --load networkidle
agent-browser errors
agent-browser get text h1
```

For more thorough checks see `reference/figma-parity.md` (cheapest-first ordering, responsive shots, screenshot guidelines).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Port 4001 busy by non-Nuxt process | `lsof -ti:4001` to check PID, ask user before killing |
| Dev server fails to start | Check `/tmp/preview-page-dev.log` — missing `.env.local`? Missing deps? Node version? |
| Page 404s but route file exists | Nuxt needs a beat to pick up new files; refresh after a second |
| `bun scripts/screenshot.sh` missing playwright | `(cd "${CLAUDE_SKILL_DIR:?}" && bun i)` — install in skill dir, NOT repo root |
| Blank/white screenshot | Page hasn't rendered yet. Use `agent-browser eval "document.readyState"` before capturing. |

**Never install skill deps (playwright, etc.) from the repo root** — use `$CLAUDE_SKILL_DIR`. Run `git diff package.json` at the repo root before committing to catch accidental clobbers.