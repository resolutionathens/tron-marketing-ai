---
name: prose-lint
model: haiku
effort: low
description: "Lint prose, marketing copy, blog posts, SOPs, and other markdown content with Vale to enforce style, terminology, and readability rules. Use for 'run vale', 'lint this content', 'check the prose', 'proofread this', or 'enforce the style guide'. Also trigger when the user is finalizing marketing copy, blog/cluster articles, toolkit items, or other content/*.md files and wants a quality pass before publish."
allowed-tools:
  - Task
  - Bash
scout:
  surface: true
  title: "Check writing style"
  blurb: "Runs copy against the Facilitron style guide — terminology, readability, and consistency — and lists what to fix."
  when: "Copy is nearly final and needs a mechanical style pass."
  category: qa
  effects: [report]
  inputs:
    - key: target
      label: "Draft path"
      type: path
      required: true
      placeholder: "Pick the markdown / draft to lint"
      accept: ".md,.markdown,.txt"
---

# /prose-lint — Prose / style lint

This skill delegates the lint to the **`vale-prose-runner`** subagent (runs on Sonnet — the findings need light prose judgment). Your job is to resolve the target, tell the runner where the Facilitron style pack lives, and hand off — **don't run vale yourself.**

## What to do

1. **Resolve the target:** a file/dir the user named → else `content/` if it exists → else project root.
2. **Resolve the style-pack path.** It ships with this plugin under the skill's `styles/` dir (rules under `styles/Facilitron/`, vocab under `styles/config/vocabularies/Facilitron/accept.txt`). Resolve the skill dir robustly — `$CLAUDE_SKILL_DIR` is not always exported into Bash — and pass the **absolute** `styles/` path to the runner:
   ```bash
   name=prose-lint
   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
   RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
   [ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
   [ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
   SKILL_DIR="$(bash "$RESOLVER" "$name" vale-ini.template)"
   echo "$SKILL_DIR/styles"   # → the absolute style-pack path to hand the runner
   ```
3. **Delegate to `vale-prose-runner`** (Task tool): "Lint `<target>` with Vale using the Facilitron style pack at `<absolute styles path>` (scaffold `.vale.ini` + symlinks if missing). Return findings grouped by file with severity counts and the top offenders." If the user wants an errors-only gate (pre-commit/PR), say so in the prompt.
4. **Relay the runner's grouped findings.** If it reports vale isn't installed, surface `brew install vale`.

## Notes

- The Facilitron style pack is bundled with the plugin (`styles/Facilitron/` rules + `styles/config/vocabularies/Facilitron/accept.txt` vocab) — shared across repos. To accept a false-positive term, append it to `accept.txt` and the change ships with the next plugin release.
- The runner handles project scaffolding (symlinks, `.vale.ini`, `vale sync`) — `.vale.ini` is copied verbatim from the bundled `vale-ini.template` (next to `styles/`) and committed; `.vale/styles/` is gitignored.
- Good final pass before `tron:news-item` / `tron:guide-item` / `tron:case-study` / `tron:press-release` open their PR.
