# tron — Facilitron marketing-pages AI toolkit

A Claude Code **plugin** bundling the skills that drive day-to-day work on the
[Facilitron marketing site](https://www.facilitron.com): Jira/Confluence intake, the
git task lifecycle, content pipelines (news, toolkit, guides), branded PDF export,
ImageKit/Figma asset operations, and audit/QA tooling.

It is its own repository so the skills can be versioned, reviewed, and installed across
Facilitron repos independently of any single project checkout.

---

## What's inside

| Group                                | Skills                                                                                                                                                                                                                                                                                  |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Ticket intake**                    | `tron:jira`, `tron:jira-comment`, `tron:create-ticket` (new tickets, rubric-enforced), `tron:ticket-lint` (self-assess vs the rubric), `tron:enrich-jira-ticket`, `tron:confluence`                                                                                                       |
| **Git lifecycle**                    | `tron:start-ticket`, `tron:git-commit`, `tron:git-dev`, `tron:git-pr`, `tron:git-pushtoprod`, `tron:close-worktree`, `tron:open-worktree`, `tron:ship-ticket` (whole-flow orchestrator)                                                                                                 |
| **Content pipelines**                | `tron:news-item`, `tron:toolkit-item`, `tron:guide-item`                                                                                                                                                                                                                                |
| **Assets & media**                   | `tron:figma-to-imagekit`, `tron:gen-image`, `tron:md-to-pdf`                                                                                                                                                                                                                            |
| **Preview & deploy**                 | `tron:gh`                                                                                                                                                                                                                                                                               |
| **CI / pipelines**                   | `tron:circleci` (list/watch pipelines, fetch logs, validate `.circleci/config.yml`)                                                                                                                                                                                                     |
| **Thinking & meetings**              | `tron:brainstorm` (ideation), `tron:grill` (artifact critique), `tron:weekly-update` (Jira-first weekly status email → clipboard)                                                                                                                                                       |
| **Designer** (git-free intake/audit) | `tron:creative-request` (ticket → design brief + asset plan), `tron:brand-check` (palette / `tron-` tokens / logo / WCAG contrast)                                                                                                                                                      |
| **Content drafting** (git-free)      | `tron:case-study`, `tron:press-release`, `tron:email-campaign`, `tron:onesheet`                                                                                                                                                                                                         |
| **SEO** (git-free)                   | `tron:seo-audit`, `tron:keyword-research`, `tron:landing-page-seo`, `tron:seo-report` (work with the seo.facilitron.work GSC report)                                                                                                                                                    |
| **Manager / board** (git-free)       | `tron:board-triage`, `tron:initiative-report`, `tron:board-scaffold`                                                                                                                                                                                                                    |
| **Video** (git-free)                 | `tron:video-brief` (brief + script + shot list), `tron:video-publish` (YouTube/social publishing kit)                                                                                                                                                                                   |
| **Social** (git-free)                | `tron:social-post` (IG/FB/LI variants), `tron:spotlight` (new-hire / people / district / facility spotlights)                                                                                                                                                                           |
| **Audits & QA** (read-only)          | `tron:a11y-scan` (WCAG via axe/pa11y), `tron:link-check` (broken links), `tron:prose-lint` (prose/style), `tron:site-audit` (site-wide Lighthouse), `tron:optimize-images` (pngquant) — each delegates the mechanical run to a cost-scoped runner subagent (Haiku, or Sonnet for prose) |

Skills invoke as `tron:<name>` (e.g. `/tron:news-item`). The content skills
(`news-item`, `toolkit-item`, `guide-item`) run a **preflight repo guard** and
refuse to write unless the current checkout is `marketing-pages`.

---

## Installing it (consumer repos)

Add the marketplace and enable the plugin in the consumer repo's `.claude/settings.json`
(this is what `marketing-pages` does):

```jsonc
{
  "extraKnownMarketplaces": {
    "tron": {
      "source": { "source": "github", "repo": "Facilitron/tron-marketing-ai" },
    },
  },
  "enabledPlugins": { "tron@tron": true },
}
```

On the next session Claude Code fetches the marketplace, installs the plugin into its
cache, and the `tron:*` skills become available.

### Staying up to date

Third-party marketplaces don't auto-update by default, so an installed copy can drift behind
`master`. Two things help:

- **Opt into auto-update** — add `"autoUpdate": true` to the `tron` marketplace entry so
  Claude Code pulls the latest version at session start:

  ```jsonc
  "extraKnownMarketplaces": {
    "tron": {
      "source": { "source": "github", "repo": "Facilitron/tron-marketing-ai" },
      "autoUpdate": true
    }
  }
  ```

- **Update notice** — even without auto-update, the plugin ships a `SessionStart` hook
  (`hooks/check-update.sh`) that compares your installed `version` against `master` once a
  day and prints a one-line notice when you're behind. To update manually:

  ```
  /plugin marketplace update tron
  /plugin install tron@tron --force
  /reload-plugins
  ```

  The check is fail-silent (never blocks startup) and network-frugal (cached daily).

### Developing the plugin (live edit loop)

The github source caches the plugin, so edits don't show up until you push + update.
While **working on the skills**, add the local checkout as a directory marketplace
instead, so edits are picked up without a round-trip:

```
/plugin marketplace add /path/to/tron-marketing-ai
/plugin install tron@tron
```

Use the github source for the committed team setup; the local directory source for
authoring.

---

## Dependencies

The skills shell out to a number of CLIs and services that **do not ship with macOS**.
Install what you need for the skills you'll actually use — nothing here is required just
to load the plugin; a skill only fails if you invoke it without its tool present.

### Command-line tools

| Tool                                     | Install (macOS)                                                                           | Needed by                                                                                                                |
| ---------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **acli** (Atlassian CLI)                 | [Atlassian CLI docs](https://developer.atlassian.com/cloud/acli/) — then `acli jira auth` | `jira`, `jira-comment`, `enrich-jira-ticket`, `confluence`, `start-ticket`, `ship-ticket`, `news-item`, `guide-item`, `toolkit-item` |
| **tmux** (terminal multiplexer)          | `brew install tmux`                                                                       | `start-ticket`, `open-worktree`, `close-worktree`, `ship-ticket`                                                         |
| **gh** (GitHub CLI)                      | `brew install gh` → `gh auth login`                                                       | `gh`, `git-pr`, `git-pushtoprod`, `start-ticket`, `ship-ticket`                                                          |
| **bun**                                  | `brew install oven-sh/bun/bun`                                                            | `md-to-pdf`, `news-item`, `guide-item`, `toolkit-item`                                                                   |
| **node** (Node.js)                       | `brew install node`                                                                       | ImageKit CLI consumers + `md-to-pdf`                                                                                     |
| **lychee** (link checker)                | `brew install lychee`                                                                     | `news-item`, `toolkit-item`, `guide-item`, `link-check`                                                                  |
| **pa11y / axe** (a11y scanners)          | `npm i -g pa11y pa11y-ci @axe-core/cli`                                                   | `a11y-scan`                                                                                                              |
| **vale** (prose linter)                  | `brew install vale`                                                                       | `prose-lint`                                                                                                             |
| **unlighthouse** (site Lighthouse)       | `npx unlighthouse` (no install; downloads Chromium on first run)                          | `site-audit`                                                                                                             |
| **pngquant** (PNG compressor)            | `brew install pngquant`                                                                   | `optimize-images`                                                                                                        |
| **pandoc**                               | `brew install pandoc`                                                                     | `md-to-pdf` (pandoc fallback path)                                                                                       |
| **xelatex** (BasicTeX/MacTeX)            | `brew install --cask basictex` (+ `tlmgr install` extras)                                 | `md-to-pdf` (preferred LaTeX path)                                                                                       |
| **codex** (OpenAI Codex CLI)             | `npm i -g @openai/codex` → `codex login`                                                  | `gen-image`, `guide-item`, `toolkit-item` (card images)                                                                  |
| **jq**                                   | `brew install jq`                                                                         | `gh`, `start-ticket`                                                                                                     |
| **webp / cwebp**                         | `brew install webp`                                                                       | image fallback for `news-item`, `guide-item`, `toolkit-item` (primary path uses Bun's built-in `Bun.Image` — no install) |
| **librsvg / rsvg-convert**               | `brew install librsvg`                                                                    | `md-to-pdf` (only to regenerate the logo PNG — rare)                                                                     |
| **ripgrep (rg)**                         | `brew install ripgrep`                                                                    | recommended for the internal-link `find`/grep checks                                                                     |

`git`, `curl`, and `sips` ship with macOS — no install needed.

### Bundled tools

The plugin vendors a couple of Node CLIs under `tools/`, each invoked via
`${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/<name>/…` and each **lazy-installing**
its own `node_modules` on first run (not committed — needs `node` + `npm` + network the
first time, then runs offline):

- **`md-to-adf`** (`tools/md-to-adf/md-to-adf.mjs`) — converts markdown → Atlassian Document
  Format JSON for rich Jira descriptions (`tron:jira`, `tron:enrich-jira-ticket`). Wraps
  `markdown-to-adf` (`story` preset).

The plugin also carries a versioned **ticket rubric** at `tools/ticket/ticket-rubric.md` (the shared
spec behind `tron:create-ticket`, `tron:ticket-lint`, and Scout triage) with a deterministic,
offline parser (`tools/ticket/rubric-lint.sh` + `rubric-lib.sh`, tested by `test-rubric-lint.sh`).
No install needed: pure bash, with `jq` required for the JSON output (all modes) and `acli`
additionally for the `--key` (live-ticket) path.

**ImageKit CLI**

The **ImageKit CLI** is vendored in the plugin at `tools/imagekit/imagekit.mjs` and used by
every skill that uploads media (`news-item`, `guide-item`, `toolkit-item`,
`figma-to-imagekit`, `md-to-pdf`). Skills invoke it via
`${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs`, so it
resolves from any skill regardless of cwd.

It authenticates through the **org-secret broker** at `secrets.facilitron.work`
using a short-lived Cloudflare Access token (no local `IMAGEKIT_PRIVATE_KEY`
needed). This is transparent to any skill that invokes it — the CLI fetches
the token on each call.

### MCP servers

- **Figma Dev Mode MCP** — required by `tron:figma-to-imagekit`. Connect it in Claude
  Code before running figma exports.

### Environment variables

Copy [`.env.example`](.env.example) and fill in your own values. These usually live in
`~/.env` (generated by 1Password) and are auto-sourced; skills fall back to
`set -a; source ~/.env; set +a` if a token is missing. You can equally export them in
your shell or add them to your `marketing-pages/.env.local`.

| Var                   | Used for                                                                                                 |
| --------------------- | -------------------------------------------------------------------------------------------------------- |
| `ATLASSIAN_EMAIL`     | Confluence REST basic auth (attachment downloads); falls back to `git config user.email`                 |
| `JIRA_API_TOKEN`      | Confluence/Jira REST + attachment downloads (`confluence`, `news-item`, `guide-item`)                    |
| `CONFLUENCE_CLOUD_ID` | _(optional)_ override the Confluence cloud ID — defaults to Facilitron's instance                        |
| `CONFLUENCE_BASE`     | _(optional)_ override the Confluence wiki base URL — defaults to `https://facilitron.atlassian.net/wiki` |

- **1Password** (app + optional `op` CLI, `brew install 1password-cli`) populates `~/.env`.
  If a skill reports a token is unset, the 1Password agent likely isn't running.
- Tools with their own auth (`acli`, `gh`, `codex`) aren't env vars — log in separately.

---

## Repo layout

```
tron-marketing-ai/
├── .claude-plugin/
│   ├── plugin.json          # the plugin manifest (name: tron)
│   └── marketplace.json     # single-plugin marketplace, source "."
├── skills/                  # one dir per skill
│   ├── md-to-pdf/           # bundles build.ts, template.tex, fonts/, logo
│   ├── prose-lint/          # bundles the Facilitron Vale style pack under styles/
│   └── …
├── agents/                  # runner subagents the audit skills delegate to (Haiku/Sonnet)
│   ├── a11y-scan-runner.md  # axe/pa11y · lychee-link-runner · unlighthouse-runner ·
│   └── …                    # optimize-images-runner · vale-prose-runner · confluence-transformer
├── hooks/                   # SessionStart update-notice hook (check-update.sh + hooks.json)
├── evaluations/             # skill-evaluation scenarios run by tools/evaluate (see TESTING.md)
├── tools/                   # shared, plugin-level tooling (referenced via CLAUDE_PLUGIN_ROOT)
│   ├── imagekit/            # vendored ImageKit CLI (node_modules lazy-installed, not committed)
│   ├── md-to-adf/           # vendored markdown→ADF helper for Jira (lazy-installed)
│   ├── confluence/          # fetch-confluence.sh + confluence-lib.sh — used by confluence, news-item, guide-item
│   ├── content/             # content.sh + content-lib.sh + dev-server.sh — slug/check-repo/dev-server helpers
│   ├── git/                 # git-promote.sh + token-usage.sh — deterministic git flows + PR retro stats
│   ├── ticket/              # ticket-lib.sh — shared Jira/GitHub lookup helpers (start-ticket, ship-ticket)
│   ├── worktree/            # worktree-lib.sh — shared worktree path/resolution helpers
│   ├── image/               # to-webp.sh + image-pipeline.sh + generate-card.sh + images-to-imagekit.md — news-item, guide-item, toolkit-item
│   └── evaluate/            # evaluate.mjs — the skill-evaluation harness (see TESTING.md)
├── TESTING.md
└── README.md
```

Two reference patterns:

- A skill's **own** bundled files resolve through **`$CLAUDE_SKILL_DIR`** (set by the
  plugin to that skill's directory) — e.g. `md-to-pdf` and `prose-lint`, whose assets
  are single-skill.
- **Shared** tooling used by several skills lives once under `tools/` and resolves through
  **`${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/…`** — the `CLAUDE_PLUGIN_ROOT`
  var with a fallback two levels up from the skill dir, so it works whichever variable the
  runtime exports.
