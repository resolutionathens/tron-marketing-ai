# CLAUDE.md — working on the `tron` plugin

This repo **is a Claude Code plugin**, not an app. There's nothing to build or serve — the
deliverable is the instruction layer itself: `skills/*/SKILL.md`, `agents/*.md`, the bundled
`tools/`, and `hooks/`. Editing those files _is_ the work. See [README.md](README.md) for the
consumer-facing install/dependency docs; this file is for editing the plugin. See
[WORKER_CONTRACT.md](WORKER_CONTRACT.md) for what a dispatched (non-interactive) worker gets and
is bound by when it runs a skill from this plugin — env vars, the PR-gate autonomy model,
unavailable tools, and the broker credential-minting pattern.

## Layout

- `skills/<name>/SKILL.md` — one dir per skill; the markdown body is the instructions.
- `skills/<name>/scripts/` — deterministic bash that the SKILL.md shells out to (see below).
- `agents/*.md` — cost-scoped runner subagents the audit skills delegate the mechanical run to.
- `tools/` — shared, multi-skill tooling, resolved via `CLAUDE_PLUGIN_ROOT` (see Path resolution).
- `.claude-plugin/{plugin.json,marketplace.json}` — manifest + single-plugin marketplace.

## SKILL.md frontmatter

Every skill declares `name`, `description`, `model`, `effort`, a `scout:` display block (see
below), and (when it needs more than the default) `allowed-tools`. The `description` is the
**only** thing the router sees — it must carry the trigger phrases, so keep it dense and
example-heavy.

### Model + effort routing (deliberate — match the tier to the work)

| Tier                      | Use for                                                                  | Examples                                                                                        |
| ------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `haiku` / `low`           | Pure orchestration — resolve a target, shell out, hand off. No judgment. | `jira`, `confluence`, all 5 audit skills (the _agent_ does any heavier work)                    |
| `sonnet` / `low`–`medium` | Most skills: light judgment, drafting, git flows, board ops.             | `git-commit`, `seo-audit`, `board-triage`, `figma-to-imagekit`                                  |
| `opus` / `high`           | Long-form generation and critique where quality dominates cost.          | `news-item`, `guide-item`, `toolkit-item`, `case-study`, `press-release`, `brainstorm`, `grill` |

When you add or edit a skill, pick the cheapest tier that does the job. An orchestration-only
skill set to `sonnet` is a routing bug (this is what was wrong with `a11y-scan`). If a skill says
"runs on Haiku to keep cost low," its frontmatter must agree.

### The `scout:` block (required on every skill — MD-2006/MD-2007)

The Scout desktop app (tron-os) derives its user-facing skills catalog from this frontmatter.
The `description` is written for the agent router; `scout:` is written for a human reading a
card. **A skill without a scout block defaults to user-surfaced with auto-derived card text** —
the agent-prose-on-a-card problem this block exists to prevent — so every new skill must declare
one.

```yaml
scout:
  surface: true            # true | developer | false — see the tier rule below
  title: "Get a ticket dev-ready"        # verb-first human title; the card's headline
  blurb: "Fleshes out thin tickets with background, links, and acceptance criteria."
  when: "A ticket is just a title and someone needs to actually build it."
  category: tickets        # tickets | drafting | qa | seo | media → Scout's task groups
  effects: [jira]          # draft | report | jira | publish | cdn | local
  inputs:                  # the run form Scout renders before launching
    - key: tickets
      label: "Ticket key(s)"
      type: text           # text | textarea | path (path gets a Browse picker)
      required: true
      placeholder: "MD-1234, MD-1235"   # optional; also: help, accept (e.g. ".md,.png")
```

**Surface tier rule:** anything that touches the website (publishing pipelines, live-page QA
scanners, CDN uploads, CI, the git lifecycle) is `developer` — visible only in Scout's developer
mode; end users draft, plan, research, and report. Pure agent plumbing (`okf-query`,
`confluence`, `jira`) is `false` — never shown. Everything else is `true` with full display
copy (title, blurb, when, category, effects, inputs).

**Effects are load-bearing, not just badges:** `publish` is what routes a Scout run through the
git lifecycle (branch → PR → parked at the gate); everything else stops for review with no PR.
Scout also enforces tiers server-side (a locked instance 403s developer-tier runs), and tron-os
pins the schema with hermetic fixtures in `test/fixtures/plugin-skills/` — if you change a
pinned skill's scout block shape, sync the fixture. Only user-tier skills need full display
copy; `developer`/`false` blocks can stay minimal (surface + effects + inputs).

CI lints every `scout:` block against this shape — `tools/lint/check-scout-frontmatter.sh`
(MD-2027) — since `parseScoutMeta()` in tron-os degrades a malformed block silently instead of
erroring.

## Deterministic scripts

Mechanical flows live in `skills/<name>/scripts/<name>.sh`, and the SKILL.md's "Fast path"
section runs them rather than re-deriving the steps in prose. Each script has a `test-<name>.sh`
sibling — run it after editing the script. Keep the prose steps as a readable fallback/spec, but
the script is the source of truth.

## Reference files & progressive disclosure

Keep the SKILL.md body under 500 lines. When it grows past that (or carries bulky templates,
schemas, or command catalogs), split the detail into `skills/<name>/reference/*.md` and keep
the workflow + judgment in SKILL.md.

- **A reference file must not link another reference file.** SKILL.md links each reference doc
  directly; a doc reachable only through a second reference doc is one Claude may never open, since
  it reads a linked doc partially and follows a chain of them less reliably still. If two reference
  files are both needed, link both from SKILL.md. Linking *out* of the `reference/` layer is not
  chaining, and a reference doc may link exactly two kinds of target: shared prose under
  `tools/<area>/<name>.md` and root-level repo docs (`WORKER_CONTRACT.md`, `README.md`). Those are
  single-source leaves that the rule below tells skills to link rather than restate. That list is
  closed — a reference doc may not link another skill's `SKILL.md` either, since reaching into a
  second skill is a dependency its own SKILL.md should declare, not a link buried at depth two.
  `tools/lint/check-reference-chaining.sh` enforces exactly this. The absolute form of the rule
  forbade what the shared-prose rule requires, and drifted to ten violations unnoticed (MD-2541).
- **Shared prose used by more than one skill lives once under `tools/<area>/<name>.md`** and is
  linked directly from each consuming SKILL.md (still one level deep) — don't copy it into each
  skill's `reference/`. The content image pipeline is the model: the convert → upload → verify
  mechanics live in `tools/image/images-to-imagekit.md`, while `news-item` / `guide-item` /
  `toolkit-item` keep only their own destination folders and naming in their `reference/`.

## Path resolution (two patterns — don't mix them)

- **A skill's own bundled files** resolve through `tools/skill/resolve-skill-dir.sh`. Launchers use
  a small guarded `find` bootstrap to locate that helper when `$CLAUDE_PLUGIN_ROOT` is unavailable,
  then the shared resolver prefers `$CLAUDE_SKILL_DIR`, falls back to
  `$CLAUDE_PLUGIN_ROOT/skills/<name>`, and finally selects the newest installed copy containing the
  requested file across Claude cache/marketplace, Codex cache/marketplace, and the release store.
  Keep the bootstrap block copied verbatim in script-backed skill docs because finding the shared
  helper is the chicken-and-egg step it cannot perform for itself.

  **There is exactly one canonical bootstrap** — the six lines ending in
  `SKILL_DIR="$(bash "$RESOLVER" "$name" <probe>)"`, as in `skills/git-dev/SKILL.md`. Copy it
  verbatim and change only `name=` and the probe path. Do **not** hand-roll a
  `find … -type d -path "*/skills/$name"` that locates the skill dir directly: that variant skips
  the resolver entirely, and with it the version-then-rank precedence (marketplace over cache over
  release store) that decides which installed copy wins when several are present.

  The **first** `<probe>` drives the search and must be a **file**. A skill whose install is only
  valid when several pieces are present passes the rest as extra required paths after it, and those
  may be files or directories: `prose-lint` probes `vale-ini.template styles`, so a partial install
  is skipped rather than resolved and handed a missing `styles/` downstream.
- **Shared `tools/`** resolve through `${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/…` so
  they work from any skill regardless of cwd. The ImageKit CLI invocation convention is
  `IK="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs"; node "$IK" …`.

## Runner-agent delegation (audit skills)

`a11y-scan`, `link-check`, `prose-lint`, `site-audit`, `optimize-images` are
thin orchestrators: the SKILL.md resolves the target and hands off to a matching `agents/*-runner.md`
that does the mechanical run. The **skill** stays cheap (`haiku`); the **agent** carries whatever
model the work needs (e.g. `vale-prose-runner` is `sonnet` for prose judgment).

## Content-pipeline repo guard

`news-item`, `toolkit-item`, `guide-item` write into the `marketing-pages` repo.
They run a preflight check (`tools/content/content.sh check-repo`) and refuse to write unless the
current checkout is `marketing-pages`. Preserve that guard on any content-writing skill.

The guard deliberately does **not** consult the content profile below: a file inside the repo
cannot vouch for the repo. `check-repo` answers *whether* you may write; the profile answers
*where*. Keep them separate.

## Consuming-repo knowledge lives in the repo, not the skill (MD-2451)

Anything true of only one consuming repo is at the wrong layer if it sits in a SKILL.md. The
repo declares its own facts in `.tron/content-profile.json` (`version: 1`) — destinations,
collection schema, permitted components, CDN folders, registration mode, link exceptions — and
the plugin reads them:

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" pipeline   <name> --slug <slug>   # destination, route, components, registration
bash "$C" collection <name>                 # required/optional/enums/defaults
bash "$C" image      <pipeline> <role> …    # uploadFolder, uploadName, reference
bash "$C" paths                             # framework roots: srcDir, pagesRoot, contentRoot (+ <key>Abs)
bash "$C" profile                           # the whole thing (framework, cdn, surfaces, internalLinks)
```

Two rules when you touch a content skill:

- **Never hardcode a consuming repo's paths, schema, or destination folders.** Resolve them.
  Every command above fails loudly, naming the file it looked for and what it needed; a skill
  run against a repo that declares nothing must stop, never guess a path.
- **Write `reference` verbatim.** Each image/download role declares a `valueFormat`
  (`filename`, `cdn-relative-path`, or `absolute-url`) because renderers consume the same asset
  three different ways. `content.sh image` applies the rule; hand-assembling the string is the
  bug this exists to prevent.

Read-only skills resolve the same way. `brand-check`, `landing-page-seo`, `md-to-pdf`,
`jira-source-discovery`, and `circleci` read the repo's declared roots through `content.sh paths`
instead of probing for a conventional directory. Probing is what rots: marketing-pages moved to a
Nuxt 4 `app/` srcDir and left an empty root `pages/` behind, so `[ -d "$repo/pages" ]` still
succeeded and the search that followed found nothing — reported as "no existing page", which scopes
a redesign ticket as net-new.

`seo-report` is **not** migrated: it depends on tron-search-console, which declares no profile. It
keeps its paths in the skill until that repo lands one — deferring is correct here, half-migrating
is not.

## Conventions when authoring copy-producing skills

- **Facilitron voice: no em dashes** in produced copy. Several skills restate this — when you add
  one, follow suit.
- Git-free drafting/audit skills (SEO, designer, drafting, manager, video, social) report and hand
  off; they never branch/commit. Say so in the description.

## Versioning + release

- Bump `version` in `.claude-plugin/plugin.json` when shipping skill changes — the `SessionStart`
  hook (`hooks/check-update.sh`) compares installed vs `master` daily and nudges stale installs.
- Keep `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` at the same version.
- Every skill must have exactly one owner in `packages/package-map.json`. A role may include a
  skill owned elsewhere when its runtime requires it; generated packages copy that skill and its
  dependency closure from the single authored `skills/` source.
- Keep package resource closures explicit in `packages/package-map.json`; do not infer shared
  tools or agents from prose. Cross-package handoffs are rewritten to the target skill's declared
  owner and validated during the build.
- `packages/package-map.json` also carries a `repos` block: one bundle per consuming repo, in the
  same `extends` / `skills` / `resources` shape as a role package, so a dispatched worker sees only
  the skills its repo actually uses. A repo key builds as `tron-repo-<key>` (`marketing-pages` →
  `tron-repo-marketing-pages`) and releases alongside the role packages, attested and checksummed
  the same way. Repo bundles extend role packages (in practice `core`); they may not extend each
  other, and nothing may extend them. Which bundle a repo gets is tron-os's call; what is in the
  bundle is this repo's.
- Run `bash tools/package/test-build-packages.sh` after changing package ownership, repo bundles,
  shared paths, cross-skill handoffs, agents, or skill-local assets.
- Local authoring loop: add the checkout as a directory marketplace
  (`/plugin marketplace add /path/to/tron-marketing-ai`) so edits apply without a push round-trip.
