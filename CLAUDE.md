# CLAUDE.md — working on the `tron` plugin

This repo **is a Claude Code plugin**, not an app. There's nothing to build or serve — the
deliverable is the instruction layer itself: `skills/*/SKILL.md`, `agents/*.md`, the bundled
`tools/`, and `hooks/`. Editing those files _is_ the work. See [README.md](README.md) for the
consumer-facing install/dependency docs; this file is for editing the plugin.

## Layout

- `skills/<name>/SKILL.md` — one dir per skill; the markdown body is the instructions.
- `skills/<name>/scripts/` — deterministic bash that the SKILL.md shells out to (see below).
- `agents/*.md` — cost-scoped runner subagents the audit skills delegate the mechanical run to.
- `tools/` — shared, multi-skill tooling, resolved via `CLAUDE_PLUGIN_ROOT` (see Path resolution).
- `.claude-plugin/{plugin.json,marketplace.json}` — manifest + single-plugin marketplace.

## SKILL.md frontmatter

Every skill declares `name`, `description`, `model`, `effort`, and (when it needs more than the
default) `allowed-tools`. The `description` is the **only** thing the router sees — it must carry
the trigger phrases, so keep it dense and example-heavy.

### Model + effort routing (deliberate — match the tier to the work)

| Tier                      | Use for                                                                  | Examples                                                                                        |
| ------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `haiku` / `low`           | Pure orchestration — resolve a target, shell out, hand off. No judgment. | `jira`, `confluence`, all 5 audit skills (the _agent_ does any heavier work)                    |
| `sonnet` / `low`–`medium` | Most skills: light judgment, drafting, git flows, board ops.             | `git-commit`, `seo-audit`, `board-triage`, `figma-to-imagekit`                                  |
| `opus` / `high`           | Long-form generation and critique where quality dominates cost.          | `news-item`, `guide-item`, `toolkit-item`, `case-study`, `press-release`, `brainstorm`, `grill` |

When you add or edit a skill, pick the cheapest tier that does the job. An orchestration-only
skill set to `sonnet` is a routing bug (this is what was wrong with `a11y-scan`). If a skill says
"runs on Haiku to keep cost low," its frontmatter must agree.

## Deterministic scripts

Mechanical flows live in `skills/<name>/scripts/<name>.sh`, and the SKILL.md's "Fast path"
section runs them rather than re-deriving the steps in prose. Each script has a `test-<name>.sh`
sibling — run it after editing the script. Keep the prose steps as a readable fallback/spec, but
the script is the source of truth.

## Path resolution (two patterns — don't mix them)

- **A skill's own bundled files** resolve through the robust resolver block (copied verbatim into
  each script-backed skill). It prefers `$CLAUDE_SKILL_DIR`, falls back to
  `$CLAUDE_PLUGIN_ROOT/skills/<name>`, then to the newest _installed_ copy that actually contains
  the script. This boilerplate is **intentional** (`$CLAUDE_SKILL_DIR` isn't always exported under
  the headless worker) — do not "DRY it up" into a sourced helper; sourcing has the same
  chicken-and-egg path problem it exists to solve.
- **Shared `tools/`** resolve through `${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/…` so
  they work from any skill regardless of cwd. The ImageKit CLI invocation convention is
  `IK="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs"; node "$IK" …`.

## Runner-agent delegation (audit skills)

`a11y-scan`, `link-check`, `prose-lint`, `site-audit`, `optimize-images` are
thin orchestrators: the SKILL.md resolves the target and hands off to a matching `agents/*-runner.md`
that does the mechanical run. The **skill** stays cheap (`haiku`); the **agent** carries whatever
model the work needs (e.g. `vale-prose-runner` is `sonnet` for prose judgment). Keep the skill's
declared model and its delegation note in sync.

## Content-pipeline repo guard

`news-item`, `toolkit-item`, `guide-item`, `preview-page` write into the `marketing-pages` repo.
They run a preflight check (`tools/content/content.sh check-repo`) and refuse to write unless the
current checkout is `marketing-pages`. Preserve that guard on any content-writing skill.

## Conventions when authoring copy-producing skills

- **Facilitron voice: no em dashes** in produced copy. Several skills restate this — when you add
  one, follow suit.
- Git-free drafting/audit skills (SEO, designer, drafting, manager, video, social) report and hand
  off; they never branch/commit. Say so in the description.

## Versioning + release

- Bump `version` in `.claude-plugin/plugin.json` when shipping skill changes — the `SessionStart`
  hook (`hooks/check-update.sh`) compares installed vs `master` daily and nudges stale installs.
- Local authoring loop: add the checkout as a directory marketplace
  (`/plugin marketplace add /path/to/tron-marketing-ai`) so edits apply without a push round-trip.
