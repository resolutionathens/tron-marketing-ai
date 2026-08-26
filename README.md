# tron — Facilitron marketing-pages AI toolkit

A shared-source Claude Code and Codex **plugin** bundling the skills that drive day-to-day work on the
[Facilitron marketing site](https://www.facilitron.com): Jira/Confluence intake, the
git task lifecycle, content drafting and handoffs, branded PDF export,
ImageKit/Figma asset operations, and audit/QA tooling.

It is its own repository so the skills can be versioned, reviewed, and installed across
Facilitron repos independently of any single project checkout.

---

## What's inside

| Group                                | Skills                                                                                                                                                                                                                                                                                  |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Ticket intake**                    | `tron:jira`, `tron:jira-comment`, `tron:create-ticket` (new tickets, rubric-enforced), `tron:ticket-lint` (self-assess vs the rubric), `tron:jira-source-discovery` (source context), `tron:jira-ticket-enricher` (write enriched description), `tron:enrich-jira-ticket` (orchestrator for both), `tron:confluence`                                                                                                       |
| **Git lifecycle**                    | `tron:start-ticket`, `tron:git-commit`, `tron:git-dev`, `tron:git-pr`, `tron:git-pushtoprod`, `tron:close-worktree`, `tron:open-worktree`, `tron:ship-ticket` (whole-flow orchestrator)                                                                                                 |
| **Work orchestration**               | `tron:orchestrate-queue` (drive one ticket or a dependency-aware batch through the control plane to the human PR gate; requires `TRON_API_URL`)                                                                                                                                   |
| **Engineering quality** (report-only) | `tron:test-driven-development` (behavior-first tests), `tron:debugging-and-error-recovery` (reproduce through verification), `tron:code-review-and-quality` (six-axis review), `tron:security-and-hardening` (trust-boundary assessment and hardening guidance), `tron:figma-inspect` (read-only implementation specifications) |
| **Assets & media**                   | `tron:figma-to-imagekit`, `tron:gen-image`, `tron:md-to-pdf`                                                                                                                                                                                                                            |
| **Preview & deploy**                 | `tron:gh`                                                                                                                                                                                                                                                                               |
| **CI / pipelines**                   | `tron:circleci` (list/watch pipelines, fetch logs, validate `.circleci/config.yml`)                                                                                                                                                                                                     |
| **Worker runtime** (read-only)       | `tron:okf-query` (pull OKF playbooks by type/tags mid-task over `TRON_API_URL`, select-then-load)                                                                                                                                                                                       |
| **Thinking & meetings**              | `tron:brainstorm` (ideation), `tron:grill` (artifact critique), `tron:weekly-update` (Jira-first weekly status email → clipboard)                                                                                                                                                       |
| **Designer** (git-free intake/audit) | `tron:creative-request` (ticket → design brief + asset plan), `tron:brand-check` (palette / `tron-` tokens / logo / WCAG contrast)                                                                                                                                                      |
| **Content drafting** (git-free)      | `tron:case-study`, `tron:press-release`, `tron:email-campaign`, `tron:onesheet`                                                                                                                                                                                                         |
| **SEO** (git-free)                   | `tron:seo-audit`, `tron:keyword-research`, `tron:landing-page-seo`, `tron:seo-report` (work with the seo.facilitron.work GSC report)                                                                                                                                                    |
| **Manager / board** (git-free)       | `tron:board-triage`, `tron:initiative-report`, `tron:board-scaffold`                                                                                                                                                                                                                    |
| **Video** (git-free)                 | `tron:video-brief` (brief + script + shot list), `tron:video-publish` (YouTube/social publishing kit)                                                                                                                                                                                   |
| **Social** (git-free)                | `tron:social-post` (IG/FB/LI variants), `tron:spotlight` (new-hire / people / district / facility spotlights)                                                                                                                                                                           |
| **Audits & QA** (read-only)          | `tron:a11y-scan` (WCAG via axe/pa11y), `tron:link-check` (broken links), `tron:prose-lint` (prose/style), `tron:site-audit` (site-wide Lighthouse), `tron:optimize-images` (pngquant) — each delegates the mechanical run to a cost-scoped runner subagent (Haiku, or Sonnet for prose) |

Plugin skills invoke as `tron:<name>` (for example, `/tron:jira`). The website-publishing
`news-item`, `toolkit-item`, and `guide-item` skills are repo-local to marketing-pages and invoke by
bare name. A cross-repo handoff must create or reopen a marketing-pages worktree and add that
directory to the session before invoking them; they only appear in the listing after the directory
is added.

`tron:orchestrate-queue` is the single worker-orchestration entry point. Remove or disable legacy
user-level `orchestrate-workers` and `orchestrate-epic` commands; they must not expose a second
worker transport beside the control plane.

---

## Core and role packages

The authored catalog remains in `skills/` once. [`packages/package-map.json`](packages/package-map.json)
classifies every skill into exactly one owner and defines eight scoped release packages:
`tron-core`, `tron-engineer`, `tron-designer`, `tron-content`, `tron-seo`, `tron-manager`,
`tron-social`, and `tron-video`. The seven role packages extend `tron-core`; `tron-core` is also
available on its own for shared ticket-intake and worker-runtime capabilities.

Each scoped package is self-contained. The package map explicitly declares each package's shared
agents and tool directories. The builder copies that declared closure alongside the selected skill
directories, hooks, the dispatched-worker contract, and skill-local assets, and rejects missing,
escaping, or symlinked resources.
Scoped packages do not read another installed plugin's filesystem, so installing a role package
does not require installing `tron-core` beside it. Shared capabilities can consequently appear in
more than one built package while retaining one authored source and one declared owner.

Build and validate the complete matrix locally:

```sh
node tools/package/build-packages.mjs dist/packages
bash tools/package/test-build-packages.sh
```

### Repo bundles

The same package map also declares a bundle per consuming repository under `repos`, using the
identical `extends` / `skills` / `resources` shape. A repo key builds as `tron-repo-<key>`, so
`marketing-pages` releases as `tron-repo-marketing-pages` for both harnesses. The point is scope: a
worker dispatched into a repo installs only the skills that repo actually uses, which keeps the
router surface small and keeps an irrelevant skill from misfiring. `tron-repo-facilitron-ui`, for
instance, omits `git-pushtoprod` because that library finishes at its `dev` branch.

Repo bundles extend role packages, never each other, and no package may extend a repo bundle. They
go through the same dependency-closure, namespace-rewrite, and handoff validation as the role
packages, and they ship in the same release with the same attestation and checksums. Which bundle a
repository gets is decided outside this repo; what a bundle contains is decided here.

The build emits matching Claude and Codex inventories from the same source and version. Generated
skill prose rewrites an in-package `tron:<skill>` reference to the current package namespace. A
reference outside the current inventory is rewritten to its declared owner, such as
`tron-engineer:git-pr`, making the cross-role handoff explicit instead of pretending the skill is
local. Repository-writing content pipelines live only in marketing-pages and are intentionally
absent from every plugin bundle; `tron-content` stays limited to drafting, critique, and content QA. The generated inventory
records the monolith and scoped package IDs plus their
mutual-exclusion rule so migration tooling can validate that a consumer enables exactly one
distribution shape.

### Migration from the monolithic package

The monolithic `tron@tron` package remains available during migration and rollback. A consumer
must enable either that package or one scoped package, not both, because their inventories overlap.

1. Choose the scoped package matching the worker profile.
2. Replace `tron:*` references in role configuration with `tron-<role>:*`.
3. Install the matching Claude or Codex artifact from the same release version.
4. Verify the required skill inventory before disabling `tron@tron`.
5. Roll back by re-enabling the version-pinned monolith and restoring `tron:*` references.

Cross-role handoffs must target a skill present in the caller's built inventory. If a workflow
needs a skill outside that inventory, route the work to a worker with the owning package instead
of reaching into another plugin directory.

---

## Installing it (consumer repos)

### Codex

Add the repository as a marketplace, then install the native Codex package:

```sh
codex plugin marketplace add resolutionathens/tron-marketing-ai
codex plugin add tron@tron
```

Start a new Codex conversation after installation so its skills are discovered. The Codex
package references the same `skills/`, `agents/`, `tools/`, and `hooks/` source as Claude Code;
there is no harness-specific copy of any `SKILL.md`.

### Claude Code

Add the marketplace and enable the plugin in the consumer repo's `.claude/settings.json`
(this is what `marketing-pages` does):

```jsonc
{
  "extraKnownMarketplaces": {
    "tron": {
      "source": { "source": "github", "repo": "resolutionathens/tron-marketing-ai" },
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
      "source": { "source": "github", "repo": "resolutionathens/tron-marketing-ai" },
      "autoUpdate": true
    }
  }
  ```

- **Update notice** — even without auto-update, the plugin ships a `SessionStart` hook
  (`hooks/check-update.sh`) that compares your installed `version` against the newest version
  in its own release channel and returns a one-line SessionStart system message when you're
  behind. To update manually:

  ```
  claude plugin update tron@tron
  ```

  For a tron-os release-store install, run `tron-os reconcile-tron-release` first, then run
  the plugin update command. The check is fail-silent (never blocks startup), network-frugal for
  GitHub marketplace installs (cached daily), and silent when its channel is indeterminate.

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

## Releases

A dedicated release PR, containing a synchronized manifest version bump and `releases/v<version>.md`, starts
`.github/workflows/release.yml`. The workflow builds monolithic Claude and Codex archives plus
both-harness artifacts for every scoped package from the same commit. It records their file
inventories and SHA-256 values in `release-manifest.json`, verifies the uploaded assets and build
provenance, and only then publishes the draft as GitHub's latest release. Consumers can resolve
the current approved version through:

```text
GET https://api.github.com/repos/resolutionathens/tron-marketing-ai/releases/latest
```

The repository must have **Settings → Releases → Immutable releases** enabled. A failed build or
upload deletes its draft and cannot change the latest-release pointer.

To publish, explicitly ask to **cut the next Tron plugin release**. Ordinary feature and fix PRs
must leave both manifest versions unchanged. The release workflow then:

1. Select the semver bump from commits since the previous release tag, synchronize both manifests,
   and add `releases/v<version>.md` with the prior boundary and change summary.
2. Merge the reviewed dedicated release PR to `master`. Its record and manifest change start the release workflow.
3. Confirm the workflow's checksum and artifact-attestation verification passes.

To retry a failed release after correcting its cause, run **Publish immutable Tron release** from
the Actions tab. The workflow never replaces an existing version.

To roll back adoption, first verify the target release and its assets:

```sh
gh release download v0.33.0 --dir /tmp/tron-rollback
(cd /tmp/tron-rollback && shasum -a 256 -c SHA256SUMS)
gh attestation verify /tmp/tron-rollback/tron-claude-v0.33.0.tar.gz \
  --repo resolutionathens/tron-marketing-ai
```

`gh release verify` looks for an attestation on the release tag. Tron attests the release artifacts,
so verify downloaded artifact files with `gh attestation verify` instead. Repeat the artifact command
for each package when validating a complete release.

After maintainer approval, move only the current pointer to that already-immutable release:

```sh
gh release edit v0.33.0 --latest
```

This does not modify or republish either version. Consumers resolving the latest-release endpoint
adopt the rollback target, while pinned artifact URLs remain unchanged.

---

## Dependencies

The skills shell out to a number of CLIs and services that **do not ship with macOS**.
Install what you need for the skills you'll actually use — nothing here is required just
to load the plugin; a skill only fails if you invoke it without its tool present.

### Command-line tools

| Tool                                     | Install (macOS)                                                                           | Needed by                                                                                                                |
| ---------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **acli** (Atlassian CLI)                 | [Atlassian CLI docs](https://developer.atlassian.com/cloud/acli/) — then `acli jira auth` | `jira`, `jira-comment`, `enrich-jira-ticket`, `jira-source-discovery`, `jira-ticket-enricher`, `confluence`, `start-ticket`, `ship-ticket` |
| **tmux** (terminal multiplexer)          | `brew install tmux`                                                                       | `start-ticket`, `open-worktree`, `close-worktree`, `ship-ticket`                                                         |
| **gh** (GitHub CLI)                      | `brew install gh` → `gh auth login`                                                       | `gh`, `git-pr`, `git-pushtoprod`, `start-ticket`, `ship-ticket`                                                          |
| **bun**                                  | `brew install oven-sh/bun/bun`                                                            | `md-to-pdf`                                                                                                              |
| **node** (Node.js)                       | `brew install node`                                                                       | ImageKit CLI consumers + `md-to-pdf`                                                                                     |
| **lychee** (link checker)                | `brew install lychee`                                                                     | `link-check`                                                                                                             |
| **pa11y / axe** (a11y scanners)          | `npm i -g pa11y pa11y-ci @axe-core/cli`                                                   | `a11y-scan`                                                                                                              |
| **vale** (prose linter)                  | `brew install vale`                                                                       | `prose-lint`                                                                                                             |
| **unlighthouse** (site Lighthouse)       | `npx unlighthouse` (no install; downloads Chromium on first run)                          | `site-audit`                                                                                                             |
| **pngquant** (PNG compressor)            | `brew install pngquant`                                                                   | `optimize-images`                                                                                                        |
| **pandoc**                               | `brew install pandoc`                                                                     | `md-to-pdf` (pandoc fallback path)                                                                                       |
| **xelatex** (BasicTeX/MacTeX)            | `brew install --cask basictex` (+ `tlmgr install` extras)                                 | `md-to-pdf` (preferred LaTeX path)                                                                                       |
| **codex** (OpenAI Codex CLI)             | `npm i -g @openai/codex` → `codex login`                                                  | `gen-image`                                                                                                              |
| **jq**                                   | `brew install jq`                                                                         | `gh`, `start-ticket`                                                                                                     |
| **webp / cwebp**                         | `brew install webp`                                                                       | shared image conversion fallback                                                                                         |
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

The **ImageKit CLI** is vendored in the plugin at `tools/imagekit/imagekit.mjs` for plugin media
workflows such as `figma-to-imagekit`. Skills invoke it via
`${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs`, so it
resolves from any skill regardless of cwd.

It authenticates through the **org-secret broker** at `secrets.facilitron.work`
using a short-lived Cloudflare Access token (no local `IMAGEKIT_PRIVATE_KEY`
needed). This is transparent to any skill that invokes it — the CLI fetches
the token on each call.

### MCP servers

- **Figma Dev Mode MCP** — required by `tron:figma-to-imagekit`. `tron:figma-inspect` instead uses the broker's per-user Figma OAuth connection and does not require MCP. Connect MCP in Claude
  Code before running figma exports.

### Environment variables

Copy [`.env.example`](.env.example) and fill in your own values. These usually live in
`~/.env` (generated by 1Password) and are auto-sourced; skills fall back to
`set -a; source ~/.env; set +a` if a token is missing. You can equally export them in
your shell or add them to your `marketing-pages/.env.local`.

| Var                   | Used for                                                                                                 |
| --------------------- | -------------------------------------------------------------------------------------------------------- |
| `ATLASSIAN_EMAIL`     | Confluence attachment **download** basic auth, and the direct-auth fallback if the broker is unavailable; falls back to `git config user.email` |
| `JIRA_API_TOKEN`      | Confluence attachment **download** basic auth, and the direct-auth fallback if the broker is unavailable (`confluence`) |
| `CONFLUENCE_CLOUD_ID` | _(optional)_ override the Confluence cloud ID — defaults to Facilitron's instance                        |
| `CONFLUENCE_BASE`     | _(optional)_ override the Confluence wiki base URL — defaults to `https://facilitron.atlassian.net/wiki` |
| `WEEKLY_UPDATE_RECIPIENT` | _(optional)_ `weekly-update`'s report recipient / template owner — defaults to `Kristina`      |
| `WEEKLY_UPDATE_MANAGER`   | _(optional)_ `weekly-update`'s second greeting name (your manager) — defaults to `Dave`        |
| `WEEKLY_UPDATE_DEADLINE`  | _(optional)_ `weekly-update`'s reporting deadline — defaults to `Tuesday 9am PST / 12pm EST`   |

- **1Password** (app + optional `op` CLI, `brew install 1password-cli`) populates `~/.env`.
  If a skill reports a token is unset, the 1Password agent likely isn't running.
- Tools with their own auth (`acli`, `gh`, `codex`) aren't env vars — log in separately.
- As of MD-1995, `tools/confluence/fetch-confluence.sh`'s page-body fetch and attachment
  *listing* go through the **org-secret broker** at `secrets.facilitron.work` first (same
  Cloudflare Access token pattern as ImageKit above) — `ATLASSIAN_EMAIL`/`JIRA_API_TOKEN` are
  only consulted as a fallback, or for the attachment *download* leg, which the broker doesn't
  proxy yet (blocked on MD-2011). The six `acli`-based Jira skills (`jira`, `jira-comment`,
  `enrich-jira-ticket`, `board-triage`, `start-ticket`, `weekly-update`) stay on `acli`'s own
  OAuth session — `acli` has no way to point at a proxy; see
  [tools/jira/broker-status.md](tools/jira/broker-status.md).

---

## Repo layout

```
tron-marketing-ai/
├── .agents/plugins/          # native Codex marketplace manifest
├── .claude-plugin/
│   ├── plugin.json          # the plugin manifest (name: tron)
│   └── marketplace.json     # single-plugin marketplace, source "."
├── .codex-plugin/           # native Codex plugin manifest, sharing skills/
├── .github/workflows/       # CI and immutable-release workflows
├── packages/
│   └── package-map.json     # scoped package ownership and resource closures
├── skills/                  # one dir per skill
│   ├── md-to-pdf/           # bundles build.ts, template.tex, fonts/, logo
│   ├── prose-lint/          # bundles the Facilitron Vale style pack under styles/
│   └── …
├── agents/                  # runner subagents the audit skills delegate to (Haiku/Sonnet)
│   ├── a11y-scan-runner.md  # axe/pa11y · lychee-link-runner · unlighthouse-runner ·
│   └── …                    # optimize-images-runner · vale-prose-runner · confluence-transformer
├── hooks/                   # SessionStart update-notice hook (check-update.sh + hooks.json)
├── evaluations/             # skill-evaluation scenarios run by tools/evaluate (see TESTING.md)
├── WORKER_CONTRACT.md       # non-interactive dispatched-worker rules and PR gate
├── TESTING.md                # test layers and commands for plugin contributors
├── tools/                   # shared, plugin-level tooling (referenced via CLAUDE_PLUGIN_ROOT)
│   ├── broker/              # org-secret broker access and credential-minting docs
│   ├── imagekit/            # vendored ImageKit CLI (node_modules lazy-installed, not committed)
│   ├── md-to-adf/           # vendored markdown→ADF helper for Jira (lazy-installed)
│   ├── confluence/          # fetch-confluence.sh + confluence-lib.sh — Confluence body and attachment helpers
│   ├── content/             # content.sh + content-lib.sh + dev-server.sh — slug/check-repo/dev-server helpers
│   ├── git/                 # git-promote.sh + token-usage.sh — deterministic git flows + PR retro stats
│   ├── ticket/              # ticket-lib.sh — shared Jira/GitHub lookup helpers (start-ticket, ship-ticket)
│   ├── worktree/            # worktree-lib.sh — shared worktree path/resolution helpers
│   ├── image/               # to-webp.sh + image-pipeline.sh + generate-card.sh + images-to-imagekit.md
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

## Developing and verifying

This repository ships instructions, deterministic scripts, and packaged assets rather than an app.
See [CLAUDE.md](CLAUDE.md) for authoring rules, [TESTING.md](TESTING.md) for the complete test
matrix, and [WORKER_CONTRACT.md](WORKER_CONTRACT.md) for the non-interactive worker and PR-gate
rules.

Run the smallest relevant check while editing, then the package test when changing package
ownership, shared resources, cross-skill handoffs, agents, or skill-local assets:

```sh
# A changed deterministic script
bash skills/<skill>/scripts/test-<skill>.sh

# All deterministic script and shared-tool tests
bash tools/lint/run-layer1-tests.sh

# Frontmatter and fast-path resolver checks
bash tools/lint/check-scout-frontmatter.sh
bash tools/lint/check-fastpath-resolvers.sh

# Scoped Claude/Codex package inventories and dependency closures
bash tools/package/test-build-packages.sh
```

CI also validates native Claude and Codex package installation and deterministic release builds.
The release fixture requires a clean tree, so run it after the atomic commit. If tracked changes
remain, commit them and rerun `bash tools/release/test-build-release.sh`.
